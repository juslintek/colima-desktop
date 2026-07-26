using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ColimaDesktop.Windows.Services;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Networks view: list/create/remove/inspect/connect/disconnect/prune.
/// CONTRACT Part B DockerService.
/// </summary>
public sealed partial class NetworksViewModel : ViewModelBase
{
    [ObservableProperty] private string _rawJson = string.Empty;
    [ObservableProperty] private string _detailJson = string.Empty;
    [ObservableProperty] private string _newNetworkName = string.Empty;
    [ObservableProperty] private string _connectNetworkId = string.Empty;
    [ObservableProperty] private string _connectContainerId = string.Empty;

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(LoadCoreAsync, ct);

    private async Task LoadCoreAsync(CancellationToken t)
    {
        await LoadCoreAsync(Settings.CaptureDockerTarget(), t);
    }

    private async Task LoadCoreAsync(DockerTarget target, CancellationToken t)
    {
        var resp = await Client.ListNetworksAsync(target, t);
        RawJson = resp.Json;
    }

    [RelayCommand]
    private Task CreateNetworkAsync() =>
        RunAsync(async t =>
        {
            var target = Settings.CaptureDockerTarget();
            await Client.CreateNetworkAsync(NewNetworkName, target, t);
            NewNetworkName = string.Empty;
            await LoadCoreAsync(target, t);
        });

    [RelayCommand]
    private Task RemoveNetworkAsync(string id) =>
        RunDestructiveAsync(
            new DestructiveAction("RemoveNetwork", $"remove network {id}",
                $"Network '{id}' will be removed from the selected profile/provider.", "Remove"),
            async t =>
            {
                var target = Settings.CaptureDockerTarget();
                await Client.RemoveNetworkAsync(id, target, t);
                await LoadCoreAsync(target, t);
            });

    [RelayCommand]
    private Task InspectNetworkAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.InspectNetworkAsync(id, Settings.CaptureDockerTarget(), t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ConnectNetworkAsync() =>
        RunAsync(async t =>
        {
            await Client.ConnectNetworkAsync(ConnectNetworkId, ConnectContainerId, Settings.CaptureDockerTarget(), t);
            ConnectNetworkId = string.Empty;
            ConnectContainerId = string.Empty;
        });

    [RelayCommand]
    private Task DisconnectNetworkAsync() =>
        RunAsync(async t =>
        {
            await Client.DisconnectNetworkAsync(ConnectNetworkId, ConnectContainerId, Settings.CaptureDockerTarget(), t);
        });

    [RelayCommand]
    private Task PruneNetworksAsync() =>
        RunDestructiveAsync(
            new DestructiveAction("PruneNetworks", "prune unused networks",
                "Unused networks in the selected profile/provider will be removed.", "Prune"),
            async t =>
            {
                var target = Settings.CaptureDockerTarget();
                await Client.PruneNetworksAsync(target, t);
                await LoadCoreAsync(target, t);
            });
}
