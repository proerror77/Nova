fn main() {
    // Compile proto files for gRPC (both server + client for internal calls)
    println!("cargo:rerun-if-changed=../proto/services/feed_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/common.proto");
    println!("cargo:rerun-if-changed=../proto/services_v2/content_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/graph_service.proto");

    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .compile_protos(
            &[
                "../proto/services/feed_service.proto",
                "../proto/services/common.proto",
                "../proto/services_v2/content_service.proto",
                "../proto/services/graph_service.proto",
            ],
            &["../proto/services/", "../proto/services_v2/"],
        )
        .expect("Failed to compile proto files for feed-service");
}
