use rand::Rng;

use crate::satd_rust::satd4x4_rust;

mod satd_rust;

extern "C" {
    fn satd4x4_asm(x: &[u8; 16], buf: &mut [i16; 16]) -> u64;
}

fn satd4x4_asm_wrapper(x: &[u8; 16]) -> u64 {
    let mut tmp = [0; 16];
    unsafe {
        satd4x4_asm(&x, &mut tmp);
    }

    tmp.iter().map(|x| (*x as i64).unsigned_abs()).sum()
}

fn main() {
    let mut z = [0; 16];

    let mut rng = rand::thread_rng();

    loop {
        z.fill_with(|| rng.gen());

        let satd = satd4x4_asm_wrapper(&z);
        let satd2 = satd4x4_rust(&z);

        assert_eq!(satd, satd2);
    }
}
