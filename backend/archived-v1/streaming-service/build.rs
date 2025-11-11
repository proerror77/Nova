fn main() {
    println!("cargo:rerun-if-changed=../proto/services/streaming_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/common.proto");
    // Compile proto files for gRPC server generation
    // streaming-service PROVIDES StreamingService (server implementation)
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(
            &[
                "../proto/services/streaming_service.proto",
                "../proto/services/common.proto",
            ],
            &["../proto/services/"],
        )
        .expect("Failed to compile streaming_service.proto");
}
