// Build script for identity-service
// Compiles auth_service.proto for gRPC server and client code generation
fn main() {
    println!("cargo:rerun-if-changed=../proto/services/auth_service.proto");
    println!("cargo:rerun-if-changed=../proto/third_party/google/api/annotations.proto");
    println!("cargo:rerun-if-changed=../proto/third_party/google/api/http.proto");
    println!("cargo:rerun-if-changed=../proto/third_party/google/protobuf/timestamp.proto");
    println!("cargo:rerun-if-changed=../proto/third_party/google/protobuf/empty.proto");

    // Compile proto files for identity-service gRPC server
    // identity-service PROVIDES AuthService (server implementation)
    // Includes authentication, authorization, account management, and invitations
    // Client code is also generated for integration tests
    tonic_build::configure()
        .compile_well_known_types(false)
        .extern_path(".google.protobuf.Timestamp", "::prost_types::Timestamp")
        .build_server(true)
        .build_client(true) // Enable client code generation for integration tests
        .compile_protos(
            &["../proto/services/auth_service.proto"],
            &["../proto/services", "../proto/third_party"],
        )
        .expect("Failed to compile auth_service.proto for identity-service");
}
