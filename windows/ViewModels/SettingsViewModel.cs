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

    // Typed accessors for each dependency (indexer x:Bind not supported in WinUI 3 XamlCompiler)
    public DependencyManager.Dependency Wsl2Dep => DependencyManager.Dependencies[0];
    public DependencyManager.Dependency DockerDep => DependencyManager.Dependencies[1];
    public DependencyManager.Dependency DaemonDep => DependencyManager.Dependencies[2];

    [ObservableProperty] private string _statusMessage = string.Empty;

    public override Task LoadAsync(CancellationToken ct = default) =>
        DependencyManager.CheckAllAsync(ct);

    [RelayCommand]
    private Task InstallWsl2Async() =>
        RunAsync(t => DependencyManager.InstallWsl2Async(
            new Progress<string>(msg => StatusMessage = msg), t));

    [RelayCommand]
    private Task InstallDockerAsync() =>
        RunAsync(t => DependencyManager.InstallDockerAsync(
            new Progress<string>(msg => StatusMessage = msg), t));

    [RelayCommand]
    private Task InstallDaemonAsync() =>
        RunAsync(t => DependencyManager.InstallDaemonAsync(
            new Progress<string>(msg => StatusMessage = msg), t));

    [RelayCommand]
    private Task CheckForUpdatesAsync() =>
        RunAsync(DependencyManager.CheckForUpdatesAsync);

    [RelayCommand]
    private void SwitchToRemoteSSH() =>
        ConnectionSettings.Mode = ConnectionSettings.BackendMode.RemoteSSH;

    [RelayCommand]
    private void SwitchToLocalWsl2() =>
        ConnectionSettings.Mode = ConnectionSettings.BackendMode.LocalWSL2;

    [RelayCommand]
    private async Task ApplyConnectionSettingsAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            var result = await App.DaemonConnectionManager.ConnectAsync(
                App.DaemonClient,
                ConnectionSettings,
                DependencyManager,
                allowTrustedLocalStart: true,
                token);
            StatusMessage = result.Message;
        }, ct);
    }
}
