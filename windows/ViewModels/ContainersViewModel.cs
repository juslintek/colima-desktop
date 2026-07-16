using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

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

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(async token =>
        {
            var resp = await Client.ListContainersAsync(
                Settings.ActiveProfile, all: true, wsl2: Settings.UseWsl2, ct: token);
            RawJson = resp.Json;
        }, ct);

    [RelayCommand]
    private Task StartContainerAsync(string id) =>
        RunAsync(t => Client.ContainerActionAsync(id, "start", Settings.ActiveProfile, Settings.UseWsl2, t).ContinueWith(_ => LoadAsync(t)).Unwrap());

    [RelayCommand]
    private Task StopContainerAsync(string id) =>
        RunAsync(t => Client.ContainerActionAsync(id, "stop", Settings.ActiveProfile, Settings.UseWsl2, t).ContinueWith(_ => LoadAsync(t)).Unwrap());

    [RelayCommand]
    private Task KillContainerAsync(string id) =>
        RunAsync(t => Client.ContainerActionAsync(id, "kill", Settings.ActiveProfile, Settings.UseWsl2, t).ContinueWith(_ => LoadAsync(t)).Unwrap());

    [RelayCommand]
    private Task RestartContainerAsync(string id) =>
        RunAsync(t => Client.ContainerActionAsync(id, "restart", Settings.ActiveProfile, Settings.UseWsl2, t).ContinueWith(_ => LoadAsync(t)).Unwrap());

    [RelayCommand]
    private Task PauseContainerAsync(string id) =>
        RunAsync(t => Client.ContainerActionAsync(id, "pause", Settings.ActiveProfile, Settings.UseWsl2, t).ContinueWith(_ => LoadAsync(t)).Unwrap());

    [RelayCommand]
    private Task UnpauseContainerAsync(string id) =>
        RunAsync(t => Client.ContainerActionAsync(id, "unpause", Settings.ActiveProfile, Settings.UseWsl2, t).ContinueWith(_ => LoadAsync(t)).Unwrap());

    [RelayCommand]
    private Task RemoveContainerAsync(string id) =>
        RunAsync(t => Client.ContainerActionAsync(id, "remove", Settings.ActiveProfile, Settings.UseWsl2, t).ContinueWith(_ => LoadAsync(t)).Unwrap());

    [RelayCommand]
    private Task CreateContainerAsync() =>
        RunAsync(async t =>
        {
            await Client.CreateContainerAsync(NewContainerName, NewContainerImage, Settings.ActiveProfile, Settings.UseWsl2, t);
            NewContainerName = string.Empty;
            NewContainerImage = string.Empty;
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task RenameContainerAsync(string id) =>
        RunAsync(async t =>
        {
            await Client.RenameContainerAsync(id, RenameNewName, Settings.ActiveProfile, t);
            RenameNewName = string.Empty;
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task InspectContainerAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.InspectContainerAsync(id, Settings.ActiveProfile, Settings.UseWsl2, t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ContainerTopAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.ContainerTopAsync(id, Settings.ActiveProfile, Settings.UseWsl2, t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ContainerStatsAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.ContainerStatsAsync(id, Settings.ActiveProfile, Settings.UseWsl2, t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ContainerChangesAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.ContainerChangesAsync(id, Settings.ActiveProfile, Settings.UseWsl2, t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ContainerLogsAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.ContainerLogsAsync(id, Settings.ActiveProfile, Settings.UseWsl2, t);
            LogsText = resp.Json;
        });

    [RelayCommand]
    private Task PruneContainersAsync() =>
        RunAsync(async t =>
        {
            await Client.PruneContainersAsync(Settings.ActiveProfile, Settings.UseWsl2, t);
            await LoadAsync(t);
        });
}
