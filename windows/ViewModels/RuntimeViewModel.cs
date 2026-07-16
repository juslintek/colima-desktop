using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Runtime Controls: switch runtime, update runtime, update colima, prune.
/// CONTRACT Part A SwitchRuntime/UpdateRuntime/Update/Prune.
/// </summary>
public sealed partial class RuntimeViewModel : ViewModelBase
{
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
            var resp = await Client.UpdateAsync(t);
            StatusMessage = resp.Success ? "Colima updated." : $"Error: {resp.Error}";
        });

    [RelayCommand]
    private Task PruneAsync(bool all = false) =>
        RunAsync(async t =>
        {
            var resp = await Client.PruneAsync(all, t);
            StatusMessage = resp.Success ? "Pruned." : $"Error: {resp.Error}";
        });
}
