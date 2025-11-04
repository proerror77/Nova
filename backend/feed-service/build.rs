fn main() {
    // Compile proto files for gRPC server generation
    // recommendation-service PROVIDES RecommendationService (server implementation)
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(&["../protos/recommendation.proto"], &["../protos/"])
        .expect("Failed to compile recommendation.proto");
}
