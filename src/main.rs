use rand::Rng;

use crate::satd_rust::{hadamard4x4, satd, satd4x4_rust};
use std::mem::transmute;

mod satd_rust;

extern "C" {
    fn rav1e_satd_4x4_16bpc_avx2(
        src: *const u16,
        src_stride: usize,
        dst: *const u16,
        dst_stride: usize,
        bdmax: u32,
    ) -> u64;
}

fn main() {
    let mut src = [0; 16];
    let mut dst = [0; 16];
    let mut buf = [0; 16];

    for i in 0..16 {
        src[i] = i as u16;
    }

    unsafe {
        let satd = rav1e_satd_4x4_16bpc_avx2(src.as_ptr(), 8, dst.as_ptr(), 8, (1 << 10) - 1);
        // let satd = rav1e_satd_4x4_hbd_avx2(src.as_ptr(), 8, dst.as_ptr(), 8, (1 << 12) - 1);
        // let satd = rav1e_satd_4x4_10bpc_avx2(src.as_ptr(), 8, dst.as_ptr(), 8);

        let satd_rust = satd4x4_rust(&src, &dst);

        println!("buf: {buf:?}");
        println!(" satd_asm: {satd}");
        println!("satd_rust: {satd_rust}");
    }
}

#[cfg(test)]
mod tests {
    use rand::Rng;

    use crate::{satd_rust::satd4x4_rust, *};

    #[test]
    fn check() {
        let mut src = [0; 16];
        let mut dst = [0; 16];

        let stride = 4 * std::mem::size_of::<u16>();

        let mut rng = rand::thread_rng();

        // 10-bit -- we're good
        // 12-bit -- 32-bit precision is required

        loop {
            src.fill_with(|| rng.gen_range(0..=4095));
            dst.fill_with(|| rng.gen_range(0..=4095));

            let satd_avx2 = unsafe {
                rav1e_satd_4x4_16bpc_avx2(src.as_ptr(), stride, dst.as_ptr(), stride, (1 << 12) - 1)
            };
            let satd_rust = satd4x4_rust(&src, &dst);

            assert_eq!(satd_avx2, satd_rust);
        }
    }
}
