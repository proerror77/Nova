fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Compile proto files
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile(
            &[
                "../proto/services/events_service.proto",
                "../proto/services/common.proto",
            ],
            &["../proto/services"],
        )?;
    Ok(())
}
