fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("cargo:rerun-if-changed=../proto/third_party/google/api/annotations.proto");
    println!("cargo:rerun-if-changed=../proto/third_party/google/api/http.proto");

    // Compile protobuf files
    tonic_build::configure()
        .compile_well_known_types(true)
        .build_server(true)
        .build_client(false)
        .compile_protos(
            &["../proto/services/notification_service.proto"],
            &["../proto/services", "../proto", "../proto/third_party"],
        )?;

    Ok(())
}
