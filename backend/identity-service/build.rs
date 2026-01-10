fn main() {
    println!("cargo:rerun-if-changed=../proto/services_v2/identity_service.proto");
    println!("cargo:rerun-if-changed=../proto/third_party/google/api/annotations.proto");
    println!("cargo:rerun-if-changed=../proto/third_party/google/api/http.proto");
    println!("cargo:rerun-if-changed=../proto/third_party/google/protobuf/timestamp.proto");
    println!("cargo:rerun-if-changed=../proto/third_party/google/protobuf/empty.proto");

    // Compile proto files for identity-service gRPC server
    // identity-service PROVIDES IdentityService (server implementation)
    // Includes authentication, authorization, account management, and alias accounts
    // Client code is also generated for integration tests
    tonic_build::configure()
        .compile_well_known_types(false)
        .extern_path(".google.protobuf.Timestamp", "::prost_types::Timestamp")
        .build_server(true)
        .build_client(true) // Enable client code generation for integration tests
        .compile_protos(
            &["../proto/services_v2/identity_service.proto"],
            &["../proto/services_v2", "../proto/third_party"],
        )
        .expect("Failed to compile identity_service.proto for identity-service");
}
