// Build scripts are allowed to panic on compilation errors
// Root workspace Cargo.toml updated: services + config dependency
#![allow(clippy::panic)]

use std::path::PathBuf;

fn main() {
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR not set"));

    // Compile main service protos (v1 services from services/ directory)
    // NOTE: search_service.proto is compiled separately below to use the correct version
    tonic_build::configure()
        .build_server(false)
        .build_client(true)
        .file_descriptor_set_path(out_dir.join("nova_descriptor.bin"))
        .type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]")
        .type_attribute(".", "#[allow(clippy::enum_variant_names)]")
        .compile_well_known_types(true)
        .extern_path(".google.protobuf", "::pbjson_types")
        .compile_protos(
            &[
                "../proto/services/common.proto",
                "../proto/services/auth_service.proto",
                "../proto/services_v2/identity_service.proto",
                // user_service.proto removed - service is deprecated
                "../proto/services_v2/content_service.proto",
                "../proto/services/feed_service.proto",
                "../proto/services_v2/social_service.proto",
                // search_service.proto compiled separately - see below
                "../proto/services_v2/media_service.proto",
                "../proto/services/notification_service.proto",
                "../proto/services/graph_service.proto",
            ],
            // Put services_v2 before services to prefer v2 definitions when filenames overlap
            // Include third_party for google/api/annotations.proto
            &[
                "../proto/services_v2/",
                "../proto/services/",
                "../proto/third_party/",
            ],
        )
        .expect("Failed to compile main service protos");

    // Compile search-service proto separately to match the deployed search-service
    // search-service uses proto/services/search_service.proto (nova.search_service.v2)
    // NOT proto/services_v2/search_service.proto (nova.search.v1)
    tonic_build::configure()
        .build_server(false)
        .build_client(true)
        .type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]")
        .type_attribute(".", "#[allow(clippy::enum_variant_names)]")
        .compile_protos(
            &["../proto/services/search_service.proto"],
            &["../proto/services/", "../proto/third_party/"],
        )
        .expect("Failed to compile search-service proto");

    // Compile realtime-chat service proto separately
    tonic_build::configure()
        .build_server(false)
        .build_client(true)
        .type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]")
        .type_attribute(".", "#[allow(clippy::enum_variant_names)]")
        .compile_protos(
            &["../realtime-chat-service/proto/realtime_chat.proto"],
            &["../realtime-chat-service/proto/"],
        )
        .expect("Failed to compile realtime-chat proto");
}
