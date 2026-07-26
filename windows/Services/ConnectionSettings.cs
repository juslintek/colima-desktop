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

    [ObservableProperty]
    private bool _isConnected;

    [ObservableProperty]
    private string _connectionStatus = "Disconnected";

    /// <summary>Resolves the daemon address based on current mode.</summary>
    public string DaemonAddress => Mode switch
    {
        BackendMode.RemoteSSH => RemoteHost,
        BackendMode.LocalWSL2 => Wsl2Host,
        _ => Wsl2Host
    };

    /// <summary>Whether the WSL2 backend flag should be sent in Docker RPC scopes.</summary>
    public bool UseWsl2 => Mode == BackendMode.LocalWSL2;
    public bool UseRemoteSsh => Mode == BackendMode.RemoteSSH;

    /// <summary>
    /// Captures one immutable target for an operation. Commands must take this snapshot once so a
    /// settings change cannot split one multi-step action across different profiles/providers.
    /// </summary>
    public DockerTarget CaptureDockerTarget() => new(
        NormalizeProfile(ActiveProfile),
        Mode == BackendMode.RemoteSSH ? SshTarget.Trim() : string.Empty,
        UseWsl2);

    public static string NormalizeProfile(string? profile) =>
        string.IsNullOrWhiteSpace(profile) ? "default" : profile.Trim();

    partial void OnModeChanged(BackendMode value)
    {
        OnPropertyChanged(nameof(DaemonAddress));
        OnPropertyChanged(nameof(UseWsl2));
        OnPropertyChanged(nameof(UseRemoteSsh));
        IsConnected = false;
        ConnectionStatus = "Connection settings changed; apply to reconnect.";
    }

    partial void OnRemoteHostChanged(string value) => MarkConnectionDirty();

    partial void OnWsl2HostChanged(string value) => MarkConnectionDirty();

    private void MarkConnectionDirty()
    {
        OnPropertyChanged(nameof(DaemonAddress));
        IsConnected = false;
        ConnectionStatus = "Connection settings changed; apply to reconnect.";
    }
}

/// <summary>Profile and provider fields available on Docker RPC messages.</summary>
public readonly record struct DockerTarget(string Profile, string Host, bool Wsl2)
{
    public bool UsesProviderRouting => Wsl2 || !string.IsNullOrWhiteSpace(Host);
}
