/// Shared application state threaded through the GTK4 UI via `glib::MainContext`.
///
/// Callers send async work to the Tokio runtime via `rt.spawn`; results are sent
/// back through `async_channel` and received on the GTK main thread via
/// `glib::spawn_future_local`, which runs on the main context and can safely
/// access GTK widgets (`!Send`).
use std::sync::{Arc, Mutex};
use tokio::runtime::Runtime;

use crate::client::proto::{
    ContainerActionRequest, CreateContainerRequest, DockerScope, IdRequest, NameRequest,
    NetworkContainerRequest, RenameRequest, SearchRequest, TagRequest,
};
use crate::client::DaemonClient;

/// Docker backend selected by the user. Keeping this as plain data makes it
/// safe to capture in Tokio tasks; GTK objects must remain on the GLib thread.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DockerTarget {
    pub profile: String,
    pub host: String,
    pub wsl2: bool,
}

impl DockerTarget {
    pub fn local(profile: impl Into<String>) -> Self {
        Self {
            profile: profile.into(),
            host: String::new(),
            wsl2: false,
        }
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.profile.trim().is_empty() {
            return Err("profile must not be empty".to_owned());
        }
        if self.wsl2 && !self.host.is_empty() {
            return Err("remote SSH host and WSL2 cannot be selected together".to_owned());
        }
        #[cfg(not(target_os = "windows"))]
        if self.wsl2 {
            return Err("WSL2 provider is only available on Windows".to_owned());
        }
        Ok(())
    }

    pub fn scope(&self, all: bool) -> DockerScope {
        DockerScope {
            profile: self.profile.clone(),
            all,
            host: self.host.clone(),
            wsl2: self.wsl2,
        }
    }

    pub fn id_request(&self, id: impl Into<String>) -> IdRequest {
        IdRequest {
            id: id.into(),
            profile: self.profile.clone(),
            host: self.host.clone(),
            wsl2: self.wsl2,
        }
    }

    pub fn name_request(&self, name: impl Into<String>) -> NameRequest {
        NameRequest {
            name: name.into(),
            profile: self.profile.clone(),
            host: self.host.clone(),
            wsl2: self.wsl2,
        }
    }

    pub fn container_action(
        &self,
        id: impl Into<String>,
        action: impl Into<String>,
    ) -> ContainerActionRequest {
        ContainerActionRequest {
            id: id.into(),
            action: action.into(),
            profile: self.profile.clone(),
            host: self.host.clone(),
            wsl2: self.wsl2,
        }
    }

    pub fn create_container(
        &self,
        name: impl Into<String>,
        image: impl Into<String>,
    ) -> CreateContainerRequest {
        CreateContainerRequest {
            name: name.into(),
            image: image.into(),
            profile: self.profile.clone(),
            host: self.host.clone(),
            wsl2: self.wsl2,
        }
    }

    pub fn rename_request(
        &self,
        id: impl Into<String>,
        new_name: impl Into<String>,
    ) -> RenameRequest {
        RenameRequest {
            id: id.into(),
            new_name: new_name.into(),
            profile: self.profile.clone(),
            host: self.host.clone(),
            wsl2: self.wsl2,
        }
    }

    pub fn tag_request(
        &self,
        name: impl Into<String>,
        repo: impl Into<String>,
        tag: impl Into<String>,
    ) -> TagRequest {
        TagRequest {
            name: name.into(),
            repo: repo.into(),
            tag: tag.into(),
            profile: self.profile.clone(),
            host: self.host.clone(),
            wsl2: self.wsl2,
        }
    }

    pub fn search_request(&self, term: impl Into<String>) -> SearchRequest {
        SearchRequest {
            term: term.into(),
            profile: self.profile.clone(),
            host: self.host.clone(),
            wsl2: self.wsl2,
        }
    }

    pub fn network_request(
        &self,
        network_id: impl Into<String>,
        container_id: impl Into<String>,
    ) -> NetworkContainerRequest {
        NetworkContainerRequest {
            network_id: network_id.into(),
            container_id: container_id.into(),
            profile: self.profile.clone(),
            host: self.host.clone(),
            wsl2: self.wsl2,
        }
    }
}

/// Current connection status to the daemon.
#[derive(Debug, Clone, PartialEq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Error(String),
}

