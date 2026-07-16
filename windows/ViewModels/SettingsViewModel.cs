using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ColimaDesktop.Windows.Services;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Onboarding / Settings view-model. Surfaces the DependencyManager state
/// and the remote-SSH / local-WSL2 backend toggle. CONTRACT Part C (M4.13).
/// </summary>
public sealed partial class SettingsViewModel : ViewModelBase
{
    public DependencyManager DependencyManager => App.DependencyManager;
    public ConnectionSettings ConnectionSettings => App.ConnectionSettings;

    [ObservableProperty] private string _statusMessage = string.Empty;

    public override Task LoadAsync(CancellationToken ct = default) =>
        DependencyManager.CheckAllAsync(ct);

    [RelayCommand]
    private Task InstallWsl2Async() =>
        DependencyManager.InstallWsl2Async(
            new Progress<string>(msg => StatusMessage = msg));

    [RelayCommand]
    private Task InstallDockerAsync() =>
        DependencyManager.InstallDockerAsync(
            new Progress<string>(msg => StatusMessage = msg));

    [RelayCommand]
    private Task InstallDaemonAsync() =>
        DependencyManager.InstallDaemonAsync(
            new Progress<string>(msg => StatusMessage = msg));

    [RelayCommand]
    private Task CheckForUpdatesAsync() =>
        DependencyManager.CheckForUpdatesAsync();

    [RelayCommand]
    private void SwitchToRemoteSSH() =>
        ConnectionSettings.Mode = ConnectionSettings.BackendMode.RemoteSSH;

    [RelayCommand]
    private void SwitchToLocalWsl2() =>
        ConnectionSettings.Mode = ConnectionSettings.BackendMode.LocalWSL2;

    [RelayCommand]
    private void ApplyConnectionSettings()
    {
        App.DaemonClient.Reconnect(ConnectionSettings.DaemonAddress);
        StatusMessage = $"Reconnected to {ConnectionSettings.DaemonAddress}";
    }
}
