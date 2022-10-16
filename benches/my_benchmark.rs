use criterion::{black_box, criterion_group, criterion_main, Criterion};

use mylib::satd_rust::*;
use mylib::*;

fn fibonacci(n: u64) -> u64 {
    match n {
        0 => 1,
        1 => 1,
        n => fibonacci(n - 1) + fibonacci(n - 2),
    }
}

fn criterion_benchmark(c: &mut Criterion) {
    let mut src = [0; 32];
    let mut dst = [0; 32];

    let stride = 8 * std::mem::size_of::<u16>();

    c.bench_function("Rust SATD 8x4", |b| {
        b.iter(|| satd8x4_rust(black_box(&src), black_box(&dst)))
    });

    c.bench_function("AVX2 SATD 8x4", |b| {
        b.iter(|| unsafe {
            rav1e_satd_8x4_16bpc_avx2(src.as_ptr(), stride, dst.as_ptr(), stride, (1 << 10) - 1)
        })
    });
}

criterion_group!(benches, criterion_benchmark);
criterion_main!(benches);
