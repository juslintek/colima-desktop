using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Volumes view: list/create/remove/inspect/prune.
/// CONTRACT Part B DockerService.
/// </summary>
public sealed partial class VolumesViewModel : ViewModelBase
{
    [ObservableProperty] private string _rawJson = string.Empty;
    [ObservableProperty] private string _detailJson = string.Empty;
    [ObservableProperty] private string _newVolumeName = string.Empty;

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(async t =>
        {
            var resp = await Client.ListVolumesAsync(Settings.ActiveProfile, Settings.UseWsl2, t);
            RawJson = resp.Json;
        }, ct);

    [RelayCommand]
    private Task CreateVolumeAsync() =>
        RunAsync(async t =>
        {
            await Client.CreateVolumeAsync(NewVolumeName, Settings.ActiveProfile, Settings.UseWsl2, t);
            NewVolumeName = string.Empty;
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task RemoveVolumeAsync(string name) =>
        RunAsync(async t =>
        {
            await Client.RemoveVolumeAsync(name, Settings.ActiveProfile, Settings.UseWsl2, t);
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task InspectVolumeAsync(string name) =>
        RunAsync(async t =>
        {
            var resp = await Client.InspectVolumeAsync(name, Settings.ActiveProfile, Settings.UseWsl2, t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task PruneVolumesAsync() =>
        RunAsync(async t =>
        {
            await Client.PruneVolumesAsync(Settings.ActiveProfile, Settings.UseWsl2, t);
            await LoadAsync(t);
        });
}
