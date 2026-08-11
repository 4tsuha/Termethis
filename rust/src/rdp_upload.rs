#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct UploadRegion {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
    pub offset: u64,
    pub bytes_per_row: u32,
}

impl UploadRegion {
    pub(crate) fn from_dirty_rect(
        frame_width: u16,
        frame_height: u16,
        left: u16,
        top: u16,
        right: u16,
        bottom: u16,
        force_full_upload: bool,
    ) -> Self {
        let frame_width = u32::from(frame_width.max(1));
        let frame_height = u32::from(frame_height.max(1));
        let bytes_per_row = frame_width * 4;
        if force_full_upload {
            return Self {
                x: 0,
                y: 0,
                width: frame_width,
                height: frame_height,
                offset: 0,
                bytes_per_row,
            };
        }

        let left = u32::from(left).min(frame_width - 1);
        let top = u32::from(top).min(frame_height - 1);
        let right = u32::from(right).clamp(left, frame_width - 1);
        let bottom = u32::from(bottom).clamp(top, frame_height - 1);
        Self {
            x: left,
            y: top,
            width: right - left + 1,
            height: bottom - top + 1,
            offset: u64::from(top * bytes_per_row + left * 4),
            bytes_per_row,
        }
    }

    #[cfg(test)]
    fn transferred_bytes(self) -> u64 {
        u64::from(self.width) * u64::from(self.height) * 4
    }
}

#[cfg(test)]
mod tests {
    use super::UploadRegion;

    #[test]
    fn small_dirty_rect_avoids_full_frame_upload() {
        let region = UploadRegion::from_dirty_rect(1920, 1080, 64, 32, 127, 95, false);

        assert_eq!(region.x, 64);
        assert_eq!(region.y, 32);
        assert_eq!(region.width, 64);
        assert_eq!(region.height, 64);
        assert_eq!(region.offset, ((32 * 1920 + 64) * 4) as u64);
        assert_eq!(region.bytes_per_row, 1920 * 4);
        assert_eq!(region.transferred_bytes(), 16 * 1024);
        assert!(region.transferred_bytes() * 500 < 1920 * 1080 * 4);
    }

    #[test]
    fn new_texture_is_initialized_with_a_full_upload() {
        let region = UploadRegion::from_dirty_rect(1920, 1080, 64, 32, 127, 95, true);

        assert_eq!(region.x, 0);
        assert_eq!(region.y, 0);
        assert_eq!(region.width, 1920);
        assert_eq!(region.height, 1080);
        assert_eq!(region.offset, 0);
    }
}
