use std::collections::{HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context, Result};
use dashmap::DashMap;
use once_cell::sync::Lazy;
use russh::client::{self, KeyboardInteractiveAuthResponse};
use russh::keys::{decode_secret_key, HashAlg, PrivateKey, PrivateKeyWithHashAlg};
use russh::{ChannelMsg, ChannelWriteHalf, Disconnect};
use russh_sftp::client::SftpSession;
use russh_sftp::protocol::FileType;
use tokio::sync::{Mutex, Notify};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
};
use zeroize::Zeroize;

const MAX_BUFFER_BYTES: usize = 2 * 1024 * 1024;
const MAX_READ_BYTES: usize = 256 * 1024;
const RETAINED_BUFFER_BYTES: usize = 128 * 1024;
const READ_BATCH_BYTES: usize = 64 * 1024;
const READ_COALESCE_MILLIS: u64 = 2;

static NEXT_ID: AtomicI64 = AtomicI64::new(1);
static SSH_SESSIONS: Lazy<DashMap<i64, Arc<SshSession>>> = Lazy::new(DashMap::new);
static PENDING_AUTHS: Lazy<DashMap<i64, PendingAuthentication>> = Lazy::new(DashMap::new);
static SFTP_SESSIONS: Lazy<DashMap<i64, Arc<SftpSessionState>>> = Lazy::new(DashMap::new);
static SSH_EXEC_CANCELLATIONS: Lazy<DashMap<i64, Arc<Notify>>> = Lazy::new(DashMap::new);
static SSH_TUNNELS: Lazy<DashMap<i64, Arc<SshTunnel>>> = Lazy::new(DashMap::new);

#[derive(Clone)]
pub struct RustSshConnectRequest {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth_kind: String,
    pub password: String,
    pub private_key_pem: String,
    pub passphrase: Option<String>,
    pub trusted_host_keys: Vec<String>,
    pub terminal_width: u32,
    pub terminal_height: u32,
    pub jump_hosts: Vec<RustSshJumpHost>,
}

#[derive(Clone)]
pub struct RustSshJumpHost {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth_kind: String,
    pub password: String,
    pub private_key_pem: String,
    pub passphrase: Option<String>,
    pub trusted_host_keys: Vec<String>,
}

#[derive(Clone)]
pub struct RustHostKey {
    pub algorithm: String,
    pub fingerprint_sha256: String,
}

#[derive(Clone)]
pub struct RustInteractivePrompt {
    pub text: String,
    pub echo: bool,
}

#[derive(Clone)]
pub struct RustAuthChallenge {
    pub name: String,
    pub instruction: String,
    pub prompts: Vec<RustInteractivePrompt>,
}

pub struct RustSshConnectResult {
    pub session_id: Option<i64>,
    pub pending_auth_id: Option<i64>,
    pub host_key: Option<RustHostKey>,
    pub challenge: Option<RustAuthChallenge>,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
}

pub struct RustSshReadResult {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub closed: bool,
    pub error_message: Option<String>,
}

#[derive(Clone)]
pub struct RustSshExecRequest {
    pub execution_id: i64,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth_kind: String,
    pub password: String,
    pub private_key_pem: String,
    pub passphrase: Option<String>,
    pub trusted_host_keys: Vec<String>,
    pub command: String,
    pub timeout_millis: u32,
    pub output_limit_bytes: u32,
}

pub struct RustSshExecResult {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub exit_status: Option<u32>,
    pub timed_out: bool,
    pub cancelled: bool,
    pub truncated: bool,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
}

pub struct RustKeyDecodeDiagnostics {
    pub selected_path: String,
    pub aarch64: bool,
    pub neon: bool,
    pub sve: bool,
    pub sve2: bool,
    pub aes: bool,
    pub sha2: bool,
    pub p50_microseconds: u64,
    pub p95_microseconds: u64,
    pub successful_iterations: u32,
}

pub struct RustSshTunnelStartRequest {
    pub session_id: i64,
    pub kind: String,
    pub bind_host: String,
    pub bind_port: u16,
    pub target_host: String,
    pub target_port: u16,
    pub allow_lan: bool,
}

pub struct RustSshTunnelStatus {
    pub tunnel_id: i64,
    pub kind: String,
    pub bind_host: String,
    pub bind_port: u16,
    pub bytes_up: u64,
    pub bytes_down: u64,
    pub active: bool,
    pub error_message: Option<String>,
}

#[derive(Clone)]
pub struct RustSftpConnectRequest {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth_kind: String,
    pub password: String,
    pub private_key_pem: String,
    pub passphrase: Option<String>,
    pub trusted_host_keys: Vec<String>,
}

pub struct RustSftpConnectResult {
    pub session_id: Option<i64>,
    pub host_key: Option<RustHostKey>,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
}

