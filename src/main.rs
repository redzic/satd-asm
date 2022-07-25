use rand::Rng;

use crate::satd_rust::satd4x4_rust;

mod satd_rust;

extern "C" {
    fn rav1e_satd_4x4_10bpc_avx2(
        src: *const u16,
        src_stride: usize,
        dst: *const u16,
        dst_stride: usize,
    ) -> u64;
}

fn main() {
    let mut src = [0; 16];
    let mut dst = [0; 16];

    let stride = 4 * std::mem::size_of::<u16>();

    let mut rng = rand::thread_rng();

    // 10-bit -- we're good
    // 12-bit -- 32-bit precision is required

    loop {
        src.fill_with(|| rng.gen_range(0..=1023));
        dst.fill_with(|| rng.gen_range(0..=1023));

        let satd_asm =
            unsafe { rav1e_satd_4x4_10bpc_avx2(src.as_ptr(), stride, dst.as_ptr(), stride) };
        let satd_rust = satd4x4_rust(&src, &dst);

        assert_eq!(satd_asm, satd_rust);
    }
}
