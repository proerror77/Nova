fn main() {
    // Compile proto files for gRPC server generation
    // user-service PROVIDES UserService (server implementation)
    // Uses Phase 0 proto definitions from nova/backend/proto/services/
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(&["../proto/services/user_service.proto"], &["../proto/services/"])
        .expect("Failed to compile user_service.proto");
}
