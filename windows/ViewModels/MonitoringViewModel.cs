using System.Collections.ObjectModel;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Colimaui;
using Grpc.Core;
using ColimaDesktop.Windows.Services;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Monitoring view: live VM stats stream, process list, kill process.
/// CONTRACT Part A VMStats(stream)/ProcessList/KillProcess.
/// </summary>
public sealed partial class MonitoringViewModel : ViewModelBase
{
    [ObservableProperty] private VMStatsEvent? _latestStats;
    [ObservableProperty] private ProcessListResponse? _processes;
    [ObservableProperty] private string _statusMessage = string.Empty;
    [ObservableProperty] private bool _isStreaming;

    private StreamLifetime? _streamLifetime;

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(t => LoadProcessesCoreAsync(ConnectionSettings.NormalizeProfile(Settings.ActiveProfile), t), ct);

    private async Task LoadProcessesCoreAsync(string profile, CancellationToken t)
    {
        Processes = await Client.ProcessListAsync(profile, t);
    }

    [RelayCommand]
    private async Task StartStatsStreamAsync()
    {
        if (IsStreaming) return;
        IsStreaming = true;
        _streamLifetime = new StreamLifetime();
        var ct = _streamLifetime.Token;
        try
        {
            var profile = ConnectionSettings.NormalizeProfile(Settings.ActiveProfile);
            using var call = Client.VMStatsStream(profile, ct);
            await foreach (var evt in call.ResponseStream.ReadAllAsync(ct))
            {
                LatestStats = evt;
            }
        }
        catch (OperationCanceledException) { StatusMessage = "Stats stream stopped."; }
        catch (RpcException ex) when (ct.IsCancellationRequested && ex.StatusCode == StatusCode.Cancelled)
        {
            StatusMessage = "Stats stream stopped.";
        }
        catch (Exception ex) { StatusMessage = $"Stream error: {ex.Message}"; }
        finally
        {
            var streamLifetime = _streamLifetime;
            _streamLifetime = null;
            streamLifetime?.Dispose();
            IsStreaming = false;
        }
    }

    [RelayCommand]
    private void StopStatsStream()
    {
        _streamLifetime?.Cancel();
    }

    [RelayCommand]
    private Task RefreshProcessesAsync() => LoadAsync();

    [RelayCommand]
    private Task KillProcessAsync(int pid) =>
        RunDestructiveAsync(
            new DestructiveAction("KillProcess", $"kill process {pid}",
                $"Process {pid} in the selected profile will receive SIGKILL.", "Kill"),
            async t =>
            {
                var profile = ConnectionSettings.NormalizeProfile(Settings.ActiveProfile);
                var resp = await Client.KillProcessAsync(profile, pid, ct: t);
                StatusMessage = resp.Success ? $"Process {pid} killed." : $"Error: {resp.Error}";
                await LoadProcessesCoreAsync(profile, t);
            });
}
