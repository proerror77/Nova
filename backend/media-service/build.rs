fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Use services_v2 proto for unified media API (matches graphql-gateway)
    let services_v2_dir = "../proto/services_v2";
    let common_dir = "../proto";
    let third_party_dir = "../proto/third_party";

    for proto in ["media_service.proto"] {
        println!("cargo:rerun-if-changed={}/{}", services_v2_dir, proto);
    }

    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile_protos(
            &[format!("{services_v2_dir}/media_service.proto")],
            &[services_v2_dir, common_dir, third_party_dir],
        )?;

    Ok(())
}
