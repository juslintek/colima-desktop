// tonic gRPC client wrapper for the colima-desktop daemon.
pub mod colimaui {
    tonic::include_proto!("colimaui");
}
use colimaui::colima_service_client::ColimaServiceClient;
use colimaui::docker_service_client::DockerServiceClient;
use colimaui::{DockerScope, Empty, StatusRequest};

pub struct Daemon {
    pub colima: ColimaServiceClient<tonic::transport::Channel>,
    pub docker: DockerServiceClient<tonic::transport::Channel>,
}

impl Daemon {
    /// Connect to the daemon over its TCP endpoint (local colima).
    pub async fn connect(addr: String) -> Result<Self, tonic::transport::Error> {
        let ch = tonic::transport::Channel::from_shared(addr)
            .unwrap()
            .connect()
            .await?;
        Ok(Self {
            colima: ColimaServiceClient::new(ch.clone()),
            docker: DockerServiceClient::new(ch),
        })
    }

    pub async fn status(&mut self, profile: &str) -> Result<colimaui::VmStatus, tonic::Status> {
        Ok(self
            .colima
            .status(StatusRequest { profile: profile.into(), extended: false })
            .await?
            .into_inner())
    }

    pub async fn containers(&mut self, profile: &str) -> Result<String, tonic::Status> {
        let r = self
            .docker
            .list_containers(DockerScope { profile: profile.into(), all: true, host: String::new(), wsl2: false })
            .await?
            .into_inner();
        Ok(r.json)
    }
}
