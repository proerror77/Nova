fn main() {
    println!("cargo:rerun-if-changed=../proto/services/auth_service.proto");
    println!("cargo:rerun-if-changed=../proto/services/common.proto");

    // Compile proto files for identity-service gRPC server
    // identity-service PROVIDES AuthService (server implementation)
    // Replaces archived auth-service as part of Phase G consolidation
    // Client code is also generated for integration tests
    tonic_build::configure()
        .build_server(true)
        .build_client(true) // Enable client code generation for integration tests
        .compile_protos(
            &["../proto/services/auth_service.proto"],
            &["../proto/services/"],
        )
        .expect("Failed to compile auth_service.proto for identity-service");
}
