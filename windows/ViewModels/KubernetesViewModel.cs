using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Colimaui;
using ColimaDesktop.Windows.Services;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Kubernetes view: start/stop/reset cluster, exec kubectl commands.
/// CONTRACT Part A KubernetesStart/Stop/Reset/Exec.
/// </summary>
public sealed partial class KubernetesViewModel : ViewModelBase
{
    [ObservableProperty] private VMStatus? _vmStatus;
    [ObservableProperty] private string _kubectlCommand = "get pods --all-namespaces";
    [ObservableProperty] private string _kubectlOutput = string.Empty;
    [ObservableProperty] private int _kubectlExitCode;

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(LoadCoreAsync, ct);

    private async Task LoadCoreAsync(CancellationToken t)
    {
        await LoadCoreAsync(ConnectionSettings.NormalizeProfile(Settings.ActiveProfile), t);
    }

    private async Task LoadCoreAsync(string profile, CancellationToken t)
    {
        VmStatus = await Client.StatusAsync(profile, t);
    }

    [RelayCommand]
    private Task StartKubernetesAsync() =>
        RunAsync(async t =>
        {
            var profile = ConnectionSettings.NormalizeProfile(Settings.ActiveProfile);
            await Client.KubernetesStartAsync(profile, t);
            await LoadCoreAsync(profile, t);
        });

    [RelayCommand]
    private Task StopKubernetesAsync() =>
        RunAsync(async t =>
        {
            var profile = ConnectionSettings.NormalizeProfile(Settings.ActiveProfile);
            await Client.KubernetesStopAsync(profile, t);
            await LoadCoreAsync(profile, t);
        });

    [RelayCommand]
    private Task ResetKubernetesAsync() =>
        RunDestructiveAsync(
            new DestructiveAction("ResetKubernetes", "reset Kubernetes",
                "The Kubernetes cluster state in the selected profile will be reset.", "Reset"),
            async t =>
            {
                var profile = ConnectionSettings.NormalizeProfile(Settings.ActiveProfile);
                await Client.KubernetesResetAsync(profile, t);
                await LoadCoreAsync(profile, t);
            });

    [RelayCommand]
    private Task ExecKubectlAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.KubernetesExecAsync(Settings.ActiveProfile, KubectlCommand, t);
            KubectlOutput = string.IsNullOrEmpty(resp.Error) ? resp.Output : $"{resp.Output}\n\nERROR: {resp.Error}";
            KubectlExitCode = resp.ExitCode;
        });
}
