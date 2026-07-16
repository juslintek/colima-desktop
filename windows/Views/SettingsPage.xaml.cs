using ColimaDesktop.Windows.Services;
using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class SettingsPage : Page
{
    public SettingsViewModel ViewModel { get; } = new();

    public SettingsPage()
    {
        InitializeComponent();
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.LoadAsync();
    }

    private void RadioLocalWSL2_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        => ViewModel.SwitchToLocalWsl2Command.Execute(null);

    private void RadioRemoteSSH_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        => ViewModel.SwitchToRemoteSSHCommand.Execute(null);
}
