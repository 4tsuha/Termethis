use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use dashmap::DashMap;
use ironrdp::client::config::{ConfigBuilder, Destination};
use ironrdp::client::rdp::{RdpClient, RdpInputEvent, RdpOutputEvent};
use ironrdp::input::{Database, MouseButton, MousePosition, Operation, Scancode};
use ironrdp::pdu::rdp::capability_sets::MajorPlatformType;
use once_cell::sync::Lazy;
use tokio::sync::{mpsc, Mutex, Notify};

#[cfg(target_os = "android")]
use crate::android_vulkan::AndroidVulkanRenderer;

static NEXT_RDP_ID: AtomicI64 = AtomicI64::new(1);
static RDP_SESSIONS: Lazy<DashMap<i64, Arc<RdpSession>>> = Lazy::new(DashMap::new);

#[derive(Clone)]
pub struct RustRdpConnectRequest {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    pub domain: String,
    pub width: u16,
    pub height: u16,
}

pub struct RustRdpConnectResult {
    pub session_id: i64,
    pub renderer: String,
}

pub struct RustRdpFrame {
    pub sequence: i64,
    pub width: u16,
    pub height: u16,
    pub rgba: Vec<u8>,
    pub state: String,
    pub error_message: Option<String>,
}

pub struct RustRdpStatus {
    pub sequence: i64,
    pub width: u16,
    pub height: u16,
    pub state: String,
    pub error_message: Option<String>,
    pub renderer: String,
    pub renderer_error: Option<String>,
}

struct RdpFrameData {
    sequence: i64,
    width: u16,
    height: u16,
    pixels: Arc<Vec<u32>>,
    state: String,
    error_message: Option<String>,
}

struct RdpSession {
    input: mpsc::UnboundedSender<RdpInputEvent>,
    input_state: StdMutex<Database>,
    frame: Mutex<RdpFrameData>,
    changed: Notify,
    closed: AtomicBool,
    #[cfg(target_os = "android")]
    renderer: AndroidVulkanRenderer,
}

pub async fn rdp_connect(request: RustRdpConnectRequest) -> Result<RustRdpConnectResult> {
    if request.host.trim().is_empty() || request.username.trim().is_empty() {
        return Err(anyhow!("RDP host and username are required"));
    }

    let config = ConfigBuilder::new()
        .with_destination(Destination::from_parts(request.host.trim(), request.port))
        .with_username(request.username)
        .with_password(request.password)
        .with_domain(request.domain)
        .with_client_build(0)
        .with_client_dir("")
        .with_client_name("Termethis")
        .with_platform(MajorPlatformType::ANDROID)
        .with_desktop_width(request.width.clamp(320, 8192))
        .with_desktop_height(request.height.clamp(200, 8192))
        .with_color_depth(32)
        .with_server_pointer(true)
        .with_pointer_software_rendering(true)
        .build()
        .context("Failed to configure IronRDP")?;

    let (output_sender, mut output_receiver) = mpsc::channel(2);
    let client = RdpClient::new(config, output_sender);
    let input = client.input_sender();
    let id = NEXT_RDP_ID.fetch_add(1, Ordering::Relaxed);
    let session = Arc::new(RdpSession {
        input,
        input_state: StdMutex::new(Database::new()),
        frame: Mutex::new(RdpFrameData {
            sequence: 0,
            width: request.width,
            height: request.height,
            pixels: Arc::new(Vec::new()),
            state: "connecting".to_owned(),
            error_message: None,
        }),
        changed: Notify::new(),
        closed: AtomicBool::new(false),
        #[cfg(target_os = "android")]
        renderer: AndroidVulkanRenderer::new(id),
    });
    #[cfg(target_os = "android")]
    let client = {
        let session = Arc::clone(&session);
        client.with_frame_callback(Arc::new(move |pixels, width, height, region| {
            session.renderer.render_frame(
                width.get(),
                height.get(),
                region.left,
                region.top,
                region.right,
                region.bottom,
                pixels,
            );
        }))
    };
    RDP_SESSIONS.insert(id, Arc::clone(&session));

    std::thread::Builder::new()
        .name(format!("ironrdp-{id}"))
        .spawn(move || {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("IronRDP runtime initialization failed");
            runtime.block_on(client.run());
        })
        .context("Failed to start IronRDP thread")?;

    tokio::spawn(async move {
        while let Some(event) = output_receiver.recv().await {
            let terminal = matches!(
                event,
                RdpOutputEvent::ConnectionFailure(_) | RdpOutputEvent::Terminated(_)
            );
            apply_output_event(&session, event).await;
            if terminal {
                break;
            }
        }
        session.closed.store(true, Ordering::Release);
        session.changed.notify_waiters();
    });

    Ok(RustRdpConnectResult {
        session_id: id,
        renderer: if cfg!(target_os = "android") {
            "IronRDP + native Vulkan Surface".to_owned()
        } else {
            "IronRDP + Flutter fallback".to_owned()
        },
    })
}

