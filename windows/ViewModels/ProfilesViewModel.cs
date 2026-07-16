using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Colimaui;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Profiles view: list, create, delete, clone profiles.
/// CONTRACT Part A ListProfiles/CreateProfile/DeleteProfile/CloneProfile.
/// </summary>
public sealed partial class ProfilesViewModel : ViewModelBase
{
    [ObservableProperty] private ProfileList? _profiles;
    [ObservableProperty] private string _newProfileName = string.Empty;
    [ObservableProperty] private string _cloneSource = string.Empty;
    [ObservableProperty] private string _cloneDestination = string.Empty;
    [ObservableProperty] private string _statusMessage = string.Empty;

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(async t =>
        {
            Profiles = await Client.ListProfilesAsync(t);
        }, ct);

    [RelayCommand]
    private Task CreateProfileAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.CreateProfileAsync(NewProfileName, new ColimaConfig(), t);
            StatusMessage = resp.Success ? $"Profile '{NewProfileName}' created." : $"Error: {resp.Error}";
            NewProfileName = string.Empty;
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task DeleteProfileAsync(string name) =>
        RunAsync(async t =>
        {
            var resp = await Client.DeleteProfileAsync(name, ct: t);
            StatusMessage = resp.Success ? $"Profile '{name}' deleted." : $"Error: {resp.Error}";
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task CloneProfileAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.CloneProfileAsync(CloneSource, CloneDestination, t);
            StatusMessage = resp.Success
                ? $"Cloned '{CloneSource}' to '{CloneDestination}'."
                : $"Error: {resp.Error}";
            CloneSource = string.Empty;
            CloneDestination = string.Empty;
            await LoadAsync(t);
        });

    [RelayCommand]
    private void SelectProfile(string name) => Settings.ActiveProfile = name;
}