pub struct RustSftpEntry {
    pub name: String,
    pub kind: String,
    pub size: Option<i64>,
    pub modified_seconds: Option<i64>,
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub async fn ssh_connect(request: RustSshConnectRequest) -> Result<RustSshConnectResult> {
    if !request.jump_hosts.is_empty() {
        return ssh_connect_via_jumps(request).await;
    }
    let observed = Arc::new(StdMutex::new(None));
    let handler = HostKeyHandler {
        trusted: request.trusted_host_keys.iter().cloned().collect(),
        observed: Arc::clone(&observed),
    };
    let mut client = match connect_client(&request.host, request.port, handler).await {
        Ok(client) => client,
        Err(error) => {
            if let Some(host_key) = observed.lock().expect("host key mutex poisoned").clone() {
                return Ok(connect_error("host_key_untrusted", error, Some(host_key)));
            }
            return Ok(connect_error("connection_failed", error, None));
        }
    };

    match authenticate(&mut client, &request).await {
        Ok(AuthenticationOutcome::Complete) => {
            finalize_ssh_session(
                client,
                Vec::new(),
                request.terminal_width,
                request.terminal_height,
            )
            .await
        }
        Ok(AuthenticationOutcome::Challenge(challenge)) => {
            let id = next_id();
            PENDING_AUTHS.insert(
                id,
                PendingAuthentication {
                    client,
                    terminal_width: request.terminal_width,
                    terminal_height: request.terminal_height,
                    jump_clients: Vec::new(),
                },
            );
            Ok(RustSshConnectResult {
                session_id: None,
                pending_auth_id: Some(id),
                host_key: None,
                challenge: Some(challenge),
                error_code: None,
                error_message: None,
            })
        }
        Err(error) => Ok(connect_error("authentication_failed", error, None)),
    }
}

pub async fn ssh_continue_authentication(
    pending_auth_id: i64,
    responses: Vec<String>,
) -> Result<RustSshConnectResult> {
    let (_, mut pending) = PENDING_AUTHS
        .remove(&pending_auth_id)
        .ok_or_else(|| anyhow!("Authentication request expired"))?;
    match pending
        .client
        .authenticate_keyboard_interactive_respond(responses)
        .await
        .context("Keyboard-interactive authentication failed")?
    {
        KeyboardInteractiveAuthResponse::Success => {
            finalize_ssh_session(
                pending.client,
                pending.jump_clients,
                pending.terminal_width,
                pending.terminal_height,
            )
            .await
        }
        KeyboardInteractiveAuthResponse::InfoRequest {
            name,
            instructions,
            prompts,
        } => {
            PENDING_AUTHS.insert(pending_auth_id, pending);
            Ok(RustSshConnectResult {
                session_id: None,
                pending_auth_id: Some(pending_auth_id),
                host_key: None,
                challenge: Some(RustAuthChallenge {
                    name,
                    instruction: instructions,
                    prompts: prompts
                        .into_iter()
                        .map(|prompt| RustInteractivePrompt {
                            text: prompt.prompt,
                            echo: prompt.echo,
                        })
                        .collect(),
                }),
                error_code: None,
                error_message: None,
            })
        }
        KeyboardInteractiveAuthResponse::Failure { .. } => Ok(connect_error(
            "authentication_failed",
            anyhow!("Keyboard-interactive authentication was rejected"),
            None,
        )),
    }
}

pub async fn ssh_read(
    session_id: i64,
    max_bytes: u32,
    wait_millis: u32,
) -> Result<RustSshReadResult> {
    let session = get_ssh_session(session_id)?;
    let limit = (max_bytes as usize).clamp(1, MAX_READ_BYTES);
    let mut coalesce_deadline = None;
    loop {
        let notified = session.data_ready.notified();
        let mut has_buffered_data = false;
        {
            let mut output = session.output.lock().await;
            if output.len() > 0 || session.closed.load(Ordering::Acquire) {
                has_buffered_data = output.len() > 0;
                let interactive_response = has_buffered_data
                    && session
                        .interactive_response_pending
                        .swap(false, Ordering::AcqRel);
                let batch_ready = interactive_response
                    || output.len() >= limit.min(READ_BATCH_BYTES)
                    || session.closed.load(Ordering::Acquire)
                    || coalesce_deadline.is_some_and(|deadline| Instant::now() >= deadline);
                if batch_ready {
                    let stdout = drain_queue(&mut output.stdout, limit);
                    let stderr =
                        drain_queue(&mut output.stderr, limit.saturating_sub(stdout.len()));
                    let error_message = output.error.take();
                    drop(output);
                    session.space_ready.notify_waiters();
                    return Ok(RustSshReadResult {
                        stdout,
                        stderr,
                        closed: session.closed.load(Ordering::Acquire),
                        error_message,
                    });
                }
                coalesce_deadline.get_or_insert_with(|| {
                    Instant::now() + Duration::from_millis(READ_COALESCE_MILLIS)
                });
            }
        }
        let wait = if has_buffered_data {
            coalesce_deadline
                .expect("buffered SSH data has a coalescing deadline")
                .saturating_duration_since(Instant::now())
        } else {
            Duration::from_millis(wait_millis as u64)
        };
        if tokio::time::timeout(wait, notified).await.is_err() {
            if has_buffered_data {
                continue;
            }
            session.output.lock().await.release_excess_capacity();
            return Ok(RustSshReadResult {
                stdout: Vec::new(),
                stderr: Vec::new(),
                closed: false,
                error_message: None,
            });
        }
    }
}

pub async fn ssh_write(session_id: i64, data: Vec<u8>) -> Result<()> {
    let session = get_ssh_session(session_id)?;
    session
        .interactive_response_pending
        .store(true, Ordering::Release);
    let result = session
        .writer
        .lock()
        .await
        .data(&data[..])
        .await
        .context("Failed to write SSH channel");
    result
}

pub async fn ssh_resize(
    session_id: i64,
    width: u32,
    height: u32,
    pixel_width: u32,
    pixel_height: u32,
) -> Result<()> {
    let session = get_ssh_session(session_id)?;
    let result = session
        .writer
        .lock()
        .await
        .window_change(width, height, pixel_width, pixel_height)
        .await
        .context("Failed to resize SSH PTY");
    result
}

pub async fn ssh_close(session_id: i64) -> Result<()> {
    let Some((_, session)) = SSH_SESSIONS.remove(&session_id) else {
        return Ok(());
    };
    session.closed.store(true, Ordering::Release);
    session.data_ready.notify_waiters();
    session.space_ready.notify_waiters();
    let tunnel_ids: Vec<i64> = SSH_TUNNELS
        .iter()
        .filter(|entry| entry.session_id == session_id)
        .map(|entry| *entry.key())
        .collect();
    for tunnel_id in tunnel_ids {
        ssh_stop_tunnel(tunnel_id);
    }
    let _ = session.writer.lock().await.close().await;
    if let Some(client) = session.client.lock().await.take() {
        let _ = client
            .disconnect(Disconnect::ByApplication, "", "English")
            .await;
    }
    for client in session.jump_clients.lock().await.drain(..).rev() {
        let _ = client
            .disconnect(Disconnect::ByApplication, "", "English")
            .await;
    }
    Ok(())
}

pub async fn ssh_execute(request: RustSshExecRequest) -> Result<RustSshExecResult> {
    let timeout_millis = request.timeout_millis.clamp(1_000, 120_000);
    let output_limit = (request.output_limit_bytes as usize).clamp(1_024, 1024 * 1024);
    let cancellation = Arc::new(Notify::new());
    SSH_EXEC_CANCELLATIONS.insert(request.execution_id, Arc::clone(&cancellation));
    let execution = execute_ssh_command(&request, output_limit);
    let result = tokio::select! {
        _ = cancellation.notified() => RustSshExecResult {
            stdout: Vec::new(), stderr: Vec::new(), exit_status: None,
            timed_out: false, cancelled: true, truncated: false,
            error_code: Some("cancelled".to_owned()),
            error_message: Some("SSH command was cancelled".to_owned()),
        },
        value = tokio::time::timeout(Duration::from_millis(timeout_millis as u64), execution) => {
            match value {
                Ok(Ok(result)) => result,
                Ok(Err(error)) => RustSshExecResult {
                    stdout: Vec::new(), stderr: Vec::new(), exit_status: None,
                    timed_out: false, cancelled: false, truncated: false,
                    error_code: Some("execution_failed".to_owned()),
                    error_message: Some(format!("{error:#}")),
                },
                Err(_) => RustSshExecResult {
                    stdout: Vec::new(), stderr: Vec::new(), exit_status: None,
                    timed_out: true, cancelled: false, truncated: false,
                    error_code: Some("timeout".to_owned()),
                    error_message: Some("SSH command timed out".to_owned()),
                },
            }
        }
    };
    SSH_EXEC_CANCELLATIONS.remove(&request.execution_id);
    Ok(result)
}

pub fn ssh_cancel_execution(execution_id: i64) {
    if let Some(cancellation) = SSH_EXEC_CANCELLATIONS.get(&execution_id) {
        cancellation.notify_waiters();
    }
}

pub fn private_key_is_encrypted(pem: String) -> bool {
    if pem.contains("BEGIN ENCRYPTED PRIVATE KEY") || pem.contains("DEK-Info:") {
        return true;
    }
    if pem.trim_start().starts_with("PuTTY-User-Key-File-") {
        return pem
            .lines()
            .any(|line| line.trim() != "Encryption: none" && line.starts_with("Encryption:"));
    }
    PrivateKey::from_openssh(&pem)
        .map(|key| key.is_encrypted())
        .unwrap_or(false)
}

pub fn validate_private_key(pem: String, passphrase: Option<String>) -> Result<()> {
    decode_secret_key(&pem, passphrase.as_deref())
        .map(|_| ())
        .context("Invalid or unsupported private key")
}

pub fn key_decode_diagnostics(
    mut pem: String,
    mut passphrase: Option<String>,
    iterations: u32,
) -> Result<RustKeyDecodeDiagnostics> {
    let sample_count = iterations.clamp(3, 100);
    let features = runtime_key_decode_features();
    let mut measurements = Vec::with_capacity(sample_count as usize);
    let mut successful_iterations = 0;
    for _ in 0..sample_count {
        let started = Instant::now();
        let decoded = decode_secret_key(&pem, passphrase.as_deref())
            .context("Invalid or unsupported private key")?;
        measurements.push(started.elapsed().as_micros().min(u64::MAX as u128) as u64);
        successful_iterations += 1;
        drop(decoded);
    }
    measurements.sort_unstable();
    let p50 = percentile(&measurements, 50);
    let p95 = percentile(&measurements, 95);
    pem.zeroize();
    if let Some(secret) = passphrase.as_mut() {
        secret.zeroize();
    }
    Ok(RustKeyDecodeDiagnostics {
        selected_path: "portable".to_owned(),
        aarch64: features.aarch64,
        neon: features.neon,
        sve: features.sve,
        sve2: features.sve2,
        aes: features.aes,
        sha2: features.sha2,
        p50_microseconds: p50,
        p95_microseconds: p95,
        successful_iterations,
    })
}

struct KeyDecodeFeatures {
    aarch64: bool,
    neon: bool,
    sve: bool,
    sve2: bool,
    aes: bool,
    sha2: bool,
}

fn runtime_key_decode_features() -> KeyDecodeFeatures {
    #[cfg(target_arch = "aarch64")]
    {
        KeyDecodeFeatures {
            aarch64: true,
            neon: std::arch::is_aarch64_feature_detected!("neon"),
            sve: std::arch::is_aarch64_feature_detected!("sve"),
            sve2: std::arch::is_aarch64_feature_detected!("sve2"),
            aes: std::arch::is_aarch64_feature_detected!("aes"),
            sha2: std::arch::is_aarch64_feature_detected!("sha2"),
        }
    }
    #[cfg(not(target_arch = "aarch64"))]
    {
        KeyDecodeFeatures {
            aarch64: false,
            neon: false,
            sve: false,
            sve2: false,
            aes: false,
            sha2: false,
        }
    }
}

fn percentile(values: &[u64], percentile: usize) -> u64 {
    let index = ((values.len() - 1) * percentile).div_ceil(100);
    values[index.min(values.len() - 1)]
}

async fn forward_direct(
    mut socket: TcpStream,
    origin: std::net::SocketAddr,
    session: Arc<SshSession>,
    target_host: String,
    target_port: u16,
    tunnel: &SshTunnel,
) -> Result<()> {
    let channel = {
        let client = session.client.lock().await;
        client
            .as_ref()
            .context("SSH session is closed")?
            .channel_open_direct_tcpip(
                target_host,
                target_port.into(),
                origin.ip().to_string(),
                origin.port().into(),
            )
            .await
            .context("SSH server rejected direct-tcpip")?
    };
    let mut stream = channel.into_stream();
    let (up, down) = tokio::io::copy_bidirectional(&mut socket, &mut stream).await?;
    tunnel.bytes_up.fetch_add(up, Ordering::AcqRel);
    tunnel.bytes_down.fetch_add(down, Ordering::AcqRel);
    Ok(())
}

async fn forward_socks5(
    mut socket: TcpStream,
    origin: std::net::SocketAddr,
    session: Arc<SshSession>,
    tunnel: &SshTunnel,
) -> Result<()> {
    let version = socket.read_u8().await?;
    let method_count = socket.read_u8().await? as usize;
    let mut methods = vec![0; method_count];
    socket.read_exact(&mut methods).await?;
    if version != 5 || !methods.contains(&0) {
        socket.write_all(&[5, 0xff]).await?;
        return Err(anyhow!("SOCKS5 authentication method is unsupported"));
    }
    socket.write_all(&[5, 0]).await?;
    if socket.read_u8().await? != 5 || socket.read_u8().await? != 1 {
        return Err(anyhow!("SOCKS5 command is unsupported"));
    }
    let _reserved = socket.read_u8().await?;
    let host = match socket.read_u8().await? {
        1 => {
            let mut bytes = [0; 4];
            socket.read_exact(&mut bytes).await?;
            std::net::Ipv4Addr::from(bytes).to_string()
        }
        3 => {
            let length = socket.read_u8().await? as usize;
            let mut bytes = vec![0; length];
            socket.read_exact(&mut bytes).await?;
            String::from_utf8(bytes)?
        }
        4 => {
            let mut bytes = [0; 16];
            socket.read_exact(&mut bytes).await?;
            std::net::Ipv6Addr::from(bytes).to_string()
        }
        _ => return Err(anyhow!("SOCKS5 address type is unsupported")),
    };
    let port = socket.read_u16().await?;
    let channel = {
        let client = session.client.lock().await;
        client
            .as_ref()
            .context("SSH session is closed")?
            .channel_open_direct_tcpip(
                host,
                port.into(),
                origin.ip().to_string(),
                origin.port().into(),
            )
            .await
            .context("SSH server rejected SOCKS5 destination")?
    };
    socket.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0]).await?;
    let mut stream = channel.into_stream();
    let (up, down) = tokio::io::copy_bidirectional(&mut socket, &mut stream).await?;
    tunnel.bytes_up.fetch_add(up, Ordering::AcqRel);
    tunnel.bytes_down.fetch_add(down, Ordering::AcqRel);
    Ok(())
}

