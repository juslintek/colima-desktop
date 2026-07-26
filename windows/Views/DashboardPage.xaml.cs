using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class DashboardPage : Page
{
    public DashboardViewModel ViewModel { get; } = new();

    public DashboardPage()
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
        ViewModel.StartCommand.Cancel();
        ViewModel.RestartCommand.Cancel();
        base.OnNavigatedFrom(e);
    }

    // The view-model's DeleteCommand now presents the accessible confirmation itself
    // (via DestructiveConfirmationHandler), so this handler just invokes it.
    private void DeleteVm_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e) =>
        ViewModel.DeleteCommand.Execute(false);
}
