using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class VolumesPage : Page
{
    public VolumesViewModel ViewModel { get; } = new();

    public VolumesPage()
    {
        InitializeComponent();
        ViewModel.DestructiveConfirmationHandler = action =>
            DestructiveConfirmationDialog.ShowAsync(XamlRoot, action);
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.LoadAsync();
    }

    // RemoveVolume/PruneVolumes commands present the accessible confirmation themselves.
    private void RemoveVolume_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var name = VolumeNameBox.Text.Trim();
        if (!string.IsNullOrEmpty(name))
            ViewModel.RemoveVolumeCommand.Execute(name);
    }

    private void PruneVolumes_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e) =>
        ViewModel.PruneVolumesCommand.Execute(null);

    private async void InspectVolume_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var name = VolumeNameBox.Text.Trim();
        if (!string.IsNullOrEmpty(name))
            await ViewModel.InspectVolumeCommand.ExecuteAsync(name);
    }
}