pub async fn ssh_start_tunnel(request: RustSshTunnelStartRequest) -> Result<RustSshTunnelStatus> {
    if request.kind != "local" && request.kind != "socks5" {
        return Err(anyhow!("Unsupported SSH tunnel kind"));
    }
    if !request.allow_lan && request.bind_host != "127.0.0.1" {
        return Err(anyhow!("LAN tunnel binding requires explicit permission"));
    }
    if request.kind == "local" && (request.target_host.is_empty() || request.target_port == 0) {
        return Err(anyhow!("Local forwarding target is invalid"));
    }
    let session = SSH_SESSIONS
        .get(&request.session_id)
        .map(|entry| Arc::clone(entry.value()))
        .context("SSH session is not active")?;
    if session.client.lock().await.is_none() {
        return Err(anyhow!("SSH session is closed"));
    }
    let listener = TcpListener::bind((request.bind_host.as_str(), request.bind_port))
        .await
        .context("Failed to bind SSH tunnel")?;
    let local = listener
        .local_addr()
        .context("Tunnel bind address is unavailable")?;
    let tunnel_id = next_id();
    let tunnel = Arc::new(SshTunnel {
        session_id: request.session_id,
        kind: request.kind.clone(),
        bind_host: local.ip().to_string(),
        bind_port: local.port(),
        bytes_up: AtomicU64::new(0),
        bytes_down: AtomicU64::new(0),
        active: AtomicBool::new(true),
        error: StdMutex::new(None),
        stop: Notify::new(),
    });
    SSH_TUNNELS.insert(tunnel_id, Arc::clone(&tunnel));
    let target_host = request.target_host;
    let target_port = request.target_port;
    tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = tunnel.stop.notified() => break,
                accepted = listener.accept() => match accepted {
                    Ok((socket, origin)) => {
                        let session = Arc::clone(&session);
                        let tunnel = Arc::clone(&tunnel);
                        let kind = request.kind.clone();
                        let target_host = target_host.clone();
                        tokio::spawn(async move {
                            let outcome = if kind == "socks5" {
                                forward_socks5(socket, origin, session, &tunnel).await
                            } else {
                                forward_direct(socket, origin, session, target_host, target_port, &tunnel).await
                            };
                            if let Err(error) = outcome {
                                *tunnel.error.lock().expect("tunnel error mutex poisoned") = Some(format!("{error:#}"));
                            }
                        });
                    }
                    Err(error) => {
                        *tunnel.error.lock().expect("tunnel error mutex poisoned") = Some(error.to_string());
                        break;
                    }
                }
            }
        }
        tunnel.active.store(false, Ordering::Release);
    });
    ssh_tunnel_status(tunnel_id)
}

