fn main() -> Result<(), Box<dyn std::error::Error>> {
    let services_dir = "../proto/services";

    {
        let proto = "search_service.proto";
        println!("cargo:rerun-if-changed={}/{}", services_dir, proto);
    }
    println!("cargo:rerun-if-changed=../proto/third_party/google/api/annotations.proto");
    println!("cargo:rerun-if-changed=../proto/third_party/google/api/http.proto");

    tonic_build::configure()
        .compile_well_known_types(true)
        .compile_protos(
            &[format!("{services_dir}/search_service.proto")],
            &[services_dir, "../proto/third_party"],
        )?;

    Ok(())
}
