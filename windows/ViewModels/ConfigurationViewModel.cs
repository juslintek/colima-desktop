using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Colimaui;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Configuration view: get/set ColimaConfig (CPU, memory, disk, runtime, VM type,
/// arch, network, kubernetes, mounts, env) + template read/write.
/// CONTRACT Part A GetConfig/SetConfig/GetTemplate/SetTemplate.
/// </summary>
public sealed partial class ConfigurationViewModel : ViewModelBase
{
    [ObservableProperty] private ColimaConfig? _config;
    [ObservableProperty] private ColimaConfig? _template;
    [ObservableProperty] private string _statusMessage = string.Empty;

    // Flattened editable fields (bound individually in XAML).
    // NumberBox.Value is double, so cpu/memory/disk are double to avoid XamlCompiler type errors.
    [ObservableProperty] private double _cpu;
    [ObservableProperty] private double _memory;
    [ObservableProperty] private double _disk;
    [ObservableProperty] private string _runtime = string.Empty;
    [ObservableProperty] private string _vmType = string.Empty;
    [ObservableProperty] private string _arch = string.Empty;
    [ObservableProperty] private bool _kubernetesEnabled;
    [ObservableProperty] private string _kubernetesVersion = string.Empty;
    [ObservableProperty] private bool _rosetta;
    [ObservableProperty] private string _mountType = string.Empty;

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(async t =>
        {
            Config = await Client.GetConfigAsync(Settings.ActiveProfile, t);
            ApplyConfigToFields(Config);
        }, ct);

    [RelayCommand]
    private Task LoadTemplateAsync() =>
        RunAsync(async t =>
        {
            Template = await Client.GetTemplateAsync(t);
        });

    [RelayCommand]
    private Task SaveConfigAsync() =>
        RunAsync(async t =>
        {
            if (Config is null) return;
            ApplyFieldsToConfig(Config);
            var resp = await Client.SetConfigAsync(Settings.ActiveProfile, Config, t);
            StatusMessage = resp.Success ? "Configuration saved." : $"Error: {resp.Error}";
        });

    [RelayCommand]
    private Task SaveTemplateAsync() =>
        RunAsync(async t =>
        {
            if (Template is null) return;
            var resp = await Client.SetTemplateAsync(Template, t);
            StatusMessage = resp.Success ? "Template saved." : $"Error: {resp.Error}";
        });

    private void ApplyConfigToFields(ColimaConfig cfg)
    {
        Cpu = cfg.Cpu;
        Memory = cfg.Memory;
        Disk = cfg.Disk;
        Runtime = cfg.Runtime;
        VmType = cfg.VmType;
        Arch = cfg.Arch;
        KubernetesEnabled = cfg.Kubernetes?.Enabled ?? false;
        KubernetesVersion = cfg.Kubernetes?.Version ?? string.Empty;
        Rosetta = cfg.Rosetta;
        MountType = cfg.MountType;
    }

    private void ApplyFieldsToConfig(ColimaConfig cfg)
    {
        cfg.Cpu = (int)Cpu;
        cfg.Memory = (float)Memory;
        cfg.Disk = (int)Disk;
        cfg.Runtime = Runtime;
        cfg.VmType = VmType;
        cfg.Arch = Arch;
        cfg.Rosetta = Rosetta;
        cfg.MountType = MountType;
        if (cfg.Kubernetes is null) cfg.Kubernetes = new KubernetesConfig();
        cfg.Kubernetes.Enabled = KubernetesEnabled;
        cfg.Kubernetes.Version = KubernetesVersion;
    }
}
