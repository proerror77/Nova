fn main() {
    // Compile proto files for gRPC server generation
    // streaming-service PROVIDES StreamingService (server implementation)
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(&["../protos/streaming.proto"], &["../protos/"])
        .expect("Failed to compile streaming.proto");
}
