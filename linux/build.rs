fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Compiles proto/colima_ui.proto into a Rust gRPC client (ColimaService + DockerService).
    tonic_build::configure()
        .build_server(false)
        .compile(&["proto/colima_ui.proto"], &["proto"])?;
    Ok(())
}
