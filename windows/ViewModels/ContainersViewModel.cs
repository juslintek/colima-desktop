using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ColimaDesktop.Windows.Services;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Containers view: list all containers, perform actions (start/stop/kill/restart/
/// pause/unpause/remove/rename/create/logs/inspect/top/stats/changes/prune).
/// CONTRACT Part B DockerService.
/// </summary>
public sealed partial class ContainersViewModel : ViewModelBase
{
    [ObservableProperty] private string _rawJson = string.Empty;
    [ObservableProperty] private string _selectedContainerId = string.Empty;
    [ObservableProperty] private string _detailJson = string.Empty;
    [ObservableProperty] private string _logsText = string.Empty;
    [ObservableProperty] private string _newContainerName = string.Empty;
    [ObservableProperty] private string _newContainerImage = string.Empty;
    [ObservableProperty] private string _renameNewName = string.Empty;
    [ObservableProperty] private string _streamText = string.Empty;
    [ObservableProperty] private bool _isStreaming;

    private StreamLifetime? _streamLifetime;

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(LoadCoreAsync, ct);

    private async Task LoadCoreAsync(CancellationToken token)
    {
        var target = Settings.CaptureDockerTarget();
        await LoadCoreAsync(target, token);
    }

    private async Task LoadCoreAsync(DockerTarget target, CancellationToken token)
    {
        var resp = await Client.ListContainersAsync(target, all: true, ct: token);
        RawJson = resp.Json;
    }

    [RelayCommand]
    private Task StartContainerAsync(string id) =>
        RunContainerActionAsync(id, "start");

    [RelayCommand]
    private Task StopContainerAsync(string id) =>
        RunContainerActionAsync(id, "stop");

    [RelayCommand]
    private Task KillContainerAsync(string id) =>
        RunDestructiveAsync(
            new DestructiveAction("KillContainer", $"kill container {id}",
                $"Confirm kill for container '{id}'. This can interrupt workloads or remove data.", "Kill"),
            t => ContainerActionCoreAsync(id, "kill", t));

    [RelayCommand]
    private Task RestartContainerAsync(string id) =>
        RunContainerActionAsync(id, "restart");

    [RelayCommand]
    private Task PauseContainerAsync(string id) =>
        RunContainerActionAsync(id, "pause");

    [RelayCommand]
    private Task UnpauseContainerAsync(string id) =>
        RunContainerActionAsync(id, "unpause");

    [RelayCommand]
    private Task RemoveContainerAsync(string id) =>
        RunDestructiveAsync(
            new DestructiveAction("RemoveContainer", $"remove container {id}",
                $"Confirm remove for container '{id}'. This can interrupt workloads or remove data.", "Remove"),
            t => ContainerActionCoreAsync(id, "remove", t));

    private Task RunContainerActionAsync(string id, string action) =>
        RunAsync(t => ContainerActionCoreAsync(id, action, t));

    private async Task ContainerActionCoreAsync(string id, string action, CancellationToken t)
    {
        var target = Settings.CaptureDockerTarget();
        await Client.ContainerActionAsync(id, action, target, t);
        await LoadCoreAsync(target, t);
    }

    [RelayCommand]
    private Task CreateContainerAsync() =>
        RunAsync(async t =>
        {
            var target = Settings.CaptureDockerTarget();
            await Client.CreateContainerAsync(NewContainerName, NewContainerImage, target, t);
            NewContainerName = string.Empty;
            NewContainerImage = string.Empty;
            await LoadCoreAsync(target, t);
        });

    [RelayCommand]
    private Task RenameContainerAsync(string id) =>
        RunAsync(async t =>
        {
            var target = Settings.CaptureDockerTarget();
            await Client.RenameContainerAsync(id, RenameNewName, target, t);
            RenameNewName = string.Empty;
            await LoadCoreAsync(target, t);
        });

    [RelayCommand]
    private Task InspectContainerAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.InspectContainerAsync(id, Settings.CaptureDockerTarget(), t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ContainerTopAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.ContainerTopAsync(id, Settings.CaptureDockerTarget(), t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ContainerStatsAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.ContainerStatsAsync(id, Settings.CaptureDockerTarget(), t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ContainerChangesAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.ContainerChangesAsync(id, Settings.CaptureDockerTarget(), t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ContainerLogsAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.ContainerLogsAsync(id, Settings.CaptureDockerTarget(), t);
            LogsText = resp.Json;
        });

    [RelayCommand]
    private Task PruneContainersAsync() =>
        RunDestructiveAsync(
            new DestructiveAction("PruneContainers", "prune stopped containers",
                "All stopped containers in the selected profile/provider will be removed.", "Prune"),
            async t =>
            {
                var target = Settings.CaptureDockerTarget();
                await Client.PruneContainersAsync(target, t);
                await LoadCoreAsync(target, t);
            });

    [RelayCommand]
    private Task StreamEventsAsync() => RunDockerStreamAsync(
        (target, ct) => Client.StreamEventsStream(target, ct));

    [RelayCommand]
    private Task StreamLogsAsync(string id) => RunDockerStreamAsync(
        (target, ct) => Client.StreamLogsStream(id, target, ct));

    [RelayCommand]
    private Task StreamStatsAsync(string id) => RunDockerStreamAsync(
        (target, ct) => Client.StreamStatsStream(id, target, ct));

    private async Task RunDockerStreamAsync(
        Func<DockerTarget, CancellationToken, Grpc.Core.AsyncServerStreamingCall<Colimaui.JsonResponse>> start)
    {
        if (_streamLifetime is not null)
        {
            ErrorMessage = "A Docker stream is already active. Stop it before starting another stream.";
            HasError = true;
            return;
        }

        _streamLifetime = new StreamLifetime();
        var streamLifetime = _streamLifetime;
        IsStreaming = true;
        StreamText = string.Empty;
        try
        {
            await RunAsync(async ct =>
            {
                var target = Settings.CaptureDockerTarget();
                using var call = start(target, ct);
                await foreach (var evt in call.ResponseStream.ReadAllAsync(ct))
                {
                    var json = DaemonResponse.EnsureJson(evt, "Docker stream").Json;
                    StreamText = StreamOutput.AppendBounded(StreamText, json);
                }
            }, streamLifetime.Token);
        }
        finally
        {
            if (ReferenceEquals(_streamLifetime, streamLifetime))
                _streamLifetime = null;
            streamLifetime.Dispose();
            IsStreaming = false;
        }
    }

    [RelayCommand]
    private void StopDockerStream()
    {
        _streamLifetime?.Cancel();
    }
}
