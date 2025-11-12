fn main() -> Result<(), Box<dyn std::error::Error>> {
    let services_dir = "../proto/services";

    for proto in [
        "user_service.proto",
        "auth_service.proto",
        "content_service.proto",
        "media_service.proto",
        "video_service.proto",
        "feed_service.proto",
        "common.proto",
    ] {
        println!("cargo:rerun-if-changed={}/{}", services_dir, proto);
    }

    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .compile_protos(
            &[
                format!("{services_dir}/user_service.proto"),
                format!("{services_dir}/auth_service.proto"),
                format!("{services_dir}/content_service.proto"),
                format!("{services_dir}/media_service.proto"),
                format!("{services_dir}/video_service.proto"),
                format!("{services_dir}/feed_service.proto"),
                format!("{services_dir}/common.proto"),
            ],
            &[services_dir],
        )?;

    Ok(())
}
