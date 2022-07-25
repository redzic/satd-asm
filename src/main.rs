use rand::Rng;

use crate::satd_rust::satd4x4_rust;

mod satd_rust;

extern "C" {
    fn rav1e_satd_4x4_10bpc_avx2(x: &[i16; 16]) -> u64;
}

fn main() {
    let mut z = [0i16; 16];
    let mut zx = [0i32; 16];

    let mut rng = rand::thread_rng();

    // 10-bit -- we're good
    // 12-bit -- seems like something is wrong...

    loop {
        z.fill_with(|| rng.gen_range(-1023..=1023));
        // z.fill_with(|| rng.gen_range(-4095..=4095));

        let satd_asm = unsafe { rav1e_satd_4x4_10bpc_avx2(&z) };
        let satd_rust = {
            // cast to 32-bit
            for i in 0..16 {
                zx[i] = z[i] as i32;
            }
            satd4x4_rust(&mut zx)
        };

        assert_eq!(satd_asm, satd_rust);
    }
}
