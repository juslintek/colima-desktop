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

    public override async Task LoadAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            VmStatus = await Client.StatusAsync(Settings.ActiveProfile, token);
            Version = await Client.VersionAsync(token);
        }, ct);
    }

    [RelayCommand]
    private async Task StartAsync(CancellationToken ct = default)
    {
        IsProgressVisible = true;
        ProgressMessage = "Starting…";
        ProgressValue = 0;
        try
        {
            using var call = Client.StartStream(Settings.ActiveProfile);
            await foreach (var evt in call.ResponseStream.ReadAllAsync(ct))
            {
                ProgressMessage = evt.Message;
                ProgressValue = evt.Progress;
                if (evt.Done) break;
            }
        }
        catch { /* errors handled by gRPC status */ }
        finally
        {
            IsProgressVisible = false;
            await LoadAsync(ct);
        }
    }

    [RelayCommand]
    private async Task StopAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            await Client.StopAsync(Settings.ActiveProfile, ct: token);
            await LoadAsync(token);
        }, ct);
    }

    [RelayCommand]
    private async Task RestartAsync(CancellationToken ct = default)
    {
        IsProgressVisible = true;
        ProgressMessage = "Restarting…";
        ProgressValue = 0;
        try
        {
            using var call = Client.RestartStream(Settings.ActiveProfile);
            await foreach (var evt in call.ResponseStream.ReadAllAsync(ct))
            {
                ProgressMessage = evt.Message;
                ProgressValue = evt.Progress;
                if (evt.Done) break;
            }
        }
        catch { }
        finally
        {
            IsProgressVisible = false;
            await LoadAsync(ct);
        }
    }

    [RelayCommand]
    private async Task ShowSshConfigAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            var resp = await Client.SSHConfigAsync(Settings.ActiveProfile, token);
            SshConfig = resp.Config;
        }, ct);
    }
}
