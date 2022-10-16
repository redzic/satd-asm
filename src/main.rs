use rand::Rng;

use std::mem::transmute;

use mylib::{
    satd_rust::{satd4x8_rust, satd8x4_rust},
    *,
};

fn main() {
    let mut src = [0; 32];
    let mut dst = [0; 32];
    let mut buf = [0; 32];

    let mut rng = rand::thread_rng();

    // src.fill_with(|| rng.gen_range(0..=1023));
    // dst.fill_with(|| rng.gen_range(0..=1023));

    // println!("{src:?}");

    for i in 0..32 {
        // dst[i] = i as u16;
        dst[i] = i as u16;
    }

    let stride = 4 * 2;

    unsafe {
        let satd = rav1e_satd_4x8_16bpc_avx2(src.as_ptr(), stride, dst.as_ptr(), stride, &mut buf);
        // rav1e_satd_4x8_16bpc_avx2(src.as_ptr(), stride, dst.as_ptr(), stride, (1 << 10) - 1);

        let satd_rust = satd4x8_rust(&src, &dst);

        // println!("{satd:b}");
        // println!("{:b}", 736);

        println!("buf: {buf:?}");
        println!(" satd_asm: {satd}");
        println!("satd_rust: {satd_rust}");
    }
}

#[cfg(test)]
mod tests {
    use mylib::{
        rav1e_satd_4x4_16bpc_avx2, rav1e_satd_4x8_16bpc_avx2, rav1e_satd_8x4_16bpc_avx2,
        satd_rust::{satd4x4_rust, satd4x8_rust, satd8x4_rust},
    };
    use rand::Rng;

    #[test]
    fn check_8x4_satd_asm() {
        let mut src = [0; 32];
        let mut dst = [0; 32];

        let stride = 8 * std::mem::size_of::<u16>();

        let mut rng = rand::thread_rng();

        // TODO test 12 bit
        for bd in [10, 12] {
            for _ in 0..12000 {
                src.fill_with(|| rng.gen_range(0..=(1 << bd) - 1));
                dst.fill_with(|| rng.gen_range(0..=(1 << bd) - 1));

                let satd_avx2 = unsafe {
                    rav1e_satd_8x4_16bpc_avx2(
                        src.as_ptr(),
                        stride,
                        dst.as_ptr(),
                        stride,
                        (1 << bd) - 1,
                    )
                };
                let satd_rust = satd8x4_rust(&src, &dst);

                assert_eq!(satd_avx2, satd_rust);
            }
        }
    }

    #[test]
    fn check_4x8_satd_asm() {
        let mut src = [0; 32];
        let mut dst = [0; 32];

        let stride = 4 * std::mem::size_of::<u16>();

        let mut rng = rand::thread_rng();

        // TODO test 12 bit
        for bd in [10, 10] {
            for _ in 0..12000 {
                src.fill_with(|| rng.gen_range(0..=(1 << bd) - 1));
                dst.fill_with(|| rng.gen_range(0..=(1 << bd) - 1));

                let satd_avx2 = unsafe {
                    rav1e_satd_4x8_16bpc_avx2(
                        src.as_ptr(),
                        stride,
                        dst.as_ptr(),
                        stride,
                        (1 << bd) - 1,
                    )
                };
                let satd_rust = satd4x8_rust(&src, &dst);

                assert_eq!(satd_avx2, satd_rust);
            }
        }
    }

    #[test]
    fn check_4x4_satd_asm() {
        let mut src = [0; 16];
        let mut dst = [0; 16];

        let stride = 4 * std::mem::size_of::<u16>();

        let mut rng = rand::thread_rng();

        for bd in [10, 12] {
            for _ in 0..12000 {
                src.fill_with(|| rng.gen_range(0..=(1 << bd) - 1));
                dst.fill_with(|| rng.gen_range(0..=(1 << bd) - 1));

                let satd_avx2 = unsafe {
                    rav1e_satd_4x4_16bpc_avx2(
                        src.as_ptr(),
                        stride,
                        dst.as_ptr(),
                        stride,
                        (1 << bd) - 1,
                    )
                };
                let satd_rust = satd4x4_rust(&src, &dst);

                assert_eq!(satd_avx2, satd_rust);
            }
        }
    }
}
