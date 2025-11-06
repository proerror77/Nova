fn main() {
    // Compile all proto files for client generation
    // This centralizes client code generation for all services

    let base = "../../proto/services";
    let services = vec![
        ("auth_service", format!("{}/auth_service.proto", base)),
        ("user_service", format!("{}/user_service.proto", base)),
        (
            "messaging_service",
            format!("{}/messaging_service.proto", base),
        ),
        ("content_service", format!("{}/content_service.proto", base)),
        ("feed_service", format!("{}/feed_service.proto", base)),
        ("search_service", format!("{}/search_service.proto", base)),
        ("media_service", format!("{}/media_service.proto", base)),
        (
            "notification_service",
            format!("{}/notification_service.proto", base),
        ),
        (
            "streaming_service",
            format!("{}/streaming_service.proto", base),
        ),
        ("cdn_service", format!("{}/cdn_service.proto", base)),
        ("events_service", format!("{}/events_service.proto", base)),
        ("video_service", format!("{}/video_service.proto", base)),
    ];

    for (service_name, proto_path) in services {
        tonic_build::configure()
            .build_server(false) // This is a client library, not a server
            .build_client(true) // Generate client code
            .compile(&[proto_path.as_str()], &[base])
            .unwrap_or_else(|e| panic!("Failed to compile {}: {}", service_name, e));
    }

    println!("cargo:rerun-if-changed=../../proto/services/");
    println!("cargo:rerun-if-changed=../../proto/services/common.proto");
}
