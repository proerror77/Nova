fn main() {
    println!("cargo:rerun-if-changed=../proto/services/video_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/common.proto");
    // Compile proto files for gRPC server generation
    // video-service PROVIDES VideoService (server implementation)
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile_protos(&["../proto/services/video_service.proto", "../proto/services/common.proto"], &["../proto/services/"])
        .expect("Failed to compile video_service.proto");
}