/// App-wide state shared between views (wrapped in Arc<Mutex>).
pub struct AppState {
    pub connection: ConnectionState,
    pub daemon: Option<DaemonClient>,
    pub active_profile: String,
    pub docker_host: String,
    pub docker_wsl2: bool,
    pub socket_path: String,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            connection: ConnectionState::Disconnected,
            daemon: None,
            active_profile: "default".to_owned(),
            docker_host: String::new(),
            docker_wsl2: false,
            socket_path: "/tmp/colima-desktop.sock".to_owned(),
        }
    }
}

/// Handle that views hold: a shared state + a Tokio runtime for async calls.
#[derive(Clone)]
pub struct AppHandle {
    pub state: Arc<Mutex<AppState>>,
    pub rt: Arc<Runtime>,
}

impl AppHandle {
    pub fn new_with_target(socket_path: impl Into<String>, target: DockerTarget) -> Self {
        target.validate().expect("valid Docker target");
        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .build()
            .expect("tokio runtime");
        let state = AppState {
            socket_path: socket_path.into(),
            active_profile: target.profile,
            docker_host: target.host,
            docker_wsl2: target.wsl2,
            ..AppState::default()
        };
        Self {
            state: Arc::new(Mutex::new(state)),
            rt: Arc::new(rt),
        }
    }

    /// Attempt to (re)connect to the daemon on the configured socket.
    pub fn connect_daemon(&self) {
        let handle = self.clone();
        {
            let mut st = handle.state.lock().unwrap();
            st.connection = ConnectionState::Connecting;
        }
        let endpoint = {
            let st = handle.state.lock().unwrap();
            daemon_endpoint(&st.socket_path)
        };
        handle.rt.spawn(async move {
            match DaemonClient::connect(endpoint).await {
                Ok(client) => {
                    let mut st = handle.state.lock().unwrap();
                    st.daemon = Some(client);
                    st.connection = ConnectionState::Connected;
                }
                Err(e) => {
                    let mut st = handle.state.lock().unwrap();
                    st.connection = ConnectionState::Error(e.to_string());
                }
            }
        });
    }

    /// Active colima profile name.
    pub fn profile(&self) -> String {
        self.state.lock().unwrap().active_profile.clone()
    }

    /// Atomically switch the profile used by every Colima and Docker request.
    pub fn select_profile(&self, profile: impl Into<String>) -> Result<(), String> {
        let profile = profile.into();
        if profile.trim().is_empty() {
            return Err("profile must not be empty".to_owned());
        }
        self.state.lock().unwrap().active_profile = profile;
        Ok(())
    }

    /// Snapshot the provider target once before spawning async work.
    pub fn docker_target(&self) -> DockerTarget {
        let state = self.state.lock().unwrap();
        DockerTarget {
            profile: state.active_profile.clone(),
            host: state.docker_host.clone(),
            wsl2: state.docker_wsl2,
        }
    }
}

