using System.Collections.ObjectModel;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Colimaui;

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

    private CancellationTokenSource? _streamCts;

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(async t =>
        {
            Processes = await Client.ProcessListAsync(Settings.ActiveProfile, t);
        }, ct);

    [RelayCommand]
    private async Task StartStatsStreamAsync()
    {
        if (IsStreaming) return;
        IsStreaming = true;
        _streamCts = new CancellationTokenSource();
        var ct = _streamCts.Token;
        try
        {
            using var call = Client.VMStatsStream(Settings.ActiveProfile);
            await foreach (var evt in call.ResponseStream.ReadAllAsync(ct))
            {
                LatestStats = evt;
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { StatusMessage = $"Stream error: {ex.Message}"; }
        finally { IsStreaming = false; }
    }

    [RelayCommand]
    private void StopStatsStream()
    {
        _streamCts?.Cancel();
        _streamCts = null;
    }

    [RelayCommand]
    private Task RefreshProcessesAsync() => LoadAsync();

    [RelayCommand]
    private Task KillProcessAsync(int pid) =>
        RunAsync(async t =>
        {
            var resp = await Client.KillProcessAsync(Settings.ActiveProfile, pid, ct: t);
            StatusMessage = resp.Success ? $"Process {pid} killed." : $"Error: {resp.Error}";
            await LoadAsync(t);
        });
}
