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
use tokio::sync::mpsc;
use tokio::sync::{Mutex, Notify};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
};
use vnc::{
    ClientKeyEvent, ClientMouseEvent, PixelFormat, Rect, VncConnector, VncEncoding, VncEvent,
    X11Event,
};
use zeroize::Zeroize;

const MAX_BUFFER_BYTES: usize = 2 * 1024 * 1024;
const MAX_VNC_FRAME_BYTES: usize = 2560 * 1600 * 4;
const MAX_FORWARDED_CHANNELS: usize = 32;
const MAX_READ_BYTES: usize = 256 * 1024;
const RETAINED_BUFFER_BYTES: usize = 128 * 1024;
const READ_BATCH_BYTES: usize = 64 * 1024;
const READ_COALESCE_MILLIS: u64 = 2;
const MIN_RSA_KEY_BITS: usize = 2048;

static NEXT_ID: AtomicI64 = AtomicI64::new(1);
static SSH_SESSIONS: Lazy<DashMap<i64, Arc<SshSession>>> = Lazy::new(DashMap::new);
static PENDING_AUTHS: Lazy<DashMap<i64, PendingAuthentication>> = Lazy::new(DashMap::new);
static SFTP_SESSIONS: Lazy<DashMap<i64, Arc<SftpSessionState>>> = Lazy::new(DashMap::new);
static SSH_EXEC_CANCELLATIONS: Lazy<DashMap<i64, Arc<Notify>>> = Lazy::new(DashMap::new);
static SSH_TUNNELS: Lazy<DashMap<i64, Arc<SshTunnel>>> = Lazy::new(DashMap::new);
static VNC_SESSIONS: Lazy<DashMap<i64, Arc<VncSession>>> = Lazy::new(DashMap::new);

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

#[derive(Clone)]
pub struct RustMoshBootstrapRequest {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth_kind: String,
    pub password: String,
    pub private_key_pem: String,
    pub passphrase: Option<String>,
    pub trusted_host_keys: Vec<String>,
}

