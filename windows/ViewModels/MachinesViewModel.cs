using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Colimaui;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Machines view (Lima): list Lima machines.
/// CONTRACT Part A ListMachines (M1.5 additive).
/// </summary>
public sealed partial class MachinesViewModel : ViewModelBase
{
    [ObservableProperty] private MachineList? _machines;

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(async t =>
        {
            Machines = await Client.ListMachinesAsync(t);
        }, ct);

    [RelayCommand]
    private Task RefreshAsync() => LoadAsync();
}
