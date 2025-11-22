fn main() -> Result<(), Box<dyn std::error::Error>> {
    // content-service now consumes proto definitions from grpc-clients.
    // We keep build.rs minimal to avoid duplicate generation and shadowing issues.
    println!("cargo:warning=content-service uses grpc-clients generated protos; no local generation performed");
    Ok(())
}