pub fn ssh_tunnel_status(tunnel_id: i64) -> Result<RustSshTunnelStatus> {
    let tunnel = SSH_TUNNELS
        .get(&tunnel_id)
        .context("SSH tunnel not found")?;
    let error_message = tunnel
        .error
        .lock()
        .expect("tunnel error mutex poisoned")
        .clone();
    Ok(RustSshTunnelStatus {
        tunnel_id,
        kind: tunnel.kind.clone(),
        bind_host: tunnel.bind_host.clone(),
        bind_port: tunnel.bind_port,
        bytes_up: tunnel.bytes_up.load(Ordering::Acquire),
        bytes_down: tunnel.bytes_down.load(Ordering::Acquire),
        active: tunnel.active.load(Ordering::Acquire),
        error_message,
    })
}

pub fn ssh_stop_tunnel(tunnel_id: i64) {
    if let Some((_, tunnel)) = SSH_TUNNELS.remove(&tunnel_id) {
        tunnel.active.store(false, Ordering::Release);
        tunnel.stop.notify_waiters();
    }
}

pub async fn sftp_connect(request: RustSftpConnectRequest) -> Result<RustSftpConnectResult> {
    let observed = Arc::new(StdMutex::new(None));
    let handler = HostKeyHandler {
        trusted: request.trusted_host_keys.iter().cloned().collect(),
        observed: Arc::clone(&observed),
    };
    let mut client = match connect_client(&request.host, request.port, handler).await {
        Ok(client) => client,
        Err(error) => {
            if let Some(host_key) = observed.lock().expect("host key mutex poisoned").clone() {
                return Ok(sftp_connect_error(
                    "host_key_untrusted",
                    error,
                    Some(host_key),
                ));
            }
            return Ok(sftp_connect_error("connection_failed", error, None));
        }
    };
    if let Err(error) = authenticate_sftp(&mut client, &request).await {
        return Ok(sftp_connect_error("authentication_failed", error, None));
    }
    let channel = client
        .channel_open_session()
        .await
        .context("Failed to open SFTP channel")?;
    channel
        .request_subsystem(true, "sftp")
        .await
        .context("SFTP subsystem was rejected")?;
    let sftp = SftpSession::new(channel.into_stream())
        .await
        .context("SFTP handshake failed")?;
    let path = sftp
        .canonicalize(".")
        .await
        .context("SFTP home path failed")?;
    let id = next_id();
    SFTP_SESSIONS.insert(
        id,
        Arc::new(SftpSessionState {
            client: Mutex::new(Some(client)),
            sftp,
            path: Mutex::new(path),
        }),
    );
    Ok(RustSftpConnectResult {
        session_id: Some(id),
        host_key: None,
        error_code: None,
        error_message: None,
    })
}

