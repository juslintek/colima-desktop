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
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.LoadAsync();
    }

    private async void RemoveNetwork_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = NetworkIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.RemoveNetworkCommand.ExecuteAsync(id);
    }

    private async void InspectNetwork_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = NetworkIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.InspectNetworkCommand.ExecuteAsync(id);
    }
}
