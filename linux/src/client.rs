// tonic gRPC client wrapper — ColimaService + DockerService.
//
// All methods return Results so callers can display errors in the UI.

pub mod proto {
    tonic::include_proto!("colimaui");
}

pub use proto::{
    colima_service_client::ColimaServiceClient,
    docker_service_client::DockerServiceClient,
    CloneProfileRequest, ContainerActionRequest, CreateContainerRequest,
    CreateProfileRequest, DeleteProfileRequest, DeleteRequest, DockerScope,
    Empty, IdRequest, KillProcessRequest, KubeExecRequest, ModelRequest,
    ModelRunRequest, ModelServeRequest, NameRequest, NetworkContainerRequest,
    PruneRequest, ProfileRequest, RenameRequest, RestartRequest, SearchRequest,
    SetConfigRequest, StartRequest, StatusRequest, StopRequest,
    SwitchRuntimeRequest, TagRequest,
};

use tonic::transport::Channel;

/// Shared connection to the colima-desktop daemon over a Unix socket or TCP.
#[derive(Clone)]
pub struct DaemonClient {
    pub colima: ColimaServiceClient<Channel>,
    pub docker: DockerServiceClient<Channel>,
}

impl DaemonClient {
    /// Connect via a `http://` or `unix:///` endpoint string.
    pub async fn connect(endpoint: impl Into<String>) -> Result<Self, tonic::transport::Error> {
        let ep = endpoint.into();
        let channel = if ep.starts_with("unix://") {
            // Unix domain socket (preferred on Linux)
            let path = ep.trim_start_matches("unix://").to_owned();
            tonic::transport::Endpoint::try_from("http://localhost")
                .expect("static endpoint is valid")
                .connect_with_connector(tower::service_fn(move |_| {
                    let p = path.clone();
                    async move {
                        let stream = tokio::net::UnixStream::connect(p).await?;
                        Ok::<_, std::io::Error>(hyper_util::rt::TokioIo::new(stream))
                    }
                }))
                .await?
        } else {
            Channel::from_shared(ep).unwrap().connect().await?
        };

        Ok(Self {
            colima: ColimaServiceClient::new(channel.clone()),
            docker: DockerServiceClient::new(channel),
        })
    }
}
