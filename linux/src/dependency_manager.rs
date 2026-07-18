/// DependencyManager — detects and installs colima + its dependencies on Linux.
///
/// CONTRACT Part C:
///   - isColimaInstalled() → Bool
///   - installColima()       (apt / dnf / pacman / direct download)
///   - DependencyManager: track + update colima/lima/qemu/docker-cli/kubectl
use std::path::PathBuf;
use std::process::Command;

/// A named dependency with its detection command and install recipe.
#[derive(Debug, Clone)]
pub struct Dep {
    pub name: &'static str,
    /// Binary to probe with `which`
    pub binary: &'static str,
    /// Human-readable install hint shown in the UI
    pub install_hint: &'static str,
}

/// Every dependency tracked by DependencyManager (CONTRACT Part C, Linux set).
pub const DEPS: &[Dep] = &[
    Dep {
        name: "colima",
        binary: "colima",
        install_hint: "brew install colima  OR  download from github.com/abiosoft/colima/releases",
    },
    Dep {
        name: "lima",
        binary: "limactl",
        install_hint: "brew install lima  OR  install via Homebrew",
    },
    Dep {
        name: "qemu",
        binary: "qemu-system-aarch64",
        install_hint: "sudo apt-get install qemu-system  OR  brew install qemu",
    },
    Dep {
        name: "docker-cli",
        binary: "docker",
        install_hint: "sudo apt-get install docker-ce-cli  OR  brew install docker",
    },
    Dep {
        name: "kubectl",
        binary: "kubectl",
        install_hint: "sudo apt-get install kubectl  OR  brew install kubectl",
    },
];

/// Result for a single dependency check.
#[derive(Debug, Clone)]
pub struct DepStatus {
    pub dep: &'static str,
    pub installed: bool,
    pub path: Option<PathBuf>,
    pub version: Option<String>,
}

pub struct DependencyManager;

impl DependencyManager {
    /// Check whether colima binary is on PATH.
    pub fn is_colima_installed() -> bool {
        which::which("colima").is_ok()
    }

    /// Probe all tracked dependencies; returns a list of statuses.
    pub fn check_all() -> Vec<DepStatus> {
        DEPS.iter()
            .map(|dep| {
                let path = which::which(dep.binary).ok();
                let installed = path.is_some();
                let version = if installed {
                    Self::probe_version(dep.binary)
                } else {
                    None
                };
                DepStatus {
                    dep: dep.name,
                    installed,
                    path,
                    version,
                }
            })
            .collect()
    }

    /// Attempt to install colima using the best available package manager.
    ///
    /// Precedence: brew → apt-get → dnf → pacman → snap → direct download hint.
    /// Returns (success, log_output).
    pub fn install_colima() -> (bool, String) {
        // 1. Homebrew — most reliable, version-tracked
        if which::which("brew").is_ok() {
            return run_install("brew", &["install", "colima"]);
        }
        // 2. apt-get — Debian/Ubuntu (colima is in official repos ≥ Ubuntu 23.04)
        if which::which("apt-get").is_ok() {
            let (ok, log) = run_install("sudo", &["apt-get", "install", "-y", "colima"]);
            if ok {
                return (true, log);
            }
            // Fall through to direct download hint
        }
        // 3. dnf — Fedora/RHEL
        if which::which("dnf").is_ok() {
            let (ok, log) = run_install("sudo", &["dnf", "install", "-y", "colima"]);
            if ok {
                return (true, log);
            }
        }
        // 4. pacman — Arch
        if which::which("pacman").is_ok() {
            let (ok, log) = run_install("sudo", &["pacman", "-S", "--noconfirm", "colima"]);
            if ok {
                return (true, log);
            }
        }
        // 5. snap
        if which::which("snap").is_ok() {
            let (ok, log) = run_install("sudo", &["snap", "install", "colima"]);
            if ok {
                return (true, log);
            }
        }
        // 6. Provide download hint
        (
            false,
            "No supported package manager found.\n\
             Download colima from: https://github.com/abiosoft/colima/releases\n\
             Then place the binary in ~/.local/bin or /usr/local/bin and ensure that\n\
             directory is on your PATH."
                .to_owned(),
        )
    }

    /// Install a specific dependency by name (from DEPS).
    pub fn install_dep(name: &str) -> (bool, String) {
        if let Some(dep) = DEPS.iter().find(|d| d.name == name) {
            // Use brew if available — works on all Linux distros with Linuxbrew
            if which::which("brew").is_ok() {
                return run_install("brew", &["install", dep.binary]);
            }
            // Fall back: show the install hint as log output
            return (false, dep.install_hint.to_owned());
        }
        (false, format!("Unknown dependency: {name}"))
    }

    /// Attempt to update all installed dependencies.
    pub fn update_all() -> Vec<(String, bool, String)> {
        DEPS.iter()
            .filter_map(|dep| {
                if which::which(dep.binary).is_ok() {
                    let (ok, log) = Self::update_one(dep.name);
                    Some((dep.name.to_owned(), ok, log))
                } else {
                    None
                }
            })
            .collect()
    }

    fn update_one(name: &str) -> (bool, String) {
        if which::which("brew").is_ok() {
            return run_install("brew", &["upgrade", name]);
        }
        if which::which("apt-get").is_ok() {
            return run_install(
                "sudo",
                &["apt-get", "install", "--only-upgrade", "-y", name],
            );
        }
        (false, format!("No supported updater for {name}"))
    }

    fn probe_version(binary: &str) -> Option<String> {
        let out = Command::new(binary).arg("--version").output().ok()?;
        let raw = String::from_utf8_lossy(&out.stdout);
        Some(raw.lines().next().unwrap_or("").trim().to_owned())
    }
}

fn run_install(cmd: &str, args: &[&str]) -> (bool, String) {
    match Command::new(cmd).args(args).output() {
        Ok(out) => {
            let log = format!(
                "{}\n{}",
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );
            (out.status.success(), log)
        }
        Err(e) => (false, format!("Failed to spawn {cmd}: {e}")),
    }
}
