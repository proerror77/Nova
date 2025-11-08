fn main() -> Result<(), Box<dyn std::error::Error>> {
    let services_dir = "../proto/services";
    let proto_file = "search_service.proto";

    println!("cargo:rerun-if-changed={}/{}", services_dir, proto_file);

    tonic_build::configure().compile(
        &[format!("{services_dir}/{}", proto_file)],
        &[services_dir],
    )?;

    Ok(())
}
