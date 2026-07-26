using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class MonitoringPage : Page
{
    public MonitoringViewModel ViewModel { get; } = new();

    public MonitoringPage()
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

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        // Stop the stats stream when leaving the page
        ViewModel.StopStatsStreamCommand.Execute(null);
    }

    // KillProcessCommand presents the accessible confirmation itself.
    private void KillProcess_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (int.TryParse(PidBox.Text.Trim(), out var pid))
            ViewModel.KillProcessCommand.Execute(pid);
    }
}
