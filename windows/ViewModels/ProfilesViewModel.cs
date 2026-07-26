using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Colimaui;
using ColimaDesktop.Windows.Services;

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
        RunAsync(LoadCoreAsync, ct);

    private async Task LoadCoreAsync(CancellationToken t)
    {
        Profiles = await Client.ListProfilesAsync(t);
    }

    [RelayCommand]
    private Task CreateProfileAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.CreateProfileAsync(NewProfileName, new ColimaConfig(), t);
            StatusMessage = resp.Success ? $"Profile '{NewProfileName}' created." : $"Error: {resp.Error}";
            NewProfileName = string.Empty;
            await LoadCoreAsync(t);
        });

    [RelayCommand]
    private Task DeleteProfileAsync(string name) =>
        RunDestructiveAsync(
            new DestructiveAction("DeleteProfile", $"delete profile {name}",
                $"Profile '{name}' will be deleted. This action cannot be undone.", "Delete"),
            async t =>
            {
                var resp = await Client.DeleteProfileAsync(name, ct: t);
                StatusMessage = resp.Success ? $"Profile '{name}' deleted." : $"Error: {resp.Error}";
                await LoadCoreAsync(t);
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
            await LoadCoreAsync(t);
        });

    [RelayCommand]
    private void SelectProfile(string name)
    {
        Settings.ActiveProfile = ConnectionSettings.NormalizeProfile(name);
        StatusMessage = $"Selected profile '{Settings.ActiveProfile}'. Other pages will use it on their next action or refresh.";
    }
}