pub async fn sftp_current_directory(session_id: i64) -> Result<String> {
    Ok(get_sftp_session(session_id)?.path.lock().await.clone())
}

pub async fn sftp_list_directory(session_id: i64) -> Result<Vec<RustSftpEntry>> {
    let session = get_sftp_session(session_id)?;
    let path = session.path.lock().await.clone();
    let entries = session
        .sftp
        .read_dir(path)
        .await
        .context("Failed to list SFTP directory")?;
    Ok(entries
        .map(|entry| {
            let metadata = entry.metadata();
            RustSftpEntry {
                name: entry.file_name(),
                kind: match entry.file_type() {
                    FileType::Dir => "directory",
                    FileType::File => "file",
                    FileType::Symlink => "link",
                    _ => "unknown",
                }
                .to_owned(),
                size: metadata.size.and_then(|value| i64::try_from(value).ok()),
                modified_seconds: metadata.mtime.map(i64::from),
            }
        })
        .collect())
}

pub async fn sftp_change_directory(session_id: i64, path: String) -> Result<()> {
    let session = get_sftp_session(session_id)?;
    let target = resolve_sftp_path(&session, &path).await;
    let metadata = session
        .sftp
        .metadata(target.clone())
        .await
        .context("Failed to inspect SFTP directory")?;
    if !metadata.is_dir() {
        return Err(anyhow!("SFTP path is not a directory"));
    }
    let canonical = session
        .sftp
        .canonicalize(target)
        .await
        .context("Failed to resolve SFTP directory")?;
    *session.path.lock().await = canonical;
    Ok(())
}

pub async fn sftp_create_directory(session_id: i64, name: String) -> Result<()> {
    let session = get_sftp_session(session_id)?;
    let target = resolve_sftp_path(&session, &name).await;
    session
        .sftp
        .create_dir(target)
        .await
        .context("Failed to create SFTP directory")
}

pub async fn sftp_rename(session_id: i64, old_name: String, new_name: String) -> Result<()> {
    let session = get_sftp_session(session_id)?;
    let old_path = resolve_sftp_path(&session, &old_name).await;
    let new_path = resolve_sftp_path(&session, &new_name).await;
    session
        .sftp
        .rename(old_path, new_path)
        .await
        .context("Failed to rename SFTP entry")
}

pub async fn sftp_delete_file(session_id: i64, name: String) -> Result<()> {
    let session = get_sftp_session(session_id)?;
    let target = resolve_sftp_path(&session, &name).await;
    session
        .sftp
        .remove_file(target)
        .await
        .context("Failed to delete SFTP file")
}

pub async fn sftp_delete_empty_directory(session_id: i64, name: String) -> Result<()> {
    let session = get_sftp_session(session_id)?;
    let target = resolve_sftp_path(&session, &name).await;
    session
        .sftp
        .remove_dir(target)
        .await
        .context("Failed to delete SFTP directory")
}

pub async fn sftp_close(session_id: i64) -> Result<()> {
    let Some((_, session)) = SFTP_SESSIONS.remove(&session_id) else {
        return Ok(());
    };
    let _ = session.sftp.close().await;
    if let Some(client) = session.client.lock().await.take() {
        let _ = client
            .disconnect(Disconnect::ByApplication, "", "English")
            .await;
    }
    Ok(())
}

struct HostKeyHandler {
    trusted: HashSet<String>,
    observed: Arc<StdMutex<Option<RustHostKey>>>,
}

impl client::Handler for HostKeyHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &russh::keys::PublicKey,
    ) -> std::result::Result<bool, Self::Error> {
        let host_key = RustHostKey {
            algorithm: server_public_key.algorithm().as_str().to_owned(),
            fingerprint_sha256: server_public_key.fingerprint(HashAlg::Sha256).to_string(),
        };
        let identity = host_key_identity(&host_key);
        *self.observed.lock().expect("host key mutex poisoned") = Some(host_key);
        Ok(self.trusted.contains(&identity))
    }
}

enum AuthenticationOutcome {
    Complete,
    Challenge(RustAuthChallenge),
}

