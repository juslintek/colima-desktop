fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Compile proto/colima_ui.proto → Rust gRPC client stubs (ColimaService + DockerService).
    // build_server(false) — we are a client only.
    tonic_build::configure()
        .build_server(false)
        .compile(&["proto/colima_ui.proto"], &["proto"])?;
    Ok(())
}
