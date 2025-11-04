fn main() {
    // Compile proto files for gRPC server generation
    // messaging-service PROVIDES MessagingService (server implementation)
    // Uses Phase 0 proto definitions from nova/backend/proto/services/
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(
            &["../proto/services/messaging_service.proto"],
            &["../proto/services/"],
        )
        .expect("Failed to compile messaging_service.proto");
}
