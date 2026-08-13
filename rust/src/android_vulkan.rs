use std::ffi::c_void;
use std::ffi::CString;
use std::ptr::NonNull;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{mpsc, Arc, Mutex};

use jni::objects::{JClass, JObject};
use jni::sys::{jboolean, jfloat, jint, jlong, JNI_FALSE, JNI_TRUE};
use jni::JNIEnv;
use raw_window_handle::{
    AndroidDisplayHandle, AndroidNdkWindowHandle, RawDisplayHandle, RawWindowHandle,
};

use crate::api::rdp::{android_attach_surface, android_detach_surface, android_surface_mouse};
use crate::rdp_upload::UploadRegion;

const FRAME_SHADER: &str = r#"
struct VertexOutput {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>( 3.0, -1.0),
    vec2<f32>(-1.0,  3.0),
  );
  var uvs = array<vec2<f32>, 3>(
    vec2<f32>(0.0, 1.0),
    vec2<f32>(2.0, 1.0),
    vec2<f32>(0.0, -1.0),
  );
  var output: VertexOutput;
  output.position = vec4<f32>(positions[vertex_index], 0.0, 1.0);
  output.uv = uvs[vertex_index];
  return output;
}

@group(0) @binding(0) var frame_texture: texture_2d<f32>;
@group(0) @binding(1) var frame_sampler: sampler;

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
  return vec4<f32>(textureSample(frame_texture, frame_sampler, input.uv).rgb, 1.0);
}
"#;

pub(crate) struct AndroidVulkanRenderer {
    command: mpsc::SyncSender<RenderCommand>,
    surface: Arc<Mutex<Option<VulkanSurface>>>,
    pending_frame: Arc<Mutex<Option<PendingFrame>>>,
    metrics: Arc<Mutex<RenderMetrics>>,
    error: Arc<Mutex<Option<String>>>,
    next_sequence: AtomicI64,
}

#[derive(Default)]
struct RenderMetrics {
    surface_width: u32,
    surface_height: u32,
    frame_width: u16,
    frame_height: u16,
}

struct PendingFrame {
    sequence: i64,
    width: u16,
    height: u16,
    dirty_left: u16,
    dirty_top: u16,
    dirty_right: u16,
    dirty_bottom: u16,
    pixels: Vec<u8>,
}

enum RenderCommand {
    Attach {
        native_window: usize,
        width: u32,
        height: u32,
    },
    Present,
    Detach(mpsc::SyncSender<()>),
    Stop,
}

impl AndroidVulkanRenderer {
    pub(crate) fn new(session_id: i64) -> Self {
        // One pending present is enough: every upload updates the same texture,
        // so a queued present always shows the newest completed update.
        let (command, receiver) = mpsc::sync_channel(2);
        let surface = Arc::new(Mutex::new(None));
        let pending_frame = Arc::new(Mutex::new(None));
        let metrics = Arc::new(Mutex::new(RenderMetrics::default()));
        let error = Arc::new(Mutex::new(None));
        let renderer = Self {
            command,
            surface: Arc::clone(&surface),
            pending_frame: Arc::clone(&pending_frame),
            metrics: Arc::clone(&metrics),
            error: Arc::clone(&error),
            next_sequence: AtomicI64::new(1),
        };
        std::thread::Builder::new()
            .name(format!("rdp-vulkan-{session_id}"))
            .spawn(move || render_loop(receiver, surface, pending_frame, metrics, error))
            .expect("Vulkan rendering thread initialization failed");
        renderer
    }

    pub(crate) fn attach(&self, native_window: usize, width: u32, height: u32) -> bool {
        if native_window == 0 || width == 0 || height == 0 {
            return false;
        }
        if self
            .command
            .send(RenderCommand::Attach {
                native_window,
                width,
                height,
            })
            .is_err()
        {
            return false;
        }
        true
    }

    pub(crate) fn detach(&self) {
        let (completed, receiver) = mpsc::sync_channel(0);
        if self.command.send(RenderCommand::Detach(completed)).is_ok() {
            let _ = receiver.recv_timeout(std::time::Duration::from_secs(1));
        }
    }

