use rand::Rng;

use crate::satd_rust::satd4x4_rust;

mod satd_rust;

extern "C" {
    fn satd4x4_asm(x: &[i16; 16], buf: &mut [i16; 16]) -> u64;
}

fn satd4x4_asm_wrapper(x: &[i16; 16]) -> u64 {
    let mut tmp = [0; 16];
    unsafe {
        satd4x4_asm(&x, &mut tmp);
    }

    tmp.iter().map(|x| (*x as i64).unsigned_abs()).sum()
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

        let satd_asm = satd4x4_asm_wrapper(&z);
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
