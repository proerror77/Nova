// Build scripts are allowed to panic on compilation errors
#![allow(clippy::panic)]

fn main() {
    // Compile all proto files for client generation
    // This centralizes client code generation for all services

    let base = "../../proto/services";
    let third_party = "../../proto/third_party";
    let services = vec![
        ("auth_service", format!("{}/auth_service.proto", base)),
        ("user_service", format!("{}/user_service.proto", base)),
        ("feed_service", format!("{}/feed_service.proto", base)),
        ("search_service", format!("{}/search_service.proto", base)),
        ("media_service", format!("{}/media_service.proto", base)),
        (
            "notification_service",
            format!("{}/notification_service.proto", base),
        ),
        ("events_service", format!("{}/events_service.proto", base)),
        ("graph_service", format!("{}/graph_service.proto", base)),
    ];

    for (service_name, proto_path) in services {
        tonic_build::configure()
            .build_server(false) // This is a client library, not a server
            .build_client(true) // Generate client code
            .compile_protos(&[proto_path.as_str()], &[base, third_party])
            .unwrap_or_else(|e| panic!("Failed to compile {}: {}", service_name, e));
    }

    // v2 content-service proto lives in services_v2
    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .compile_well_known_types(true)
        .extern_path(".google.protobuf", "::prost_types")
        .compile_protos(
            &["../../proto/services_v2/content_service.proto"],
            &["../../proto/services_v2", third_party],
        )
        .unwrap_or_else(|e| panic!("Failed to compile content_service v2: {}", e));

    // v2 media-service proto (package nova.media.v1)
    tonic_build::configure()
        .build_server(false)
        .build_client(true)
        .compile_well_known_types(false)
        .compile_protos(
            &["../../proto/services_v2/media_service.proto"],
            &["../../proto/services_v2", third_party],
        )
        .unwrap_or_else(|e| panic!("Failed to compile media_service v2: {}", e));

    // Compile social-service proto (from local proto directory)
    // Note: compile_well_known_types is needed for google.protobuf.Timestamp
    tonic_build::configure()
        .build_server(false)
        .build_client(true)
        .compile_well_known_types(true)
        .extern_path(".google.protobuf", "::prost_types")
        .compile_protos(&["proto/social.proto"], &["proto"])
        .unwrap_or_else(|e| panic!("Failed to compile social_service: {}", e));

    // Compile ranking-service proto (from local proto directory)
    tonic_build::configure()
        .build_server(false)
        .build_client(true)
        .compile_protos(&["proto/ranking.proto"], &["proto"])
        .unwrap_or_else(|e| panic!("Failed to compile ranking_service: {}", e));

    // Compile feature-store proto (from local proto directory)
    tonic_build::configure()
        .build_server(false)
        .build_client(true)
        .compile_protos(&["proto/feature_store.proto"], &["proto"])
        .unwrap_or_else(|e| panic!("Failed to compile feature_store: {}", e));

    // Compile trust-safety proto (from local proto directory)
    tonic_build::configure()
        .build_server(false)
        .build_client(true)
        .compile_protos(&["proto/trust_safety.proto"], &["proto"])
        .unwrap_or_else(|e| panic!("Failed to compile trust_safety: {}", e));

    println!("cargo:rerun-if-changed=../../proto/services/");
    println!("cargo:rerun-if-changed=../../proto/services/common.proto");
    println!("cargo:rerun-if-changed=../../proto/services_v2/");
    println!("cargo:rerun-if-changed=proto/social.proto");
    println!("cargo:rerun-if-changed=proto/ranking.proto");
    println!("cargo:rerun-if-changed=proto/feature_store.proto");
    println!("cargo:rerun-if-changed=proto/trust_safety.proto");
}