    #[expect(clippy::too_many_arguments)]
    pub(crate) fn render_frame(
        &self,
        width: u16,
        height: u16,
        dirty_left: u16,
        dirty_top: u16,
        dirty_right: u16,
        dirty_bottom: u16,
        pixels: &[u8],
    ) {
        if let Ok(mut metrics) = self.metrics.lock() {
            metrics.frame_width = width;
            metrics.frame_height = height;
        }
        let sequence = self.next_sequence.fetch_add(1, Ordering::Relaxed);
        let mut uploaded = false;
        let result = self
            .surface
            .lock()
            .map_err(|_| "Vulkan Surfaceをロックできませんでした".to_owned())
            .and_then(|mut surface| {
                if let Some(surface) = surface.as_mut() {
                    uploaded = true;
                    return surface.upload(
                        sequence,
                        width,
                        height,
                        dirty_left,
                        dirty_top,
                        dirty_right,
                        dirty_bottom,
                        pixels,
                    );
                }
                let required_bytes = usize::from(width)
                    .saturating_mul(usize::from(height))
                    .saturating_mul(4);
                if pixels.len() < required_bytes {
                    return Err("IronRDP frame buffer is shorter than expected".to_owned());
                }
                if let Ok(mut pending) = self.pending_frame.lock() {
                    *pending = Some(PendingFrame {
                        sequence,
                        width,
                        height,
                        dirty_left,
                        dirty_top,
                        dirty_right,
                        dirty_bottom,
                        pixels: pixels[..required_bytes].to_vec(),
                    });
                }
                Ok(())
            });
        if let Err(message) = result {
            if let Ok(mut current_error) = self.error.lock() {
                *current_error = Some(message);
            }
        } else if uploaded || self.pending_frame.lock().is_ok_and(|frame| frame.is_some()) {
            let _ = self.command.try_send(RenderCommand::Present);
        }
    }

    pub(crate) fn remote_coordinates(&self, x: f32, y: f32) -> Option<(u16, u16)> {
        let metrics = self.metrics.lock().ok()?;
        let frame_width = f32::from(metrics.frame_width);
        let frame_height = f32::from(metrics.frame_height);
        let surface_width = metrics.surface_width as f32;
        let surface_height = metrics.surface_height as f32;
        if frame_width <= 0.0
            || frame_height <= 0.0
            || surface_width <= 0.0
            || surface_height <= 0.0
        {
            return None;
        }
        let scale = (surface_width / frame_width).min(surface_height / frame_height);
        let left = (surface_width - frame_width * scale) * 0.5;
        let top = (surface_height - frame_height * scale) * 0.5;
        let remote_x = ((x - left) / scale).round().clamp(0.0, frame_width - 1.0) as u16;
        let remote_y = ((y - top) / scale).round().clamp(0.0, frame_height - 1.0) as u16;
        Some((remote_x, remote_y))
    }

    pub(crate) fn error(&self) -> Option<String> {
        self.error.lock().ok().and_then(|value| value.clone())
    }
}

impl Drop for AndroidVulkanRenderer {
    fn drop(&mut self) {
        let _ = self.command.send(RenderCommand::Stop);
    }
}

fn render_loop(
    receiver: mpsc::Receiver<RenderCommand>,
    shared_surface: Arc<Mutex<Option<VulkanSurface>>>,
    pending_frame: Arc<Mutex<Option<PendingFrame>>>,
    metrics: Arc<Mutex<RenderMetrics>>,
    error: Arc<Mutex<Option<String>>>,
) {
    while let Ok(command) = receiver.recv() {
        match command {
            RenderCommand::Attach {
                native_window,
                width,
                height,
            } => {
                if let Ok(mut surface) = shared_surface.lock() {
                    *surface = None;
                }
                match VulkanSurface::new(native_window, width, height) {
                    Ok(next) => {
                        if let Ok(mut surface) = shared_surface.lock() {
                            *surface = Some(next);
                        }
                        if let Ok(mut current_error) = error.lock() {
                            *current_error = None;
                        }
                        if let Ok(mut current_metrics) = metrics.lock() {
                            current_metrics.surface_width = width;
                            current_metrics.surface_height = height;
                        }
                        present_latest(&shared_surface, &pending_frame, &error);
                    }
                    Err(message) => {
                        if let Ok(mut current_error) = error.lock() {
                            *current_error = Some(message);
                        }
                    }
                }
            }
            RenderCommand::Present => {
                present_latest(&shared_surface, &pending_frame, &error);
            }
            RenderCommand::Detach(completed) => {
                if let Ok(mut surface) = shared_surface.lock() {
                    *surface = None;
                }
                if let Ok(mut current_metrics) = metrics.lock() {
                    current_metrics.surface_width = 0;
                    current_metrics.surface_height = 0;
                }
                if let Ok(mut pending) = pending_frame.lock() {
                    *pending = None;
                }
                let _ = completed.send(());
            }
            RenderCommand::Stop => {
                break;
            }
        }
    }
}

