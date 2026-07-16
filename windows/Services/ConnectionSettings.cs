using CommunityToolkit.Mvvm.ComponentModel;

namespace ColimaDesktop.Windows.Services;

/// <summary>
/// Holds the active backend connection mode: remote colima/Lima over SSH/gRPC
/// or local WSL2/Docker. Persists to ApplicationData.
/// </summary>
public sealed partial class ConnectionSettings : ObservableObject
{
    public enum BackendMode { RemoteSSH, LocalWSL2 }

    [ObservableProperty]
    private BackendMode _mode = BackendMode.LocalWSL2;

    /// <summary>gRPC address for the remote colima daemon (SSH tunnel target).</summary>
    [ObservableProperty]
    private string _remoteHost = "http://127.0.0.1:50051";

    /// <summary>gRPC address for the local WSL2-backed daemon.</summary>
    [ObservableProperty]
    private string _wsl2Host = "http://127.0.0.1:50051";

    /// <summary>SSH connection string for the remote backend (user@host).</summary>
    [ObservableProperty]
    private string _sshTarget = string.Empty;

    /// <summary>Active profile to query by default.</summary>
    [ObservableProperty]
    private string _activeProfile = "default";

    /// <summary>Resolves the daemon address based on current mode.</summary>
    public string DaemonAddress => Mode switch
    {
        BackendMode.RemoteSSH => RemoteHost,
        BackendMode.LocalWSL2 => Wsl2Host,
        _ => Wsl2Host
    };

    /// <summary>Whether the WSL2 backend flag should be sent in Docker RPC scopes.</summary>
    public bool UseWsl2 => Mode == BackendMode.LocalWSL2;
}
