fn main() {
    // Compile proto files for gRPC
    // Phase 1: Spec 007 - Users Consolidation
    // messaging-service now acts as AUTH-SERVICE CLIENT to query users via gRPC
    // instead of directly querying the shadow users table

    // Build server for MessagingService (this service provides)
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(
            &["../proto/services/messaging_service.proto"],
            &["../proto/services/"],
        )
        .expect("Failed to compile messaging_service.proto");

    // Build client for AuthService (to call into auth-service)
    tonic_build::configure()
        .build_server(false)
        .build_client(true)
        .compile(
            &["../proto/services/auth_service.proto"],
            &["../proto/services/"],
        )
        .expect("Failed to compile auth_service.proto");
}
