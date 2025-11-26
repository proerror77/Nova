fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile_well_known_types(true)
        .type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]")
        .extern_path(".google.protobuf", "::pbjson_types")
        .compile_protos(
            &["../proto/services_v2/social_service.proto"],
            &[
                "../proto/services_v2",
                "../proto/services",
                "../proto/third_party",
            ],
        )?;
    Ok(())
}
