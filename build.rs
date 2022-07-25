fn main() {
    nasm_rs::compile_library("librav1easm.a", &["src/satd.asm"]).unwrap();

    println!("cargo:rustc-link-lib=static=rav1easm");
}
