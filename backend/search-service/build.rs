fn main() -> Result<(), Box<dyn std::error::Error>> {
    let services_dir = "../proto/services";

    for proto in ["search_service.proto"] {
        println!("cargo:rerun-if-changed={}/{}", services_dir, proto);
    }

    tonic_build::configure()
        .compile(
            &[format!("{services_dir}/search_service.proto")],
            &[services_dir],
        )?;

    Ok(())
}
