fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Compile proto/colima_ui.proto → Rust gRPC client stubs (ColimaService + DockerService).
    // build_server(false) — we are a client only.
    tonic_prost_build::configure()
        .build_server(false)
        .compile_protos(&["proto/colima_ui.proto"], &["proto"])?;
    Ok(())
}
