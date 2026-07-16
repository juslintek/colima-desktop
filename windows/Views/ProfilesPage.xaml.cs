using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class ProfilesPage : Page
{
    public ProfilesViewModel ViewModel { get; } = new();

    public ProfilesPage()
    {
        InitializeComponent();
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.LoadAsync();
    }

    private void SelectProfile_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var name = (sender as Microsoft.UI.Xaml.Controls.Button)?.Tag?.ToString();
        if (!string.IsNullOrEmpty(name))
            ViewModel.SelectProfileCommand.Execute(name);
    }

    private async void DeleteProfile_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var name = (sender as Microsoft.UI.Xaml.Controls.Button)?.Tag?.ToString();
        if (!string.IsNullOrEmpty(name))
            await ViewModel.DeleteProfileCommand.ExecuteAsync(name);
    }
}