struct PendingAuthentication {
    client: client::Handle<HostKeyHandler>,
    jump_clients: Vec<client::Handle<HostKeyHandler>>,
    terminal_width: u32,
    terminal_height: u32,
}

struct SshSession {
    client: Mutex<Option<client::Handle<HostKeyHandler>>>,
    jump_clients: Mutex<Vec<client::Handle<HostKeyHandler>>>,
    writer: Mutex<ChannelWriteHalf<client::Msg>>,
    output: Mutex<OutputBuffer>,
    data_ready: Notify,
    space_ready: Notify,
    closed: AtomicBool,
    interactive_response_pending: AtomicBool,
}

struct SshTunnel {
    session_id: i64,
    kind: String,
    bind_host: String,
    bind_port: u16,
    bytes_up: AtomicU64,
    bytes_down: AtomicU64,
    active: AtomicBool,
    error: StdMutex<Option<String>>,
    stop: Notify,
}

struct OutputBuffer {
    stdout: VecDeque<u8>,
    stderr: VecDeque<u8>,
    error: Option<String>,
}

impl OutputBuffer {
    fn len(&self) -> usize {
        self.stdout.len() + self.stderr.len()
    }

    fn release_excess_capacity(&mut self) {
        if self.stdout.capacity() > RETAINED_BUFFER_BYTES * 2 {
            self.stdout.shrink_to(RETAINED_BUFFER_BYTES);
        }
        if self.stderr.capacity() > RETAINED_BUFFER_BYTES * 2 {
            self.stderr.shrink_to(RETAINED_BUFFER_BYTES);
        }
    }
}

struct SftpSessionState {
    client: Mutex<Option<client::Handle<HostKeyHandler>>>,
    sftp: SftpSession,
    path: Mutex<String>,
}

async fn connect_client(
    host: &str,
    port: u16,
    handler: HostKeyHandler,
) -> Result<client::Handle<HostKeyHandler>> {
    tokio::time::timeout(
        Duration::from_secs(15),
        client::connect(ssh_client_config(), (host, port), handler),
    )
    .await
    .context("SSH connection timed out")?
    .context("SSH handshake failed")
}

fn ssh_client_config() -> Arc<client::Config> {
    Arc::new(client::Config {
        window_size: 1024 * 1024,
        maximum_packet_size: 32 * 1024,
        channel_buffer_size: 64,
        keepalive_interval: Some(Duration::from_secs(15)),
        keepalive_max: 3,
        ..Default::default()
    })
}

async fn ssh_connect_via_jumps(request: RustSshConnectRequest) -> Result<RustSshConnectResult> {
    let mut jump_clients = Vec::with_capacity(request.jump_hosts.len());
    let first = &request.jump_hosts[0];
    let first_observed = Arc::new(StdMutex::new(None));
    let first_handler = HostKeyHandler {
        trusted: first.trusted_host_keys.iter().cloned().collect(),
        observed: Arc::clone(&first_observed),
    };
    let mut current = match connect_client(&first.host, first.port, first_handler).await {
        Ok(client) => client,
        Err(error) => {
            let host_key = first_observed
                .lock()
                .expect("host key mutex poisoned")
                .clone();
            let code = if host_key.is_some() {
                "jump_host_key_rejected:0"
            } else {
                "jump_host_connection_failed:0"
            };
            return Ok(connect_error(code, error, host_key));
        }
    };
    if let Err(error) = authenticate_jump_host(&mut current, first).await {
        return Ok(connect_error(
            "jump_host_authentication_failed:0",
            error,
            None,
        ));
    }

    for (index, next) in request.jump_hosts.iter().enumerate().skip(1) {
        let channel = current
            .channel_open_direct_tcpip(&next.host, next.port.into(), "127.0.0.1", 0)
            .await
            .with_context(|| format!("Jump host {} rejected direct-tcpip", index - 1));
        let channel = match channel {
            Ok(channel) => channel,
            Err(error) => {
                return Ok(connect_error(
                    &format!("jump_host_connection_failed:{index}"),
                    error,
                    None,
                ));
            }
        };
        let observed = Arc::new(StdMutex::new(None));
        let handler = HostKeyHandler {
            trusted: next.trusted_host_keys.iter().cloned().collect(),
            observed: Arc::clone(&observed),
        };
        let next_client = tokio::time::timeout(
            Duration::from_secs(15),
            client::connect_stream(ssh_client_config(), channel.into_stream(), handler),
        )
        .await;
        let mut next_client = match next_client {
            Ok(Ok(client)) => client,
            Ok(Err(error)) => {
                let host_key = observed.lock().expect("host key mutex poisoned").clone();
                let code = if host_key.is_some() {
                    format!("jump_host_key_rejected:{index}")
                } else {
                    format!("jump_host_connection_failed:{index}")
                };
                return Ok(connect_error(&code, error, host_key));
            }
            Err(error) => {
                return Ok(connect_error(
                    &format!("jump_host_connection_failed:{index}"),
                    error,
                    None,
                ));
            }
        };
        if let Err(error) = authenticate_jump_host(&mut next_client, next).await {
            return Ok(connect_error(
                &format!("jump_host_authentication_failed:{index}"),
                error,
                None,
            ));
        }
        jump_clients.push(current);
        current = next_client;
    }

    let target_channel = current
        .channel_open_direct_tcpip(&request.host, request.port.into(), "127.0.0.1", 0)
        .await
        .context("Last jump host rejected target direct-tcpip")?;
    let observed = Arc::new(StdMutex::new(None));
    let handler = HostKeyHandler {
        trusted: request.trusted_host_keys.iter().cloned().collect(),
        observed: Arc::clone(&observed),
    };
    let mut target = match tokio::time::timeout(
        Duration::from_secs(15),
        client::connect_stream(ssh_client_config(), target_channel.into_stream(), handler),
    )
    .await
    {
        Ok(Ok(client)) => client,
        Ok(Err(error)) => {
            let host_key = observed.lock().expect("host key mutex poisoned").clone();
            return Ok(connect_error(
                if host_key.is_some() {
                    "host_key_untrusted"
                } else {
                    "connection_failed"
                },
                error,
                host_key,
            ));
        }
        Err(error) => return Ok(connect_error("connection_failed", error, None)),
    };
    if let Err(error) = authenticate_noninteractive_target(&mut target, &request).await {
        return Ok(connect_error("authentication_failed", error, None));
    }
    jump_clients.push(current);
    finalize_ssh_session(
        target,
        jump_clients,
        request.terminal_width,
        request.terminal_height,
    )
    .await
}

