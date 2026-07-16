using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

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
        RunAsync(async t =>
        {
            var resp = await Client.ListNetworksAsync(Settings.ActiveProfile, Settings.UseWsl2, t);
            RawJson = resp.Json;
        }, ct);

    [RelayCommand]
    private Task CreateNetworkAsync() =>
        RunAsync(async t =>
        {
            await Client.CreateNetworkAsync(NewNetworkName, Settings.ActiveProfile, Settings.UseWsl2, t);
            NewNetworkName = string.Empty;
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task RemoveNetworkAsync(string id) =>
        RunAsync(async t =>
        {
            await Client.RemoveNetworkAsync(id, Settings.ActiveProfile, Settings.UseWsl2, t);
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task InspectNetworkAsync(string id) =>
        RunAsync(async t =>
        {
            var resp = await Client.InspectNetworkAsync(id, Settings.ActiveProfile, Settings.UseWsl2, t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ConnectNetworkAsync() =>
        RunAsync(async t =>
        {
            await Client.ConnectNetworkAsync(ConnectNetworkId, ConnectContainerId, Settings.ActiveProfile, t);
            ConnectNetworkId = string.Empty;
            ConnectContainerId = string.Empty;
        });

    [RelayCommand]
    private Task DisconnectNetworkAsync() =>
        RunAsync(async t =>
        {
            await Client.DisconnectNetworkAsync(ConnectNetworkId, ConnectContainerId, Settings.ActiveProfile, t);
        });

    [RelayCommand]
    private Task PruneNetworksAsync() =>
        RunAsync(async t =>
        {
            await Client.PruneNetworksAsync(Settings.ActiveProfile, Settings.UseWsl2, t);
            await LoadAsync(t);
        });
}
