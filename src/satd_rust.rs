#[inline(always)]
const fn butterfly(a: i32, b: i32) -> (i32, i32) {
    ((a + b), (a - b))
}

#[inline(always)]
#[allow(clippy::identity_op, clippy::erasing_op)]
fn hadamard4_1d<const LEN: usize, const N: usize, const STRIDE0: usize, const STRIDE1: usize>(
    data: &mut [i32; LEN],
) {
    for i in 0..N {
        let sub: &mut [i32] = &mut data[i * STRIDE0..];
        let (a0, a1) = butterfly(sub[0 * STRIDE1], sub[1 * STRIDE1]);
        let (a2, a3) = butterfly(sub[2 * STRIDE1], sub[3 * STRIDE1]);
        let (b0, b2) = butterfly(a0, a2);
        let (b1, b3) = butterfly(a1, a3);
        sub[0 * STRIDE1] = b0;
        sub[1 * STRIDE1] = b1;
        sub[2 * STRIDE1] = b2;
        sub[3 * STRIDE1] = b3;
    }
}

#[inline(always)]
#[allow(clippy::identity_op, clippy::erasing_op)]
fn hadamard8_1d<const LEN: usize, const N: usize, const STRIDE0: usize, const STRIDE1: usize>(
    data: &mut [i32; LEN],
) {
    for i in 0..N {
        let sub: &mut [i32] = &mut data[i * STRIDE0..];

        let (a0, a1) = butterfly(sub[0 * STRIDE1], sub[1 * STRIDE1]);
        let (a2, a3) = butterfly(sub[2 * STRIDE1], sub[3 * STRIDE1]);
        let (a4, a5) = butterfly(sub[4 * STRIDE1], sub[5 * STRIDE1]);
        let (a6, a7) = butterfly(sub[6 * STRIDE1], sub[7 * STRIDE1]);

        let (b0, b2) = butterfly(a0, a2);
        let (b1, b3) = butterfly(a1, a3);
        let (b4, b6) = butterfly(a4, a6);
        let (b5, b7) = butterfly(a5, a7);

        let (c0, c4) = butterfly(b0, b4);
        let (c1, c5) = butterfly(b1, b5);
        let (c2, c6) = butterfly(b2, b6);
        let (c3, c7) = butterfly(b3, b7);

        sub[0 * STRIDE1] = c0;
        sub[1 * STRIDE1] = c1;
        sub[2 * STRIDE1] = c2;
        sub[3 * STRIDE1] = c3;
        sub[4 * STRIDE1] = c4;
        sub[5 * STRIDE1] = c5;
        sub[6 * STRIDE1] = c6;
        sub[7 * STRIDE1] = c7;
    }
}

#[inline(always)]
fn hadamard2d<const LEN: usize, const W: usize, const H: usize>(data: &mut [i32; LEN]) {
    /*Vertical transform.*/
    let vert_func = if H == 4 {
        hadamard4_1d::<LEN, W, 1, H>
    } else {
        hadamard8_1d::<LEN, W, 1, H>
    };
    vert_func(data);
    /*Horizontal transform.*/
    let horz_func = if W == 4 {
        hadamard4_1d::<LEN, H, W, 1>
    } else {
        hadamard8_1d::<LEN, H, W, 1>
    };
    horz_func(data);
}

// SAFETY: The length of data must be 16.
unsafe fn hadamard4x4(data: &mut [i32]) {
    hadamard2d::<{ 4 * 4 }, 4, 4>(&mut *(data.as_mut_ptr() as *mut [i32; 16]));
}

// pub fn satd4x4_rust(data: &[u8; 16]) -> u64 {
//     let mut tmp = [0; 16];
//     for i in 0..16 {
//         tmp[i] = data[i] as i32;
//     }
//     satd4x4(&mut tmp)
// }

pub fn satd4x4_rust(data: &mut [i32; 16]) -> u64 {
    unsafe {
        hadamard4x4(data);
    }

    data.iter().map(|&x| x.unsigned_abs() as u64).sum()
}

// SAFETY: The length of data must be 64.
unsafe fn hadamard8x8(data: &mut [i32]) {
    hadamard2d::<{ 8 * 8 }, 8, 8>(&mut *(data.as_mut_ptr() as *mut [i32; 64]));
}

#[inline(always)]
pub fn msb(x: i32) -> i32 {
    debug_assert!(x > 0);
    31 ^ (x.leading_zeros() as i32)
}

// pub unsafe fn rav1e_satd_8x8_hbd_avx2(
//     // plane_org: &PlaneRegion<'_, T>,
//     // plane_ref: &PlaneRegion<'_, T>,
//     // w: usize,
//     // h: usize,
//     // _bit_depth: usize,
//     src: *const u16,
//     src_stride: isize,
//     dst: *const u16,
//     dst_stride: isize,
// ) -> u32 {
//     let w = 8;
//     let h = 8;
//     // assert!(w <= 128 && h <= 128);
//     // assert!(plane_org.rect().width >= w && plane_org.rect().height >= h);
//     // assert!(plane_ref.rect().width >= w && plane_ref.rect().height >= h);

//     // Size of hadamard transform should be 4x4 or 8x8
//     // 4x* and *x4 use 4x4 and all other use 8x8
//     // let size: usize = w.min(h).min(8);
//     let size: usize = 8;
//     let tx2d = if size == 4 { hadamard4x4 } else { hadamard8x8 };

//     let mut sum: u64 = 0;

//     // Loop over chunks the size of the chosen transform
//     for chunk_y in (0..h).step_by(size) {
//         for chunk_x in (0..w).step_by(size) {
//             // let chunk_area: Area = Area::Rect {
//             //     x: chunk_x as isize,
//             //     y: chunk_y as isize,
//             //     width: chunk_w,
//             //     height: chunk_h,
//             // };
//             // let chunk_org = plane_org.subregion(chunk_area);
//             let chunk_org = src.offset(src_stride * chunk_y as isize + chunk_x as isize);
//             // let chunk_ref = plane_ref.subregion(chunk_area);
//             let chunk_ref = dst.offset(dst_stride * chunk_y as isize + chunk_x as isize);

//             let buf: &mut [i32] = &mut [0; 8 * 8][..size * size];

//             // Move the difference of the transforms to a buffer
//             // for (row_diff, (row_org, row_ref)) in buf
//             for (idx, row_diff) in buf.chunks_exact_mut(size).enumerate()
//             // .zip(chunk_org.rows_iter().zip(chunk_ref.rows_iter()))
//             {
//                 let row_org =
//                     std::slice::from_raw_parts(chunk_org.add(idx * src_stride as usize), 8);
//                 let row_ref =
//                     std::slice::from_raw_parts(chunk_ref.add(idx * dst_stride as usize), 8);
//                 for (diff, (a, b)) in row_diff.iter_mut().zip(row_org.iter().zip(row_ref.iter())) {
//                     *diff = *a as i32 - *b as i32;
//                 }
//             }

//             // Perform the hadamard transform on the differences
//             // SAFETY: A sufficient number elements exist for the size of the transform.
//             tx2d(buf);

//             // Sum the absolute values of the transformed differences
//             sum += buf.iter().map(|a| a.unsigned_abs() as u64).sum::<u64>();
//         }
//     }

//     // Normalize the results
//     let ln = msb(size as i32) as u64;
//     ((sum + (1 << ln >> 1)) >> ln) as u32
// }
