fn main() {
    // Compile proto files for gRPC server generation
    // recommendation-service PROVIDES RecommendationService (server implementation)
    println!("cargo:rerun-if-changed=../proto/services/feed_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/common.proto");
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(
            &[
                "../proto/services/feed_service.proto",
                "../proto/services/common.proto",
            ],
            &["../proto/services/"],
        )
        .expect("Failed to compile feed_service.proto");
}
