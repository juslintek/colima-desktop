using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class KubernetesPage : Page
{
    public KubernetesViewModel ViewModel { get; } = new();

    public KubernetesPage()
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

    // ResetKubernetesCommand presents the accessible confirmation itself.
    private void ResetKubernetes_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e) =>
        ViewModel.ResetKubernetesCommand.Execute(null);
}
