fn main() {
    // Compile proto files for gRPC server generation
    // auth-service PROVIDES AuthService (server implementation)
    // Uses Phase 0 proto definitions from nova/backend/proto/services/
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(&["../proto/services/auth_service.proto"], &["../proto/services/"])
        .expect("Failed to compile auth_service.proto");
}
