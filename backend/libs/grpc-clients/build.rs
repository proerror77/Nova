fn main() {
    // Compile all proto files for client generation
    // This centralizes client code generation for all services

    let services = vec![
        ("auth_service", "../../../proto/services/auth_service.proto"),
        ("user_service", "../../../proto/services/user_service.proto"),
        ("messaging_service", "../../../proto/services/messaging_service.proto"),
        ("content_service", "../../../proto/services/content_service.proto"),
        ("feed_service", "../../../proto/services/feed_service.proto"),
        ("search_service", "../../../proto/services/search_service.proto"),
        ("media_service", "../../../proto/services/media_service.proto"),
        ("notification_service", "../../../proto/services/notification_service.proto"),
        ("streaming_service", "../../../proto/services/streaming_service.proto"),
        ("cdn_service", "../../../proto/services/cdn_service.proto"),
        ("events_service", "../../../proto/services/events_service.proto"),
        ("video_service", "../../../proto/services/video_service.proto"),
    ];

    for (service_name, proto_path) in services {
        tonic_build::configure()
            .build_server(false)  // This is a client library, not a server
            .build_client(true)   // Generate client code
            .compile(&[proto_path], &["../../../proto/services/"])
            .unwrap_or_else(|e| panic!("Failed to compile {}: {}", service_name, e));
    }

    println!("cargo:rerun-if-changed=../../../proto/services/");
    println!("cargo:rerun-if-changed=../../../proto/services/common.proto");
}
