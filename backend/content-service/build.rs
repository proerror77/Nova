fn main() {
    // Compile proto files using tonic-build
    // This generates both the message types and the gRPC service traits
    tonic_build::compile_protos("../protos/content_service.proto")
        .expect("Failed to compile content_service.proto");
}
