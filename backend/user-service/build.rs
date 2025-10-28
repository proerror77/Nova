fn main() {
    // Compile proto files using tonic-build for gRPC client generation
    tonic_build::compile_protos("../protos/content_service.proto")
        .expect("Failed to compile content_service.proto");

    tonic_build::compile_protos("../protos/media_service.proto")
        .expect("Failed to compile media_service.proto");
}