async fn authenticate_jump_host(
    client: &mut client::Handle<HostKeyHandler>,
    jump: &RustSshJumpHost,
) -> Result<()> {
    if jump.auth_kind == "private_key" {
        return authenticate_private_key(
            client,
            &jump.username,
            &jump.private_key_pem,
            jump.passphrase.as_deref(),
        )
        .await;
    }
    let result = client
        .authenticate_password(&jump.username, &jump.password)
        .await
        .context("Jump host password authentication failed")?;
    if result.success() {
        Ok(())
    } else {
        Err(anyhow!("Jump host authentication was rejected"))
    }
}

async fn authenticate_noninteractive_target(
    client: &mut client::Handle<HostKeyHandler>,
    request: &RustSshConnectRequest,
) -> Result<()> {
    if request.auth_kind == "private_key" {
        return authenticate_private_key(
            client,
            &request.username,
            &request.private_key_pem,
            request.passphrase.as_deref(),
        )
        .await;
    }
    let result = client
        .authenticate_password(&request.username, &request.password)
        .await
        .context("Password authentication failed")?;
    if result.success() {
        Ok(())
    } else {
        Err(anyhow!("Password authentication was rejected"))
    }
}

async fn authenticate(
    client: &mut client::Handle<HostKeyHandler>,
    request: &RustSshConnectRequest,
) -> Result<AuthenticationOutcome> {
    if request.auth_kind == "private_key" {
        authenticate_private_key(
            client,
            &request.username,
            &request.private_key_pem,
            request.passphrase.as_deref(),
        )
        .await?;
        return Ok(AuthenticationOutcome::Complete);
    }
    let password_result = client
        .authenticate_password(&request.username, &request.password)
        .await
        .context("Password authentication failed")?;
    if password_result.success() {
        return Ok(AuthenticationOutcome::Complete);
    }
    match client
        .authenticate_keyboard_interactive_start(&request.username, None::<String>)
        .await
        .context("Keyboard-interactive authentication failed")?
    {
        KeyboardInteractiveAuthResponse::Success => Ok(AuthenticationOutcome::Complete),
        KeyboardInteractiveAuthResponse::InfoRequest {
            name,
            instructions,
            prompts,
        } => Ok(AuthenticationOutcome::Challenge(RustAuthChallenge {
            name,
            instruction: instructions,
            prompts: prompts
                .into_iter()
                .map(|prompt| RustInteractivePrompt {
                    text: prompt.prompt,
                    echo: prompt.echo,
                })
                .collect(),
        })),
        KeyboardInteractiveAuthResponse::Failure { .. } => {
            Err(anyhow!("SSH authentication was rejected"))
        }
    }
}

async fn authenticate_sftp(
    client: &mut client::Handle<HostKeyHandler>,
    request: &RustSftpConnectRequest,
) -> Result<()> {
    if request.auth_kind == "private_key" {
        return authenticate_private_key(
            client,
            &request.username,
            &request.private_key_pem,
            request.passphrase.as_deref(),
        )
        .await;
    }
    let result = client
        .authenticate_password(&request.username, &request.password)
        .await
        .context("Password authentication failed")?;
    if result.success() {
        Ok(())
    } else {
        Err(anyhow!("SFTP authentication was rejected"))
    }
}

async fn execute_ssh_command(
    request: &RustSshExecRequest,
    output_limit: usize,
) -> Result<RustSshExecResult> {
    if request.command.is_empty() {
        return Err(anyhow!("SSH command is empty"));
    }
    if request.trusted_host_keys.is_empty() {
        return Err(anyhow!("No trusted host key is stored for this connection"));
    }
    let observed = Arc::new(StdMutex::new(None));
    let handler = HostKeyHandler {
        trusted: request.trusted_host_keys.iter().cloned().collect(),
        observed,
    };
    let mut client = connect_client(&request.host, request.port, handler).await?;
    match request.auth_kind.as_str() {
        "private_key" => {
            authenticate_private_key(
                &mut client,
                &request.username,
                &request.private_key_pem,
                request.passphrase.as_deref(),
            )
            .await?;
        }
        "password" => {
            let result = client
                .authenticate_password(&request.username, &request.password)
                .await
                .context("Password authentication failed")?;
            if !result.success() {
                return Err(anyhow!("Password authentication was rejected"));
            }
        }
        _ => return Err(anyhow!("Unsupported SSH authentication type")),
    }

    let mut channel = client
        .channel_open_session()
        .await
        .context("Failed to open SSH exec channel")?;
    channel
        .exec(true, request.command.as_bytes())
        .await
        .context("SSH exec request was rejected")?;

    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let mut exit_status = None;
    let mut truncated = false;
    while let Some(message) = channel.wait().await {
        match message {
            ChannelMsg::Data { data } => {
                truncated |= append_limited(&mut stdout, data.as_ref(), output_limit, stderr.len());
            }
            ChannelMsg::ExtendedData { data, ext } if ext == 1 => {
                truncated |= append_limited(&mut stderr, data.as_ref(), output_limit, stdout.len());
            }
            ChannelMsg::ExitStatus {
                exit_status: status,
            } => exit_status = Some(status),
            ChannelMsg::Eof | ChannelMsg::Close => break,
            _ => {}
        }
        if truncated {
            let _ = channel.close().await;
            break;
        }
    }
    let _ = client
        .disconnect(Disconnect::ByApplication, "", "English")
        .await;
    Ok(RustSshExecResult {
        stdout,
        stderr,
        exit_status,
        timed_out: false,
        cancelled: false,
        truncated,
        error_code: None,
        error_message: None,
    })
}