pub async fn rdp_read_status(session_id: i64) -> Result<RustRdpStatus> {
    let session = get_session(session_id)?;
    let frame = session.frame.lock().await;
    Ok(RustRdpStatus {
        sequence: frame.sequence,
        width: frame.width,
        height: frame.height,
        state: frame.state.clone(),
        error_message: frame.error_message.clone(),
        renderer: if cfg!(target_os = "android") {
            "native Vulkan Surface".to_owned()
        } else {
            "Flutter fallback".to_owned()
        },
        renderer_error: renderer_error(&session),
    })
}

pub async fn rdp_read_frame(
    session_id: i64,
    after_sequence: i64,
    wait_millis: u32,
) -> Result<RustRdpFrame> {
    let session = get_session(session_id)?;
    {
        let frame = session.frame.lock().await;
        if frame.sequence > after_sequence || session.closed.load(Ordering::Acquire) {
            return Ok(copy_frame_after(&frame, after_sequence));
        }
    }
    let notified = session.changed.notified();
    let _ = tokio::time::timeout(Duration::from_millis(u64::from(wait_millis)), notified).await;
    let frame = session.frame.lock().await;
    Ok(copy_frame_after(&frame, after_sequence))
}

pub async fn rdp_resize(session_id: i64, width: u16, height: u16) -> Result<()> {
    let session = get_session(session_id)?;
    session
        .input
        .send(RdpInputEvent::Resize {
            width: width.clamp(320, 8192),
            height: height.clamp(200, 8192),
            scale_factor: 100,
            physical_size: None,
        })
        .map_err(|error| anyhow!("RDP input queue is full: {error}"))?;
    Ok(())
}

pub async fn rdp_mouse(session_id: i64, x: u16, y: u16, button: i32, pressed: bool) -> Result<()> {
    let session = get_session(session_id)?;
    send_mouse_event(&session, x, y, button, pressed)
}

fn send_mouse_event(
    session: &RdpSession,
    x: u16,
    y: u16,
    button: i32,
    pressed: bool,
) -> Result<()> {
    let mut state = session
        .input_state
        .lock()
        .map_err(|_| anyhow!("RDP input state is unavailable"))?;
    let mut operations = vec![Operation::MouseMove(MousePosition { x, y })];
    if let Some(button) = match button {
        1 => Some(MouseButton::Left),
        2 => Some(MouseButton::Right),
        3 => Some(MouseButton::Middle),
        _ => None,
    } {
        operations.push(if pressed {
            Operation::MouseButtonPressed(button)
        } else {
            Operation::MouseButtonReleased(button)
        });
    }
    let events = state.apply(operations);
    drop(state);
    if !events.is_empty() {
        session
            .input
            .send(RdpInputEvent::FastPath(events))
            .map_err(|error| anyhow!("RDP input queue is full: {error}"))?;
    }
    Ok(())
}

pub async fn rdp_send_text(session_id: i64, text: String) -> Result<()> {
    let session = get_session(session_id)?;
    let mut state = session
        .input_state
        .lock()
        .map_err(|_| anyhow!("RDP input state is unavailable"))?;
    let operations = text.chars().flat_map(|character| {
        [
            Operation::UnicodeKeyPressed(character),
            Operation::UnicodeKeyReleased(character),
        ]
    });
    let events = state.apply(operations);
    drop(state);
    if !events.is_empty() {
        session
            .input
            .send(RdpInputEvent::FastPath(events))
            .map_err(|error| anyhow!("RDP input queue is full: {error}"))?;
    }
    Ok(())
}

pub async fn rdp_send_scancode(session_id: i64, scancode: u16, pressed: bool) -> Result<()> {
    let session = get_session(session_id)?;
    let mut state = session
        .input_state
        .lock()
        .map_err(|_| anyhow!("RDP input state is unavailable"))?;
    let key = Scancode::from_u16(scancode);
    let events = state.apply([if pressed {
        Operation::KeyPressed(key)
    } else {
        Operation::KeyReleased(key)
    }]);
    drop(state);
    if !events.is_empty() {
        session
            .input
            .send(RdpInputEvent::FastPath(events))
            .map_err(|error| anyhow!("RDP input queue is full: {error}"))?;
    }
    Ok(())
}

