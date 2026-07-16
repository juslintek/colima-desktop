using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class ImagesPage : Page
{
    public ImagesViewModel ViewModel { get; } = new();

    public ImagesPage()
    {
        InitializeComponent();
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.LoadAsync();
    }

    private async void RemoveImage_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = ImageIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.RemoveImageCommand.ExecuteAsync(id);
    }

    private async void InspectImage_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = ImageIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.InspectImageCommand.ExecuteAsync(id);
    }

    private async void ImageHistory_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = ImageIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.ImageHistoryCommand.ExecuteAsync(id);
    }

    private async void PushImage_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = ImageIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.PushImageCommand.ExecuteAsync(id);
    }
}