fn append_limited(target: &mut Vec<u8>, data: &[u8], limit: usize, other_len: usize) -> bool {
    let available = limit.saturating_sub(target.len() + other_len);
    let copied = available.min(data.len());
    target.extend_from_slice(&data[..copied]);
    copied < data.len()
}

async fn authenticate_private_key(
    client: &mut client::Handle<HostKeyHandler>,
    username: &str,
    pem: &str,
    passphrase: Option<&str>,
) -> Result<()> {
    let key = decode_secret_key(pem, passphrase).context("Invalid SSH private key")?;
    let hash = client
        .best_supported_rsa_hash()
        .await
        .context("Failed to negotiate RSA signature algorithm")?
        .flatten();
    let result = client
        .authenticate_publickey(username, PrivateKeyWithHashAlg::new(Arc::new(key), hash))
        .await
        .context("Public-key authentication failed")?;
    if result.success() {
        Ok(())
    } else {
        Err(anyhow!("Public-key authentication was rejected"))
    }
}

async fn finalize_ssh_session(
    client: client::Handle<HostKeyHandler>,
    jump_clients: Vec<client::Handle<HostKeyHandler>>,
    width: u32,
    height: u32,
) -> Result<RustSshConnectResult> {
    let channel = client
        .channel_open_session()
        .await
        .context("Failed to open SSH channel")?;
    channel
        .request_pty(true, "xterm-256color", width, height, 0, 0, &[])
        .await
        .context("PTY request was rejected")?;
    channel
        .request_shell(true)
        .await
        .context("Shell request was rejected")?;
    let (mut reader, writer) = channel.split();
    let session = Arc::new(SshSession {
        client: Mutex::new(Some(client)),
        jump_clients: Mutex::new(jump_clients),
        writer: Mutex::new(writer),
        output: Mutex::new(OutputBuffer {
            stdout: VecDeque::new(),
            stderr: VecDeque::new(),
            error: None,
        }),
        data_ready: Notify::new(),
        space_ready: Notify::new(),
        closed: AtomicBool::new(false),
        interactive_response_pending: AtomicBool::new(false),
    });
    let id = next_id();
    SSH_SESSIONS.insert(id, Arc::clone(&session));
    tokio::spawn(async move {
        while let Some(message) = reader.wait().await {
            let result = match message {
                ChannelMsg::Data { data } => append_output(&session, data.as_ref(), false).await,
                ChannelMsg::ExtendedData { data, ext } => {
                    append_output(&session, data.as_ref(), ext == 1).await
                }
                ChannelMsg::Eof | ChannelMsg::Close => break,
                _ => continue,
            };
            if result.is_err() {
                break;
            }
        }
        session.closed.store(true, Ordering::Release);
        session.data_ready.notify_waiters();
        session.space_ready.notify_waiters();
    });
    Ok(RustSshConnectResult {
        session_id: Some(id),
        pending_auth_id: None,
        host_key: None,
        challenge: None,
        error_code: None,
        error_message: None,
    })
}

async fn append_output(session: &SshSession, data: &[u8], stderr: bool) -> Result<()> {
    let mut offset = 0;
    while offset < data.len() {
        if session.closed.load(Ordering::Acquire) {
            return Err(anyhow!("SSH session closed"));
        }
        let notified = session.space_ready.notified();
        let mut output = session.output.lock().await;
        let available = MAX_BUFFER_BYTES.saturating_sub(output.len());
        if available == 0 {
            drop(output);
            notified.await;
            continue;
        }
        let end = (offset + available).min(data.len());
        let target = if stderr {
            &mut output.stderr
        } else {
            &mut output.stdout
        };
        target.extend(&data[offset..end]);
        offset = end;
        drop(output);
        session.data_ready.notify_waiters();
    }
    Ok(())
}

fn drain_queue(queue: &mut VecDeque<u8>, limit: usize) -> Vec<u8> {
    let length = queue.len().min(limit);
    queue.drain(..length).collect()
}

fn get_ssh_session(id: i64) -> Result<Arc<SshSession>> {
    SSH_SESSIONS
        .get(&id)
        .map(|entry| Arc::clone(entry.value()))
        .ok_or_else(|| anyhow!("SSH session not found"))
}

fn get_sftp_session(id: i64) -> Result<Arc<SftpSessionState>> {
    SFTP_SESSIONS
        .get(&id)
        .map(|entry| Arc::clone(entry.value()))
        .ok_or_else(|| anyhow!("SFTP session not found"))
}

async fn resolve_sftp_path(session: &SftpSessionState, value: &str) -> String {
    if value.starts_with('/') {
        return value.to_owned();
    }
    let current = session.path.lock().await;
    if current.as_str() == "/" {
        format!("/{value}")
    } else {
        format!("{current}/{value}")
    }
}

fn connect_error(
    code: &str,
    error: impl std::fmt::Display,
    host_key: Option<RustHostKey>,
) -> RustSshConnectResult {
    RustSshConnectResult {
        session_id: None,
        pending_auth_id: None,
        host_key,
        challenge: None,
        error_code: Some(code.to_owned()),
        error_message: Some(error.to_string()),
    }
}

fn sftp_connect_error(
    code: &str,
    error: impl std::fmt::Display,
    host_key: Option<RustHostKey>,
) -> RustSftpConnectResult {
    RustSftpConnectResult {
        session_id: None,
        host_key,
        error_code: Some(code.to_owned()),
        error_message: Some(error.to_string()),
    }
}

fn host_key_identity(key: &RustHostKey) -> String {
    format!("{}|{}", key.algorithm, key.fingerprint_sha256)
}

fn next_id() -> i64 {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}
