using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class NetworksPage : Page
{
    public NetworksViewModel ViewModel { get; } = new();

    public NetworksPage()
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

    // RemoveNetwork/PruneNetworks commands present the accessible confirmation themselves.
    private void RemoveNetwork_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = NetworkIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            ViewModel.RemoveNetworkCommand.Execute(id);
    }

    private void PruneNetworks_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e) =>
        ViewModel.PruneNetworksCommand.Execute(null);

    private async void InspectNetwork_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = NetworkIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.InspectNetworkCommand.ExecuteAsync(id);
    }
}
