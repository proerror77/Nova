fn main() {
    // Compile proto files for gRPC
    // Phase 1: Spec 007 - Users Consolidation
    // messaging-service now acts as AUTH-SERVICE CLIENT to query users via gRPC
    // instead of directly querying the shadow users table

    println!("cargo:rerun-if-changed=../proto/services/messaging_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/auth_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/common.proto");

    // CRITICAL: Must compile all protos in a SINGLE call to share common.proto module
    // If split into separate compile() calls, each generates isolated module trees
    // and common::v1::ErrorStatus won't be accessible across them
    tonic_build::configure()
        .build_server(true) // MessagingService server
        .build_client(true) // AuthService client
        .compile_protos(
            &[
                "../proto/services/messaging_service.proto",
                "../proto/services/auth_service.proto",
                "../proto/services/common.proto",
            ],
            &["../proto/services/"],
        )
        .expect("Failed to compile proto files");
}