fn daemon_endpoint(configured: &str) -> String {
    if configured.starts_with("unix://")
        || configured.starts_with("http://")
        || configured.starts_with("https://")
    {
        configured.to_owned()
    } else {
        format!("unix://{configured}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn target_rejects_empty_and_conflicting_providers() {
        assert!(DockerTarget::local("").validate().is_err());
        assert!(DockerTarget {
            profile: "e2e".into(),
            host: "user@example".into(),
            wsl2: true,
        }
        .validate()
        .is_err());
    }

    #[test]
    fn selecting_profile_updates_colima_and_docker_scope_atomically() {
        let handle = AppHandle::new_with_target(
            "/tmp/test.sock",
            DockerTarget {
                profile: "first".into(),
                host: "user@example".into(),
                wsl2: false,
            },
        );
        handle.select_profile("second").unwrap();
        assert_eq!(handle.profile(), "second");
        assert_eq!(
            handle.docker_target(),
            DockerTarget {
                profile: "second".into(),
                host: "user@example".into(),
                wsl2: false,
            }
        );
    }

    #[test]
    fn request_builders_propagate_the_complete_provider_scope() {
        let target = DockerTarget {
            profile: "remote-profile".into(),
            host: "dev@example".into(),
            wsl2: false,
        };
        let scope = target.scope(true);
        assert_eq!(scope.profile, "remote-profile");
        assert_eq!(scope.host, "dev@example");
        assert!(scope.all);
        let id = target.id_request("container-id");
        assert_eq!(id.id, "container-id");
        assert_eq!(id.host, "dev@example");
        let create = target.create_container("name", "alpine:latest");
        assert_eq!(create.profile, "remote-profile");
        assert_eq!(create.host, "dev@example");
        let rename = target.rename_request("id", "new-name");
        assert_eq!(rename.host, "dev@example");
        let tag = target.tag_request("image", "repo", "latest");
        assert_eq!(tag.profile, "remote-profile");
        assert_eq!(tag.host, "dev@example");
        let search = target.search_request("alpine");
        assert_eq!(search.host, "dev@example");
        let network = target.network_request("network", "container");
        assert_eq!(network.host, "dev@example");
    }

    #[test]
    fn daemon_endpoint_preserves_tcp_and_normalizes_socket_paths() {
        assert_eq!(
            daemon_endpoint("http://127.0.0.1:50051"),
            "http://127.0.0.1:50051"
        );
        assert_eq!(
            daemon_endpoint("/tmp/colima.sock"),
            "unix:///tmp/colima.sock"
        );
        assert_eq!(
            daemon_endpoint("unix:///run/user/1000/colima.sock"),
            "unix:///run/user/1000/colima.sock"
        );
    }

    #[test]
    fn daemon_endpoint_preserves_an_https_scheme() {
        // A TLS loopback endpoint must be passed through untouched, never
        // rewritten to a `unix://` socket path.
        assert_eq!(
            daemon_endpoint("https://127.0.0.1:50051"),
            "https://127.0.0.1:50051"
        );
    }

    #[test]
    fn local_target_defaults_to_a_scoped_profile_with_no_remote_provider() {
        // The default target the GTK app launches with must carry the profile,
        // no SSH host, and no WSL2, and must validate on any platform.
        let target = DockerTarget::local("desktop-e2e");
        assert_eq!(target.profile, "desktop-e2e");
        assert!(target.host.is_empty());
        assert!(!target.wsl2);
        assert!(target.validate().is_ok());
    }

    #[test]
    fn scope_carries_the_all_flag_and_the_full_provider_scope() {
        // Docker list/prune callbacks build their request via `scope`; the v1.1
        // provider fields (profile/host/wsl2) and the `all` bit must all travel.
        let target = DockerTarget {
            profile: "e2e".into(),
            host: "dev@example".into(),
            wsl2: false,
        };
        let scoped = target.scope(true);
        assert_eq!(scoped.profile, "e2e");
        assert_eq!(scoped.host, "dev@example");
        assert!(!scoped.wsl2);
        assert!(scoped.all);
        // The same builder with `all=false` flips only the `all` bit.
        assert!(!target.scope(false).all);
    }

    #[test]
    fn every_docker_request_builder_propagates_the_wsl2_scope_field() {
        // Complements `request_builders_propagate_the_complete_provider_scope`
        // (which pins host propagation): here the v1.1 `wsl2` field must ride on
        // every Docker request builder so a WSL2-scoped call is never silently
        // downgraded to a local one.
        let target = DockerTarget {
            profile: "wsl-profile".into(),
            host: String::new(),
            wsl2: true,
        };
        assert!(target.scope(false).wsl2);
        assert!(target.id_request("id").wsl2);
        assert!(target.name_request("name").wsl2);
        assert!(target.container_action("id", "stop").wsl2);
        assert!(target.create_container("name", "alpine").wsl2);
        assert!(target.rename_request("id", "new").wsl2);
        assert!(target.tag_request("img", "repo", "tag").wsl2);
        assert!(target.search_request("term").wsl2);
        assert!(target.network_request("net", "ctr").wsl2);
    }

    #[test]
    fn validate_enforces_that_wsl2_is_windows_only() {
        // WSL2 is a Windows-only provider; on every other platform a WSL2 target
        // must be rejected rather than silently connecting to a local socket.
        let wsl2_only = DockerTarget {
            profile: "e2e".into(),
            host: String::new(),
            wsl2: true,
        };
        #[cfg(target_os = "windows")]
        assert!(wsl2_only.validate().is_ok());
        #[cfg(not(target_os = "windows"))]
        assert!(wsl2_only.validate().is_err());
    }

    #[test]
    fn selecting_a_blank_profile_is_rejected_and_leaves_the_active_profile_unchanged() {
        let handle =
            AppHandle::new_with_target("/tmp/test.sock", DockerTarget::local("desktop-e2e"));
        assert!(handle.select_profile("   ").is_err());
        // The rejected switch must not mutate the active profile.
        assert_eq!(handle.profile(), "desktop-e2e");
    }
}