fn present_latest(
    shared_surface: &Arc<Mutex<Option<VulkanSurface>>>,
    pending_frame: &Arc<Mutex<Option<PendingFrame>>>,
    error: &Arc<Mutex<Option<String>>>,
) {
    let result = shared_surface
        .lock()
        .map_err(|_| "Vulkan Surfaceをロックできませんでした".to_owned())
        .and_then(|mut surface| {
            let Some(surface) = surface.as_mut() else {
                return Ok(());
            };
            if let Some(frame) = pending_frame.lock().ok().and_then(|mut frame| frame.take()) {
                surface.upload(
                    frame.sequence,
                    frame.width,
                    frame.height,
                    frame.dirty_left,
                    frame.dirty_top,
                    frame.dirty_right,
                    frame.dirty_bottom,
                    &frame.pixels,
                )?;
            }
            surface.present()
        });
    if let Err(message) = result {
        if let Ok(mut current_error) = error.lock() {
            *current_error = Some(message);
        }
    }
}

fn android_log(message: &str) {
    let Ok(tag) = CString::new("TermethisRdpVulkan") else {
        return;
    };
    let Ok(message) = CString::new(message) else {
        return;
    };
    unsafe {
        ndk_sys::__android_log_write(6, tag.as_ptr(), message.as_ptr());
    }
}

struct NativeWindow(NonNull<ndk_sys::ANativeWindow>);

// ANativeWindow is reference-counted by the NDK. Access is serialized by the
// renderer mutex and the acquired reference remains alive until Drop.
unsafe impl Send for NativeWindow {}

impl Drop for NativeWindow {
    fn drop(&mut self) {
        unsafe { ndk_sys::ANativeWindow_release(self.0.as_ptr()) };
    }
}

struct FrameTexture {
    width: u16,
    height: u16,
    texture: wgpu::Texture,
    bind_group: wgpu::BindGroup,
}

struct VulkanSurface {
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    pipeline: wgpu::RenderPipeline,
    bind_group_layout: wgpu::BindGroupLayout,
    sampler: wgpu::Sampler,
    frame_texture: Option<FrameTexture>,
    last_uploaded_sequence: i64,
    last_presented_sequence: i64,
    _window: NativeWindow,
}

