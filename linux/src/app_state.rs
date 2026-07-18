/// Shared application state threaded through the GTK4 UI via `glib::MainContext`.
///
/// Callers send async work to the Tokio runtime via `rt.spawn`; results are sent
/// back through `async_channel` and received on the GTK main thread via
/// `glib::spawn_future_local`, which runs on the main context and can safely
/// access GTK widgets (`!Send`).
use std::sync::{Arc, Mutex};
use tokio::runtime::Runtime;

use crate::client::DaemonClient;

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
    pub socket_path: String,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            connection: ConnectionState::Disconnected,
            daemon: None,
            active_profile: "default".to_owned(),
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
    pub fn new(socket_path: impl Into<String>) -> Self {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .enable_all()
            .build()
            .expect("tokio runtime");
        let mut state = AppState::default();
        state.socket_path = socket_path.into();
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
        let sock = {
            let st = handle.state.lock().unwrap();
            format!("unix://{}", st.socket_path)
        };
        handle.rt.spawn(async move {
            match DaemonClient::connect(sock).await {
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
}
