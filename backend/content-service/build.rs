fn main() -> Result<(), Box<dyn std::error::Error>> {
    let services_dir = "../proto/services";

    for proto in ["content_service.proto", "common.proto"] {
        println!("cargo:rerun-if-changed={}/{}", services_dir, proto);
    }

    tonic_build::configure().compile_protos(
        &[
            format!("{services_dir}/content_service.proto"),
            format!("{services_dir}/common.proto"),
        ],
        &[services_dir],
    )?;

    Ok(())
}