impl VulkanSurface {
    fn new(native_window: usize, width: u32, height: u32) -> Result<Self, String> {
        let window = NonNull::new(native_window as *mut ndk_sys::ANativeWindow)
            .map(NativeWindow)
            .ok_or_else(|| "Android Surfaceが無効です".to_owned())?;
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::VULKAN,
            ..Default::default()
        });
        let raw_window_handle =
            RawWindowHandle::AndroidNdk(AndroidNdkWindowHandle::new(window.0.cast::<c_void>()));
        let surface = unsafe {
            instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::RawHandle {
                raw_display_handle: RawDisplayHandle::Android(AndroidDisplayHandle::new()),
                raw_window_handle,
            })
        }
        .map_err(|cause| format!("Vulkan Surfaceを作成できませんでした: {cause}"))?;
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            compatible_surface: Some(&surface),
        }))
        .map_err(|cause| format!("Vulkanアダプターを取得できませんでした: {cause}"))?;
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("Termethis RDP Vulkan device"),
            required_features: wgpu::Features::empty(),
            required_limits: wgpu::Limits::downlevel_defaults(),
            memory_hints: wgpu::MemoryHints::MemoryUsage,
            ..Default::default()
        }))
        .map_err(|cause| format!("Vulkanデバイスを作成できませんでした: {cause}"))?;
        device.on_uncaptured_error(Arc::new(|cause| {
            android_log(&format!("uncaptured error: {cause}"));
        }));
        let mut config = surface
            .get_default_config(&adapter, width.max(1), height.max(1))
            .ok_or_else(|| "Vulkanスワップチェーン設定が見つかりません".to_owned())?;
        config.present_mode = wgpu::PresentMode::Fifo;
        config.desired_maximum_frame_latency = 1;
        let capabilities = surface.get_capabilities(&adapter);
        config.alpha_mode = if capabilities
            .alpha_modes
            .contains(&wgpu::CompositeAlphaMode::Opaque)
        {
            wgpu::CompositeAlphaMode::Opaque
        } else {
            capabilities
                .alpha_modes
                .first()
                .copied()
                .unwrap_or(wgpu::CompositeAlphaMode::Auto)
        };
        surface.configure(&device, &config);

        let validation_scope = device.push_error_scope(wgpu::ErrorFilter::Validation);
        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("Termethis RDP frame layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
            ],
        });
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Termethis RDP pipeline layout"),
            bind_group_layouts: &[&bind_group_layout],
            immediate_size: 0,
        });
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Termethis RDP frame shader"),
            source: wgpu::ShaderSource::Wgsl(FRAME_SHADER.into()),
        });
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Termethis RDP Vulkan pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                buffers: &[],
            },
            primitive: wgpu::PrimitiveState::default(),
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                compilation_options: wgpu::PipelineCompilationOptions::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: config.format,
                    blend: None,
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            multiview_mask: None,
            cache: None,
        });
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("Termethis RDP frame sampler"),
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });
        if let Some(cause) = pollster::block_on(validation_scope.pop()) {
            return Err(format!(
                "Vulkan描画パイプラインを作成できませんでした: {cause}"
            ));
        }
        Ok(Self {
            surface,
            device,
            queue,
            config,
            pipeline,
            bind_group_layout,
            sampler,
            frame_texture: None,
            last_uploaded_sequence: 0,
            last_presented_sequence: 0,
            _window: window,
        })
    }

    fn upload(
        &mut self,
        sequence: i64,
        width: u16,
        height: u16,
        dirty_left: u16,
        dirty_top: u16,
        dirty_right: u16,
        dirty_bottom: u16,
        pixels: &[u8],
    ) -> Result<(), String> {
        if sequence <= self.last_uploaded_sequence || pixels.is_empty() {
            return Ok(());
        }
        let texture_created = self.ensure_frame_texture(width, height);
        let upload = UploadRegion::from_dirty_rect(
            width,
            height,
            dirty_left,
            dirty_top,
            dirty_right,
            dirty_bottom,
            texture_created,
        );
        let required_bytes = usize::from(width)
            .saturating_mul(usize::from(height))
            .saturating_mul(4);
        if pixels.len() < required_bytes {
            return Err("IronRDPフレームの長さが不足しています".to_owned());
        }
        let texture = self
            .frame_texture
            .as_ref()
            .ok_or_else(|| "RDPフレームテクスチャを作成できませんでした".to_owned())?;
        self.queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &texture.texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: upload.x,
                    y: upload.y,
                    z: 0,
                },
                aspect: wgpu::TextureAspect::All,
            },
            pixels,
            wgpu::TexelCopyBufferLayout {
                offset: upload.offset,
                bytes_per_row: Some(upload.bytes_per_row),
                rows_per_image: Some(upload.height),
            },
            wgpu::Extent3d {
                width: upload.width,
                height: upload.height,
                depth_or_array_layers: 1,
            },
        );
        self.last_uploaded_sequence = sequence;
        Ok(())
    }

    fn present(&mut self) -> Result<(), String> {
        if self.last_uploaded_sequence <= self.last_presented_sequence {
            return Ok(());
        }
        let texture = self
            .frame_texture
            .as_ref()
            .ok_or_else(|| "RDPフレームテクスチャを作成できませんでした".to_owned())?;
        let output = match self.surface.get_current_texture() {
            Ok(output) => output,
            Err(wgpu::SurfaceError::Lost | wgpu::SurfaceError::Outdated) => {
                self.surface.configure(&self.device, &self.config);
                self.surface
                    .get_current_texture()
                    .map_err(|cause| format!("Vulkanフレームを取得できませんでした: {cause}"))?
            }
            Err(wgpu::SurfaceError::Timeout) => return Ok(()),
            Err(cause) => return Err(format!("Vulkanフレームを取得できませんでした: {cause}")),
        };
        let target = output
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Termethis RDP Vulkan encoder"),
            });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Termethis RDP Vulkan pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &target,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            let (left, top, width, height) = fitted_viewport(
                self.config.width,
                self.config.height,
                texture.width,
                texture.height,
            );
            pass.set_viewport(left, top, width, height, 0.0, 1.0);
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &texture.bind_group, &[]);
            pass.draw(0..3, 0..1);
        }
        self.queue.submit([encoder.finish()]);
        output.present();
        self.last_presented_sequence = self.last_uploaded_sequence;
        Ok(())
    }

    fn ensure_frame_texture(&mut self, width: u16, height: u16) -> bool {
        if self
            .frame_texture
            .as_ref()
            .is_some_and(|texture| texture.width == width && texture.height == height)
        {
            return false;
        }
        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Termethis RDP BGRA frame"),
            size: wgpu::Extent3d {
                width: u32::from(width),
                height: u32::from(height),
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Termethis RDP frame bind group"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&self.sampler),
                },
            ],
        });
        self.frame_texture = Some(FrameTexture {
            width,
            height,
            texture,
            bind_group,
        });
        true
    }
}

