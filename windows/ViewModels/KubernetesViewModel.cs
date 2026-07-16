using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Colimaui;

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
        RunAsync(async t =>
        {
            VmStatus = await Client.StatusAsync(Settings.ActiveProfile, t);
        }, ct);

    [RelayCommand]
    private Task StartKubernetesAsync() =>
        RunAsync(async t =>
        {
            await Client.KubernetesStartAsync(Settings.ActiveProfile, t);
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task StopKubernetesAsync() =>
        RunAsync(async t =>
        {
            await Client.KubernetesStopAsync(Settings.ActiveProfile, t);
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task ResetKubernetesAsync() =>
        RunAsync(async t =>
        {
            await Client.KubernetesResetAsync(Settings.ActiveProfile, t);
            await LoadAsync(t);
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
