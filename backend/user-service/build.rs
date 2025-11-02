fn main() {
    // Compile proto files using tonic-build for gRPC client generation
    tonic_build::configure()
        .build_client(true)
        .build_server(false)
        .compile(&["../protos/auth.proto"], &["../protos"])
        .expect("Failed to compile auth.proto");

    tonic_build::compile_protos("../protos/content_service.proto")
        .expect("Failed to compile content_service.proto");

    tonic_build::compile_protos("../protos/media_service.proto")
        .expect("Failed to compile media_service.proto");

    // Compile new service proto files for microservices architecture
    tonic_build::compile_protos("../protos/recommendation.proto")
        .expect("Failed to compile recommendation.proto");

    tonic_build::compile_protos("../protos/video.proto").expect("Failed to compile video.proto");

    tonic_build::compile_protos("../protos/streaming.proto")
        .expect("Failed to compile streaming.proto");
}
