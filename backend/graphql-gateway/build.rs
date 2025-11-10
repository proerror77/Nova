fn main() {
    // GraphQL Gateway acts as gRPC CLIENT to call backend services
    // We only need client code, not server implementations

    println!("cargo:rerun-if-changed=../proto/services/auth_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/user_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/content_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/feed_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/common.proto");

    // Compile all protos together so they can reference each other
    let out_dir = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap());

    tonic_build::configure()
        .build_server(false) // GraphQL Gateway doesn't provide gRPC server
        .build_client(true) // GraphQL Gateway calls other services as client
        .file_descriptor_set_path(out_dir.join("nova_descriptor.bin"))
        .compile(
            &[
                "../proto/services/common.proto",
                "../proto/services/auth_service.proto",
                "../proto/services/user_service.proto",
                "../proto/services/content_service.proto",
                "../proto/services/feed_service.proto",
            ],
            &["../proto/services/"],
        )
        .expect("Failed to compile proto files for GraphQL Gateway");
}
