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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PackageManager {
    Brew,
    Apt,
    Dnf,
    Pacman,
    Snap,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum PackageAction {
    Install,
    Update,
}

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
        if let Some(manager) = detect_package_manager() {
            return run_package_action(manager, PackageAction::Install, "colima");
        }
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
            if let Some(manager) = detect_package_manager() {
                return run_package_action(
                    manager,
                    PackageAction::Install,
                    package_name(dep.name, manager),
                );
            }
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
        if let Some(manager) = detect_package_manager() {
            return run_package_action(manager, PackageAction::Update, package_name(name, manager));
        }
        (false, format!("No supported updater for {name}"))
    }

    fn probe_version(binary: &str) -> Option<String> {
        let out = Command::new(binary).arg("--version").output().ok()?;
        let raw = String::from_utf8_lossy(&out.stdout);
        Some(raw.lines().next().unwrap_or("").trim().to_owned())
    }
}

fn detect_package_manager() -> Option<PackageManager> {
    [
        ("brew", PackageManager::Brew),
        ("apt-get", PackageManager::Apt),
        ("dnf", PackageManager::Dnf),
        ("pacman", PackageManager::Pacman),
        ("snap", PackageManager::Snap),
    ]
    .into_iter()
    .find_map(|(binary, manager)| which::which(binary).ok().map(|_| manager))
}

fn package_name(name: &str, manager: PackageManager) -> &str {
    match (name, manager) {
        ("lima", PackageManager::Brew) => "lima",
        ("lima", _) => "lima",
        ("qemu", PackageManager::Brew) => "qemu",
        ("qemu", _) => "qemu-system",
        ("docker-cli", PackageManager::Brew) => "docker",
        ("docker-cli", PackageManager::Apt) => "docker.io",
        ("docker-cli", _) => "docker-cli",
        ("kubectl", _) => "kubectl",
        (other, _) => other,
    }
}

fn is_root() -> bool {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|status| {
            status
                .lines()
                .find(|line| line.starts_with("Uid:"))
                .and_then(|line| line.split_whitespace().nth(1))
                .and_then(|uid| uid.parse::<u32>().ok())
        })
        == Some(0)
}

fn package_command(
    manager: PackageManager,
    action: PackageAction,
    package: &str,
    root: bool,
    pkexec_available: bool,
) -> Result<(String, Vec<String>), String> {
    let (program, args): (&str, Vec<&str>) = match (manager, action) {
        (PackageManager::Brew, PackageAction::Install) => ("brew", vec!["install", package]),
        (PackageManager::Brew, PackageAction::Update) => ("brew", vec!["upgrade", package]),
        (PackageManager::Apt, PackageAction::Install) => {
            ("apt-get", vec!["install", "-y", package])
        }
        (PackageManager::Apt, PackageAction::Update) => {
            ("apt-get", vec!["install", "--only-upgrade", "-y", package])
        }
        (PackageManager::Dnf, PackageAction::Install) => ("dnf", vec!["install", "-y", package]),
        (PackageManager::Dnf, PackageAction::Update) => ("dnf", vec!["upgrade", "-y", package]),
        (PackageManager::Pacman, PackageAction::Install) => {
            ("pacman", vec!["-S", "--noconfirm", package])
        }
        (PackageManager::Pacman, PackageAction::Update) => {
            ("pacman", vec!["-S", "--noconfirm", package])
        }
        (PackageManager::Snap, PackageAction::Install) => ("snap", vec!["install", package]),
        (PackageManager::Snap, PackageAction::Update) => ("snap", vec!["refresh", package]),
    };
    if manager == PackageManager::Brew || root {
        return Ok((
            program.to_owned(),
            args.into_iter().map(str::to_owned).collect(),
        ));
    }
    if !pkexec_available {
        return Err(format!(
            "Installing {package} needs administrator access. Install polkit/pkexec or run the package command from a terminal."
        ));
    }
    let mut elevated = vec![program.to_owned()];
    elevated.extend(args.into_iter().map(str::to_owned));
    Ok(("pkexec".to_owned(), elevated))
}

fn run_package_action(
    manager: PackageManager,
    action: PackageAction,
    package: &str,
) -> (bool, String) {
    match package_command(
        manager,
        action,
        package,
        is_root(),
        which::which("pkexec").is_ok(),
    ) {
        Ok((program, args)) => {
            let args: Vec<&str> = args.iter().map(String::as_str).collect();
            run_install(&program, &args)
        }
        Err(error) => (false, error),
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn system_packages_use_pkexec_without_a_terminal_sudo_prompt() {
        let (program, args) = package_command(
            PackageManager::Apt,
            PackageAction::Install,
            "docker.io",
            false,
            true,
        )
        .unwrap();
        assert_eq!(program, "pkexec");
        assert_eq!(args, ["apt-get", "install", "-y", "docker.io"]);
        assert!(!args.iter().any(|arg| arg == "sudo"));
    }

    #[test]
    fn missing_privilege_broker_returns_instructions_instead_of_hanging() {
        let error = package_command(
            PackageManager::Dnf,
            PackageAction::Update,
            "kubectl",
            false,
            false,
        )
        .unwrap_err();
        assert!(error.contains("administrator access"));
    }

    #[test]
    fn brew_never_requests_elevation() {
        let (program, args) = package_command(
            PackageManager::Brew,
            PackageAction::Update,
            "colima",
            false,
            false,
        )
        .unwrap();
        assert_eq!(program, "brew");
        assert_eq!(args, ["upgrade", "colima"]);
    }
}
