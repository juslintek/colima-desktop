using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ColimaDesktop.Windows.Services;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Runtime Controls: switch runtime, update runtime, update colima, prune.
/// CONTRACT Part A SwitchRuntime/UpdateRuntime/Update/Prune.
/// </summary>
public sealed partial class RuntimeViewModel : ViewModelBase
{
    public string ActiveProfile => Settings.ActiveProfile;

    [ObservableProperty] private string _targetRuntime = "docker";
    [ObservableProperty] private string _statusMessage = string.Empty;

    [RelayCommand]
    private Task SwitchRuntimeAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.SwitchRuntimeAsync(Settings.ActiveProfile, TargetRuntime, t);
            StatusMessage = resp.Success ? $"Switched to {TargetRuntime}" : $"Error: {resp.Error}";
        });

    [RelayCommand]
    private Task UpdateRuntimeAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.UpdateRuntimeAsync(Settings.ActiveProfile, t);
            StatusMessage = resp.Success ? "Runtime updated." : $"Error: {resp.Error}";
        });

    [RelayCommand]
    private Task UpdateColimaAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.UpdateAsync(Settings.ActiveProfile, t);
            StatusMessage = resp.Success ? "Colima updated." : $"Error: {resp.Error}";
        });

    [RelayCommand]
    private Task PruneAsync(bool all = false) =>
        RunDestructiveAsync(
            all
                ? new DestructiveAction("PruneAll", "prune all resources",
                    "All eligible resources will be removed. This action is destructive and cannot be undone.", "Prune All")
                : new DestructiveAction("Prune", "prune unused resources",
                    $"Unused resources for profile '{ActiveProfile}' will be removed. This action cannot be undone.", "Prune"),
            async t =>
            {
                var resp = await Client.PruneAsync(Settings.ActiveProfile, all, t);
                StatusMessage = resp.Success ? "Pruned." : $"Error: {resp.Error}";
            });
}
