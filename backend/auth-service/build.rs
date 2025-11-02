fn main() {
    // Compile proto files for gRPC server generation
    // auth-service PROVIDES AuthService (server implementation)
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(&["../protos/auth.proto"], &["../protos/"])
        .expect("Failed to compile auth.proto");
}
