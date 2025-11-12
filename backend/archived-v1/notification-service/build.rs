fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Compile protobuf files
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .compile_protos(
            &["../proto/services/notification_service.proto"],
            &["../proto/services", "../proto"],
        )?;

    Ok(())
}