fn fitted_viewport(
    surface_width: u32,
    surface_height: u32,
    frame_width: u16,
    frame_height: u16,
) -> (f32, f32, f32, f32) {
    let surface_width = surface_width.max(1) as f32;
    let surface_height = surface_height.max(1) as f32;
    let frame_width = f32::from(frame_width.max(1));
    let frame_height = f32::from(frame_height.max(1));
    let scale = (surface_width / frame_width).min(surface_height / frame_height);
    let width = frame_width * scale;
    let height = frame_height * scale;
    (
        (surface_width - width) * 0.5,
        (surface_height - height) * 0.5,
        width,
        height,
    )
}

#[no_mangle]
pub unsafe extern "system" fn Java_jp_yts_termethis_RdpVulkanBridge_nativeAttachSurface(
    env: JNIEnv,
    _class: JClass,
    session_id: jlong,
    surface: JObject,
    width: jint,
    height: jint,
) -> jboolean {
    let native_window =
        ndk_sys::ANativeWindow_fromSurface(env.get_native_interface(), surface.as_raw());
    if native_window.is_null() {
        return JNI_FALSE;
    }
    if android_attach_surface(
        session_id,
        native_window as usize,
        width.max(1) as u32,
        height.max(1) as u32,
    ) {
        JNI_TRUE
    } else {
        ndk_sys::ANativeWindow_release(native_window);
        JNI_FALSE
    }
}

#[no_mangle]
pub extern "system" fn Java_jp_yts_termethis_RdpVulkanBridge_nativeDetachSurface(
    _env: JNIEnv,
    _class: JClass,
    session_id: jlong,
) {
    android_detach_surface(session_id);
}

#[no_mangle]
pub extern "system" fn Java_jp_yts_termethis_RdpVulkanBridge_nativeMouse(
    _env: JNIEnv,
    _class: JClass,
    session_id: jlong,
    x: jfloat,
    y: jfloat,
    button: jint,
    pressed: jboolean,
) -> jboolean {
    if android_surface_mouse(session_id, x, y, button, pressed != JNI_FALSE) {
        JNI_TRUE
    } else {
        JNI_FALSE
    }
}

#[cfg(test)]
mod tests {
    use super::fitted_viewport;

    #[test]
    fn viewport_preserves_remote_aspect_ratio() {
        let (left, top, width, height) = fitted_viewport(1080, 1920, 1920, 1080);
        assert_eq!(left, 0.0);
        assert!(top > 600.0);
        assert_eq!(width, 1080.0);
        assert_eq!(height, 607.5);
    }
}
