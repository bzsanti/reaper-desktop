use std::env;
use std::path::PathBuf;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let output_dir = PathBuf::from(&crate_dir)
        .parent()
        .unwrap()
        .join("swift-ui")
        .join("Sources")
        .join("CHeaders");
    
    std::fs::create_dir_all(&output_dir).unwrap();
    
    cbindgen::Builder::new()
        .with_crate(crate_dir)
        .with_language(cbindgen::Language::C)
        .with_include_guard("CPU_MONITOR_CORE_H")
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file(output_dir.join("cpu_monitor_core.h"));
}