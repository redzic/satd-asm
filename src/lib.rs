pub mod satd_rust;

extern "C" {
    pub fn rav1e_satd_8x4_16bpc_avx2(
        src: *const u16,
        src_stride: usize,
        dst: *const u16,
        dst_stride: usize,
        bdmax: u32,
    ) -> u64;

    pub fn rav1e_satd_4x4_16bpc_avx2(
        src: *const u16,
        src_stride: usize,
        dst: *const u16,
        dst_stride: usize,
        bdmax: u32,
    ) -> u64;
}
