fn main() {
    // Compile proto files for gRPC server generation
    // video-service PROVIDES VideoService (server implementation)
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(
            &["../protos/video.proto"],
            &["../protos/"],
        )
        .expect("Failed to compile video.proto");
}
