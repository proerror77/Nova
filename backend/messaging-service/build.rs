fn main() {
    // Compile proto files
    tonic_build::compile_protos("../protos/messaging_service.proto")
        .expect("Failed to compile messaging_service proto");
}