pub struct RustMoshBootstrapResult {
    pub output: String,
    pub exit_status: Option<u32>,
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
pub struct RustVncConnectRequest {
    pub host: String,
    pub port: u16,
    pub password: String,
    pub shared: bool,
}

pub struct RustVncConnectResult {
    pub session_id: i64,
}

pub struct RustVncFrame {
    pub width: u32,
    pub height: u32,
    pub bgra: Vec<u8>,
    pub sequence: u64,
    pub closed: bool,
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
    // Dependencies must never emit SSH packet payloads or credentials to
    // Android logcat, including debug builds.
    log::set_max_level(log::LevelFilter::Warn);
}

pub async fn ssh_connect(request: RustSshConnectRequest) -> Result<RustSshConnectResult> {
    if !request.jump_hosts.is_empty() {
        return ssh_connect_via_jumps(request).await;
    }
    let observed = Arc::new(StdMutex::new(None));
    let (forwarded_tx, forwarded_rx) = mpsc::channel(MAX_FORWARDED_CHANNELS);
    let handler = HostKeyHandler {
        trusted: request.trusted_host_keys.iter().cloned().collect(),
        observed: Arc::clone(&observed),
        forwarded_channels: Some(forwarded_tx),
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
                forwarded_rx,
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
                    forwarded_channels: forwarded_rx,
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
                pending.forwarded_channels,
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
    let Some(session) = SSH_SESSIONS
        .get(&session_id)
        .map(|entry| Arc::clone(entry.value()))
    else {
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
        ssh_stop_tunnel(tunnel_id).await;
    }
    SSH_SESSIONS.remove(&session_id);
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

pub async fn mosh_bootstrap(request: RustMoshBootstrapRequest) -> Result<RustMoshBootstrapResult> {
    if request.trusted_host_keys.is_empty() {
        return Err(anyhow!("No trusted host key is stored for this connection"));
    }
    let observed = Arc::new(StdMutex::new(None));
    let handler = HostKeyHandler {
        trusted: request.trusted_host_keys.iter().cloned().collect(),
        observed,
        forwarded_channels: None,
    };
    let mut client = connect_client(&request.host, request.port, handler).await?;
    if request.auth_kind == "private_key" {
        authenticate_private_key(
            &mut client,
            &request.username,
            &request.private_key_pem,
            request.passphrase.as_deref(),
        )
        .await?;
    } else {
        let authenticated = client
            .authenticate_password(&request.username, &request.password)
            .await
            .context("Mosh bootstrap password authentication failed")?;
        if !authenticated.success() {
            return Err(anyhow!("Mosh bootstrap authentication was rejected"));
        }
    }
    let mut channel = client.channel_open_session().await?;
    channel
        .exec(
            true,
            b"mosh-server new -s -i 0.0.0.0 -c 256 -l LANG=en_US.UTF-8",
        )
        .await
        .context("mosh-server launch was rejected")?;
    let mut output = Vec::new();
    let mut exit_status = None;
    while let Some(message) = channel.wait().await {
        match message {
            ChannelMsg::Data { data } | ChannelMsg::ExtendedData { data, .. } => {
                let available = 16 * 1024usize - output.len();
                output.extend_from_slice(&data[..data.len().min(available)]);
                if String::from_utf8_lossy(&output).contains("MOSH CONNECT ") {
                    break;
                }
            }
            ChannelMsg::ExitStatus {
                exit_status: status,
            } => exit_status = Some(status),
            ChannelMsg::Eof | ChannelMsg::Close => break,
            _ => {}
        }
    }
    let _ = client
        .disconnect(Disconnect::ByApplication, "", "English")
        .await;
    Ok(RustMoshBootstrapResult {
        output: String::from_utf8_lossy(&output).into_owned(),
        exit_status,
    })
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
    decode_ssh_private_key(&pem, passphrase.as_deref())
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
        let decoded = decode_ssh_private_key(&pem, passphrase.as_deref())
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
    if request.kind != "local" && request.kind != "remote" && request.kind != "socks5" {
        return Err(anyhow!("Unsupported SSH tunnel kind"));
    }
    if !request.allow_lan && request.bind_host != "127.0.0.1" {
        return Err(anyhow!("LAN tunnel binding requires explicit permission"));
    }
    if (request.kind == "local" || request.kind == "remote")
        && (request.target_host.is_empty() || request.target_port == 0)
    {
        return Err(anyhow!("SSH forwarding target is invalid"));
    }
    let session = SSH_SESSIONS
        .get(&request.session_id)
        .map(|entry| Arc::clone(entry.value()))
        .context("SSH session is not active")?;
    if session.client.lock().await.is_none() {
        return Err(anyhow!("SSH session is closed"));
    }
    if request.kind == "remote" {
        return start_remote_tunnel(request, session).await;
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

async fn start_remote_tunnel(
    request: RustSshTunnelStartRequest,
    session: Arc<SshSession>,
) -> Result<RustSshTunnelStatus> {
    if SSH_TUNNELS.iter().any(|entry| {
        entry.session_id == request.session_id
            && entry.kind == "remote"
            && entry.active.load(Ordering::Acquire)
    }) {
        return Err(anyhow!("Only one remote forward can run per SSH session"));
    }
    let bound_port = {
        let mut client = session.client.lock().await;
        client
            .as_mut()
            .context("SSH session is closed")?
            .tcpip_forward(request.bind_host.clone(), request.bind_port.into())
            .await
            .context("SSH server rejected remote forwarding")?
    };
    let bind_port = if request.bind_port == 0 {
        u16::try_from(bound_port).context("SSH server returned an invalid remote port")?
    } else {
        request.bind_port
    };
    let tunnel_id = next_id();
    let tunnel = Arc::new(SshTunnel {
        session_id: request.session_id,
        kind: request.kind,
        bind_host: request.bind_host,
        bind_port,
        bytes_up: AtomicU64::new(0),
        bytes_down: AtomicU64::new(0),
        active: AtomicBool::new(true),
        error: StdMutex::new(None),
        stop: Notify::new(),
    });
    SSH_TUNNELS.insert(tunnel_id, Arc::clone(&tunnel));
    let target_host = request.target_host;
    let target_port = request.target_port;
    let session_for_task = Arc::clone(&session);
    tokio::spawn(async move {
        let mut forwarded_channels = session_for_task.forwarded_channels.lock().await;
        loop {
            let received = tokio::select! {
                _ = tunnel.stop.notified() => break,
                received = forwarded_channels.recv() => received,
            };
            let Some(forwarded) = received else { break };
            if forwarded.connected_port != u32::from(tunnel.bind_port) {
                continue;
            }
            let tunnel_for_connection = Arc::clone(&tunnel);
            let target_host = target_host.clone();
            tokio::spawn(async move {
                let outcome = async {
                    let mut socket = TcpStream::connect((target_host.as_str(), target_port))
                        .await
                        .context("Remote forwarding target connection failed")?;
                    let mut stream = forwarded.channel.into_stream();
                    let (down, up) =
                        tokio::io::copy_bidirectional(&mut stream, &mut socket).await?;
                    tunnel_for_connection
                        .bytes_down
                        .fetch_add(down, Ordering::AcqRel);
                    tunnel_for_connection
                        .bytes_up
                        .fetch_add(up, Ordering::AcqRel);
                    Result::<()>::Ok(())
                }
                .await;
                if let Err(error) = outcome {
                    *tunnel_for_connection
                        .error
                        .lock()
                        .expect("tunnel error mutex poisoned") = Some(format!("{error:#}"));
                }
            });
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

pub async fn ssh_stop_tunnel(tunnel_id: i64) {
    if let Some((_, tunnel)) = SSH_TUNNELS.remove(&tunnel_id) {
        tunnel.active.store(false, Ordering::Release);
        tunnel.stop.notify_waiters();
        if tunnel.kind == "remote" {
            if let Some(session) = SSH_SESSIONS.get(&tunnel.session_id) {
                if let Some(client) = session.client.lock().await.as_ref() {
                    let _ = client
                        .cancel_tcpip_forward(tunnel.bind_host.clone(), tunnel.bind_port.into())
                        .await;
                }
            }
        }
    }
}

pub async fn sftp_connect(request: RustSftpConnectRequest) -> Result<RustSftpConnectResult> {
    let observed = Arc::new(StdMutex::new(None));
    let handler = HostKeyHandler {
        trusted: request.trusted_host_keys.iter().cloned().collect(),
        observed: Arc::clone(&observed),
        forwarded_channels: None,
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

pub async fn vnc_connect(request: RustVncConnectRequest) -> Result<RustVncConnectResult> {
    let tcp = tokio::time::timeout(
        Duration::from_secs(10),
        TcpStream::connect((request.host.as_str(), request.port)),
    )
    .await
    .context("VNC connection timed out")?
    .context("VNC server is unreachable")?;
    let password = request.password;
    let client = VncConnector::new(tcp)
        .set_auth_method(async move { Ok(password) })
        .add_encoding(VncEncoding::Zrle)
        .add_encoding(VncEncoding::CopyRect)
        .add_encoding(VncEncoding::Raw)
        .add_encoding(VncEncoding::DesktopSizePseudo)
        .allow_shared(request.shared)
        .set_pixel_format(PixelFormat::bgra())
        .build()
        .context("VNC configuration failed")?
        .try_start()
        .await
        .context("VNC handshake failed")?
        .finish()
        .context("VNC authentication failed")?;
    let session = Arc::new(VncSession {
        client: client.clone(),
        width: AtomicU64::new(0),
        height: AtomicU64::new(0),
        sequence: AtomicU64::new(0),
        frame: Mutex::new(Vec::new()),
        frame_ready: Notify::new(),
        closed: AtomicBool::new(false),
        error: StdMutex::new(None),
    });
    let session_id = next_id();
    VNC_SESSIONS.insert(session_id, Arc::clone(&session));
    tokio::spawn(async move {
        let mut refresh = tokio::time::interval(Duration::from_millis(33));
        loop {
            tokio::select! {
                _ = refresh.tick() => {
                    if client.input(X11Event::Refresh).await.is_err() { break; }
                }
                event = client.recv_event() => {
                    match event {
                        Ok(VncEvent::SetResolution(screen)) => {
                            let width = u64::from(screen.width);
                            let height = u64::from(screen.height);
                            let frame_bytes = width.saturating_mul(height).saturating_mul(4);
                            if frame_bytes > MAX_VNC_FRAME_BYTES as u64 {
                                *session.error.lock().expect("VNC error mutex poisoned") = Some(
                                    "VNC framebuffer exceeds the 2560x1600 safety limit".to_owned(),
                                );
                                break;
                            }
                            session.width.store(width, Ordering::Release);
                            session.height.store(height, Ordering::Release);
                            session.frame.lock().await.resize(frame_bytes as usize, 0);
                        }
                        Ok(VncEvent::RawImage(rect, pixels)) => {
                            if apply_vnc_rect(&session, rect, &pixels).await {
                                session.sequence.fetch_add(1, Ordering::AcqRel);
                                session.frame_ready.notify_waiters();
                            }
                        }
                        Ok(VncEvent::Copy(destination, source)) => {
                            if copy_vnc_rect(&session, destination, source).await {
                                session.sequence.fetch_add(1, Ordering::AcqRel);
                                session.frame_ready.notify_waiters();
                            }
                        }
                        Ok(VncEvent::Error(message)) => {
                            *session.error.lock().expect("VNC error mutex poisoned") = Some(message);
                            break;
                        }
                        Ok(_) => {}
                        Err(error) => {
                            *session.error.lock().expect("VNC error mutex poisoned") = Some(error.to_string());
                            break;
                        }
                    }
                }
            }
        }
        session.closed.store(true, Ordering::Release);
        session.frame_ready.notify_waiters();
    });
    Ok(RustVncConnectResult { session_id })
}

pub async fn vnc_read_frame(
    session_id: i64,
    after_sequence: u64,
    wait_millis: u32,
) -> Result<RustVncFrame> {
    let session = VNC_SESSIONS
        .get(&session_id)
        .map(|entry| Arc::clone(entry.value()))
        .context("VNC session not found")?;
    if session.sequence.load(Ordering::Acquire) <= after_sequence
        && !session.closed.load(Ordering::Acquire)
    {
        let _ = tokio::time::timeout(
            Duration::from_millis(u64::from(wait_millis.clamp(1, 1_000))),
            session.frame_ready.notified(),
        )
        .await;
    }
    let sequence = session.sequence.load(Ordering::Acquire);
    let frame = if sequence > after_sequence {
        session.frame.lock().await.clone()
    } else {
        Vec::new()
    };
    let error_message = session
        .error
        .lock()
        .expect("VNC error mutex poisoned")
        .clone();
    Ok(RustVncFrame {
        width: session.width.load(Ordering::Acquire) as u32,
        height: session.height.load(Ordering::Acquire) as u32,
        bgra: frame,
        sequence,
        closed: session.closed.load(Ordering::Acquire),
        error_message,
    })
}

pub async fn vnc_pointer(session_id: i64, x: u16, y: u16, buttons: u8) -> Result<()> {
    let client = VNC_SESSIONS
        .get(&session_id)
        .map(|entry| entry.client.clone())
        .context("VNC session not found")?;
    client
        .input(X11Event::PointerEvent(ClientMouseEvent::from((
            x, y, buttons,
        ))))
        .await
        .context("VNC pointer input failed")
}

pub async fn vnc_key(session_id: i64, key_sym: u32, down: bool) -> Result<()> {
    let client = VNC_SESSIONS
        .get(&session_id)
        .map(|entry| entry.client.clone())
        .context("VNC session not found")?;
    client
        .input(X11Event::KeyEvent(ClientKeyEvent::from((key_sym, down))))
        .await
        .context("VNC key input failed")
}

pub async fn vnc_close(session_id: i64) -> Result<()> {
    let Some((_, session)) = VNC_SESSIONS.remove(&session_id) else {
        return Ok(());
    };
    session.closed.store(true, Ordering::Release);
    session.frame_ready.notify_waiters();
    session.client.close().await.context("VNC close failed")
}

async fn apply_vnc_rect(session: &VncSession, rect: Rect, pixels: &[u8]) -> bool {
    let width = session.width.load(Ordering::Acquire) as usize;
    let height = session.height.load(Ordering::Acquire) as usize;
    let rect_width = usize::from(rect.width);
    let rect_height = usize::from(rect.height);
    let rect_x = usize::from(rect.x);
    let rect_y = usize::from(rect.y);
    if width == 0
        || height == 0
        || rect_x >= width
        || rect_y >= height
        || pixels.len() < rect_width * rect_height * 4
    {
        return false;
    }
    let copy_width = rect_width.min(width - rect_x);
    let copy_height = rect_height.min(height - rect_y);
    let mut frame = session.frame.lock().await;
    for row in 0..copy_height {
        let source = row * rect_width * 4;
        let target = ((rect_y + row) * width + rect_x) * 4;
        frame[target..target + copy_width * 4]
            .copy_from_slice(&pixels[source..source + copy_width * 4]);
    }
    true
}

async fn copy_vnc_rect(session: &VncSession, destination: Rect, source: Rect) -> bool {
    let width = session.width.load(Ordering::Acquire) as usize;
    let height = session.height.load(Ordering::Acquire) as usize;
    let source_x = usize::from(source.x);
    let source_y = usize::from(source.y);
    let destination_x = usize::from(destination.x);
    let destination_y = usize::from(destination.y);
    if source_x >= width || source_y >= height || destination_x >= width || destination_y >= height
    {
        return false;
    }
    let copy_width = usize::from(source.width)
        .min(width - source_x)
        .min(width - destination_x);
    let copy_height = usize::from(source.height)
        .min(height - source_y)
        .min(height - destination_y);
    if copy_width == 0 || copy_height == 0 {
        return false;
    }
    let mut frame = session.frame.lock().await;
    let mut temporary = vec![0; copy_width * copy_height * 4];
    for row in 0..copy_height {
        let source_offset = ((source_y + row) * width + source_x) * 4;
        temporary[row * copy_width * 4..(row + 1) * copy_width * 4]
            .copy_from_slice(&frame[source_offset..source_offset + copy_width * 4]);
    }
    for row in 0..copy_height {
        let target_offset = ((destination_y + row) * width + destination_x) * 4;
        frame[target_offset..target_offset + copy_width * 4]
            .copy_from_slice(&temporary[row * copy_width * 4..(row + 1) * copy_width * 4]);
    }
    true
}

struct HostKeyHandler {
    trusted: HashSet<String>,
    observed: Arc<StdMutex<Option<RustHostKey>>>,
    forwarded_channels: Option<mpsc::Sender<ForwardedTcpIpChannel>>,
}

struct ForwardedTcpIpChannel {
    channel: russh::Channel<client::Msg>,
    connected_port: u32,
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

    async fn server_channel_open_forwarded_tcpip(
        &mut self,
        channel: russh::Channel<client::Msg>,
        _connected_address: &str,
        connected_port: u32,
        _originator_address: &str,
        _originator_port: u32,
        _session: &mut client::Session,
    ) -> std::result::Result<(), Self::Error> {
        if let Some(sender) = &self.forwarded_channels {
            let _ = sender.try_send(ForwardedTcpIpChannel {
                channel,
                connected_port,
            });
        }
        Ok(())
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
    forwarded_channels: mpsc::Receiver<ForwardedTcpIpChannel>,
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
    forwarded_channels: Mutex<mpsc::Receiver<ForwardedTcpIpChannel>>,
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

struct VncSession {
    client: vnc::VncClient,
    width: AtomicU64,
    height: AtomicU64,
    sequence: AtomicU64,
    frame: Mutex<Vec<u8>>,
    frame_ready: Notify,
    closed: AtomicBool,
    error: StdMutex<Option<String>>,
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
        forwarded_channels: None,
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
            forwarded_channels: None,
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
    let (forwarded_tx, forwarded_rx) = mpsc::channel(MAX_FORWARDED_CHANNELS);
    let handler = HostKeyHandler {
        trusted: request.trusted_host_keys.iter().cloned().collect(),
        observed: Arc::clone(&observed),
        forwarded_channels: Some(forwarded_tx),
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
        forwarded_rx,
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
        forwarded_channels: None,
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
    let key = decode_ssh_private_key(pem, passphrase).context("Invalid SSH private key")?;
    if key.algorithm().is_rsa() {
        let advertised = client
            .best_supported_rsa_hash()
            .await
            .context("Failed to negotiate RSA signature algorithm")?;
        let key = Arc::new(key);
        for hash in rsa_hash_candidates(advertised)? {
            let result = client
                .authenticate_publickey(
                    username,
                    PrivateKeyWithHashAlg::new(Arc::clone(&key), Some(hash)),
                )
                .await
                .context("Public-key authentication failed")?;
            if result.success() {
                return Ok(());
            }
        }
        return Err(anyhow!("RSA SHA-2 public-key authentication was rejected"));
    }

    let result = client
        .authenticate_publickey(username, PrivateKeyWithHashAlg::new(Arc::new(key), None))
        .await
        .context("Public-key authentication failed")?;
    result
        .success()
        .then_some(())
        .ok_or_else(|| anyhow!("Public-key authentication was rejected"))
}

fn decode_ssh_private_key(pem: &str, passphrase: Option<&str>) -> Result<PrivateKey> {
    let key = decode_secret_key(pem, passphrase).context("Unable to decode private key")?;
    validate_rsa_key_size(&key)?;
    Ok(key)
}

fn validate_rsa_key_size(key: &PrivateKey) -> Result<()> {
    let Some(rsa) = key.public_key().key_data().rsa() else {
        return Ok(());
    };
    let modulus = rsa
        .n
        .as_positive_bytes()
        .ok_or_else(|| anyhow!("Invalid RSA modulus"))?;
    let bits = positive_integer_bits(modulus);
    if bits < MIN_RSA_KEY_BITS {
        return Err(anyhow!(
            "RSA private keys must be at least {MIN_RSA_KEY_BITS} bits"
        ));
    }
    Ok(())
}

fn positive_integer_bits(bytes: &[u8]) -> usize {
    bytes
        .first()
        .map(|first| bytes.len() * 8 - first.leading_zeros() as usize)
        .unwrap_or(0)
}

fn rsa_hash_candidates(advertised: Option<Option<HashAlg>>) -> Result<Vec<HashAlg>> {
    match advertised {
        Some(Some(HashAlg::Sha512)) => Ok(vec![HashAlg::Sha512]),
        Some(Some(HashAlg::Sha256)) => Ok(vec![HashAlg::Sha256]),
        Some(Some(_)) | Some(None) => Err(anyhow!(
            "The SSH server does not support RSA SHA-2 signatures"
        )),
        // Servers without RFC 8308 extension info can still support RFC 8332.
        // Try both SHA-2 variants and never silently downgrade to SHA-1 ssh-rsa.
        None => Ok(vec![HashAlg::Sha512, HashAlg::Sha256]),
    }
}

async fn finalize_ssh_session(
    client: client::Handle<HostKeyHandler>,
    jump_clients: Vec<client::Handle<HostKeyHandler>>,
    width: u32,
    height: u32,
    forwarded_channels: mpsc::Receiver<ForwardedTcpIpChannel>,
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
        forwarded_channels: Mutex::new(forwarded_channels),
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

#[cfg(test)]
mod tests {
    use super::{
        positive_integer_bits, rsa_hash_candidates, ssh_execute, RustSshExecRequest,
        MIN_RSA_KEY_BITS,
    };
    use russh::keys::HashAlg;
    use std::{env, fs};

    #[test]
    fn calculates_supported_rsa_key_boundaries() {
        for bits in [2048, 4096] {
            let mut modulus = vec![0_u8; bits / 8];
            modulus[0] = 0x80;
            assert_eq!(positive_integer_bits(&modulus), bits);
        }
        let mut weak_modulus = vec![0_u8; 1024 / 8];
        weak_modulus[0] = 0x80;
        assert!(positive_integer_bits(&weak_modulus) < MIN_RSA_KEY_BITS);
    }

    #[test]
    fn rsa_signature_selection_never_downgrades_to_sha1() {
        assert_eq!(
            rsa_hash_candidates(Some(Some(HashAlg::Sha512))).unwrap(),
            vec![HashAlg::Sha512]
        );
        assert_eq!(
            rsa_hash_candidates(Some(Some(HashAlg::Sha256))).unwrap(),
            vec![HashAlg::Sha256]
        );
        assert_eq!(
            rsa_hash_candidates(None).unwrap(),
            vec![HashAlg::Sha512, HashAlg::Sha256]
        );
        assert!(rsa_hash_candidates(Some(None)).is_err());
    }

    #[test]
    #[ignore = "requires an explicitly configured local SSH test server"]
    fn authenticates_rsa_2048_and_4096_against_ssh_server() {
        let host = env::var("TERMETHIS_RSA_TEST_HOST").expect("test host");
        let port = env::var("TERMETHIS_RSA_TEST_PORT")
            .expect("test port")
            .parse()
            .expect("numeric test port");
        let username = env::var("TERMETHIS_RSA_TEST_USER").expect("test user");
        let host_key = env::var("TERMETHIS_RSA_TEST_HOST_KEY").expect("trusted host key");
        let key_directory = env::var("TERMETHIS_RSA_TEST_KEY_DIRECTORY").expect("key directory");
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("Tokio runtime");

        runtime.block_on(async {
            for (execution_id, bits) in [(20_480, 2048), (40_960, 4096)] {
                let private_key_pem = fs::read_to_string(format!("{key_directory}/id_rsa_{bits}"))
                    .expect("RSA test key");
                let expected = format!("TERMETHIS_RSA_{bits}_OK");
                let result = ssh_execute(RustSshExecRequest {
                    execution_id,
                    host: host.clone(),
                    port,
                    username: username.clone(),
                    auth_kind: "private_key".to_owned(),
                    password: String::new(),
                    private_key_pem,
                    passphrase: None,
                    trusted_host_keys: vec![host_key.clone()],
                    command: format!("printf {expected}"),
                    timeout_millis: 15_000,
                    output_limit_bytes: 4_096,
                })
                .await
                .expect("SSH execution");
                assert_eq!(
                    result.error_code, None,
                    "RSA {bits} error: {:?}",
                    result.error_message
                );
                assert_eq!(String::from_utf8(result.stdout).unwrap(), expected);
                assert!(
                    result.exit_status.is_none() || result.exit_status == Some(0),
                    "RSA {bits} exit status: {:?}",
                    result.exit_status
                );
            }
        });
    }
}
