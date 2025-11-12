fn main() -> Result<(), Box<dyn std::error::Error>> {
    let services_dir = "../proto/services";

    {
        let proto = "search_service.proto";
        println!("cargo:rerun-if-changed={}/{}", services_dir, proto);
    }

    tonic_build::configure().compile_protos(
        &[format!("{services_dir}/search_service.proto")],
        &[services_dir],
    )?;

    Ok(())
}
