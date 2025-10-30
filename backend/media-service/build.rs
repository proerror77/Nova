fn main() {
    // Compile proto files using tonic-build
    // This generates both the message types and the gRPC service traits
    tonic_build::compile_protos("../protos/media_service.proto")
        .expect("Failed to compile media_service.proto");
}