pub async fn rdp_close(session_id: i64) -> Result<()> {
    if let Some((_, session)) = RDP_SESSIONS.remove(&session_id) {
        let _ = session.input.send(RdpInputEvent::Close);
        session.closed.store(true, Ordering::Release);
        session.changed.notify_waiters();
    }
    Ok(())
}

async fn apply_output_event(session: &RdpSession, event: RdpOutputEvent) {
    let mut frame = session.frame.lock().await;
    match event {
        RdpOutputEvent::Image {
            buffer,
            width,
            height,
        } => {
            frame.sequence += 1;
            frame.width = width.get();
            frame.height = height.get();
            frame.pixels = Arc::new(buffer);
            frame.state = "ready".to_owned();
        }
        RdpOutputEvent::FramePresented { width, height } => {
            frame.sequence += 1;
            frame.width = width.get();
            frame.height = height.get();
            frame.state = "ready".to_owned();
        }
        RdpOutputEvent::ConnectionFailure(error) => {
            frame.state = "failed".to_owned();
            frame.error_message = Some(error.to_string());
            session.closed.store(true, Ordering::Release);
        }
        RdpOutputEvent::Terminated(result) => {
            frame.state = "closed".to_owned();
            frame.error_message = result.err().map(|error| error.to_string());
            session.closed.store(true, Ordering::Release);
        }
        _ => {}
    }
    drop(frame);
    session.changed.notify_waiters();
}

fn get_session(session_id: i64) -> Result<Arc<RdpSession>> {
    RDP_SESSIONS
        .get(&session_id)
        .map(|entry| Arc::clone(entry.value()))
        .ok_or_else(|| anyhow!("RDP session not found"))
}

fn copy_frame_after(frame: &RdpFrameData, after_sequence: i64) -> RustRdpFrame {
    let rgba = if frame.sequence > after_sequence {
        let mut rgba = Vec::with_capacity(frame.pixels.len().saturating_mul(4));
        for pixel in frame.pixels.iter().copied() {
            let [_, red, green, blue] = pixel.to_be_bytes();
            rgba.extend_from_slice(&[red, green, blue, 255]);
        }
        rgba
    } else {
        Vec::new()
    };
    RustRdpFrame {
        sequence: frame.sequence,
        width: frame.width,
        height: frame.height,
        rgba,
        state: frame.state.clone(),
        error_message: frame.error_message.clone(),
    }
}

#[cfg(target_os = "android")]
fn renderer_error(session: &RdpSession) -> Option<String> {
    session.renderer.error()
}

#[cfg(not(target_os = "android"))]
fn renderer_error(_session: &RdpSession) -> Option<String> {
    None
}

#[cfg(target_os = "android")]
pub(crate) fn android_attach_surface(
    session_id: i64,
    native_window: usize,
    width: u32,
    height: u32,
) -> bool {
    let Ok(session) = get_session(session_id) else {
        return false;
    };
    if !session.renderer.attach(native_window, width, height) {
        return false;
    }
    let _ = session.input.send(RdpInputEvent::Resize {
        width: width.clamp(320, 8192) as u16,
        height: height.clamp(200, 8192) as u16,
        scale_factor: 100,
        physical_size: None,
    });
    true
}

#[cfg(target_os = "android")]
pub(crate) fn android_detach_surface(session_id: i64) {
    if let Ok(session) = get_session(session_id) {
        session.renderer.detach();
    }
}

#[cfg(target_os = "android")]
pub(crate) fn android_surface_mouse(
    session_id: i64,
    surface_x: f32,
    surface_y: f32,
    button: i32,
    pressed: bool,
) -> bool {
    let Ok(session) = get_session(session_id) else {
        return false;
    };
    let Some((x, y)) = session.renderer.remote_coordinates(surface_x, surface_y) else {
        return false;
    };
    send_mouse_event(&session, x, y, button, pressed).is_ok()
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::{copy_frame_after, RdpFrameData};

    #[test]
    fn unchanged_frame_does_not_cross_the_bridge_again() {
        let frame = RdpFrameData {
            sequence: 4,
            width: 1920,
            height: 1080,
            pixels: Arc::new(vec![7; 1920 * 1080]),
            state: "ready".to_owned(),
            error_message: None,
        };

        let result = copy_frame_after(&frame, 4);

        assert!(result.rgba.is_empty());
        assert_eq!(result.sequence, 4);
        assert_eq!(result.state, "ready");
    }
}
