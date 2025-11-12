// Build scripts are allowed to panic on compilation errors
// Root workspace Cargo.toml updated to include all Phase E/F/G services
#![allow(clippy::panic)]

use std::path::PathBuf;

fn main() {
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR not set"));

    tonic_build::configure()
        .build_server(false)
        .build_client(true)
        .file_descriptor_set_path(out_dir.join("nova_descriptor.bin"))
        .type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]")
        .compile_protos(
            &[
                "../proto/services/common.proto",
                "../proto/services/auth_service.proto",
                "../proto/services/user_service.proto",
                "../proto/services/content_service.proto",
                "../proto/services/feed_service.proto",
            ],
            &["../proto/services/"],
        )
        .expect("Failed to compile protos");
}
