fn main() {
    // Compile proto files for gRPC server generation
    // user-service PROVIDES UserService (server implementation)
    // Uses Phase 0 proto definitions from nova/backend/proto/services/
    //
    // NOTE: Inter-service communication (clients to other services) will be configured
    // in Phase 7A when all service proto files are available

    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(
            &["../proto/services/user_service.proto"],
            &["../proto/services/"],
        )
        .expect("Failed to compile user_service.proto");
}
