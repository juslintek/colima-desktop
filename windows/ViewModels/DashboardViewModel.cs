using System.Collections.ObjectModel;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Colimaui;
using ColimaDesktop.Windows.Services;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Dashboard: VM status, start/stop/restart lifecycle controls, SSH config panel.
/// Mirrors the macOS Dashboard surface (CONTRACT Part A).
/// </summary>
public sealed partial class DashboardViewModel : ViewModelBase
{
    [ObservableProperty] private VMStatus? _vmStatus;
    [ObservableProperty] private VersionResponse? _version;
    [ObservableProperty] private string _sshConfig = string.Empty;
    [ObservableProperty] private string _progressMessage = string.Empty;
    [ObservableProperty] private float _progressValue;
    [ObservableProperty] private bool _isProgressVisible;

    public override Task LoadAsync(CancellationToken ct = default) => RunAsync(LoadCoreAsync, ct);

    private Task LoadCoreAsync(CancellationToken token) =>
        LoadCoreAsync(ConnectionSettings.NormalizeProfile(Settings.ActiveProfile), token);

    private async Task LoadCoreAsync(string profile, CancellationToken token)
    {
        VmStatus = await Client.StatusAsync(profile, token);
        Version = await Client.VersionAsync(token);
    }

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task StartAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            IsProgressVisible = true;
            var profile = ConnectionSettings.NormalizeProfile(Settings.ActiveProfile);
            ProgressMessage = "Starting…";
            ProgressValue = 0;
            var completed = false;
            try
            {
                using var call = Client.StartStream(profile, ct: token);
                await foreach (var rawEvent in call.ResponseStream.ReadAllAsync(token))
                {
                    var evt = DaemonResponse.EnsureProgress(rawEvent, "Start VM");
                    ProgressMessage = evt.Message;
                    ProgressValue = evt.Progress;
                    if (evt.Done) { completed = true; break; }
                }
                if (!completed)
                    throw new DaemonOperationException("Start VM", "the progress stream ended before completion");
                await LoadCoreAsync(profile, token);
            }
            finally { IsProgressVisible = false; }
        }, ct);
    }

    [RelayCommand]
    private async Task StopAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            var profile = ConnectionSettings.NormalizeProfile(Settings.ActiveProfile);
            await Client.StopAsync(profile, ct: token);
            await LoadCoreAsync(profile, token);
        }, ct);
    }

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task RestartAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            IsProgressVisible = true;
            var profile = ConnectionSettings.NormalizeProfile(Settings.ActiveProfile);
            ProgressMessage = "Restarting…";
            ProgressValue = 0;
            var completed = false;
            try
            {
                using var call = Client.RestartStream(profile, token);
                await foreach (var rawEvent in call.ResponseStream.ReadAllAsync(token))
                {
                    var evt = DaemonResponse.EnsureProgress(rawEvent, "Restart VM");
                    ProgressMessage = evt.Message;
                    ProgressValue = evt.Progress;
                    if (evt.Done) { completed = true; break; }
                }
                if (!completed)
                    throw new DaemonOperationException("Restart VM", "the progress stream ended before completion");
                await LoadCoreAsync(profile, token);
            }
            finally { IsProgressVisible = false; }
        }, ct);
    }

    [RelayCommand]
    private Task DeleteAsync(bool includeData = false, CancellationToken ct = default) =>
        RunDestructiveAsync(
            new DestructiveAction("DeleteVm", "delete the selected VM",
                "This removes the selected Colima VM. This action cannot be undone.", "Delete VM"),
            async token =>
            {
                var profile = ConnectionSettings.NormalizeProfile(Settings.ActiveProfile);
                await Client.DeleteAsync(profile, data: includeData, force: false, ct: token);
                await LoadCoreAsync(profile, token);
            }, ct);

    [RelayCommand]
    private async Task ShowSshConfigAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            var resp = await Client.SSHConfigAsync(Settings.ActiveProfile, token);
            SshConfig = resp.Config;
        }, ct);
    }

    [RelayCommand]
    private void CancelLifecycle()
    {
        StartCommand.Cancel();
        RestartCommand.Cancel();
    }
}
