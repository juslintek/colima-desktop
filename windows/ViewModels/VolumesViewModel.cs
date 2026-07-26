using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ColimaDesktop.Windows.Services;

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
        RunAsync(LoadCoreAsync, ct);

    private async Task LoadCoreAsync(CancellationToken t)
    {
        await LoadCoreAsync(Settings.CaptureDockerTarget(), t);
    }

    private async Task LoadCoreAsync(DockerTarget target, CancellationToken t)
    {
        var resp = await Client.ListVolumesAsync(target, t);
        RawJson = resp.Json;
    }

    [RelayCommand]
    private Task CreateVolumeAsync() =>
        RunAsync(async t =>
        {
            var target = Settings.CaptureDockerTarget();
            await Client.CreateVolumeAsync(NewVolumeName, target, t);
            NewVolumeName = string.Empty;
            await LoadCoreAsync(target, t);
        });

    [RelayCommand]
    private Task RemoveVolumeAsync(string name) =>
        RunDestructiveAsync(
            new DestructiveAction("RemoveVolume", $"remove volume {name}",
                $"Volume '{name}' and its stored data will be removed.", "Remove"),
            async t =>
            {
                var target = Settings.CaptureDockerTarget();
                await Client.RemoveVolumeAsync(name, target, t);
                await LoadCoreAsync(target, t);
            });

    [RelayCommand]
    private Task InspectVolumeAsync(string name) =>
        RunAsync(async t =>
        {
            var resp = await Client.InspectVolumeAsync(name, Settings.CaptureDockerTarget(), t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task PruneVolumesAsync() =>
        RunDestructiveAsync(
            new DestructiveAction("PruneVolumes", "prune unused volumes",
                "Unused volumes and their stored data will be removed.", "Prune"),
            async t =>
            {
                var target = Settings.CaptureDockerTarget();
                await Client.PruneVolumesAsync(target, t);
                await LoadCoreAsync(target, t);
            });
}
