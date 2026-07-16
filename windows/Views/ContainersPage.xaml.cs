using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class ContainersPage : Page
{
    public ContainersViewModel ViewModel { get; } = new();

    public ContainersPage()
    {
        InitializeComponent();
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.LoadAsync();
    }

    // Code-behind helpers pass TextBox values to commands (x:Bind doesn't support passing
    // UI elements to commands directly; we read the TextBox here and delegate to the VM).

    private async void ContainerAction_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = ContainerIdBox.Text.Trim();
        if (string.IsNullOrEmpty(id)) return;
        var action = (sender as Microsoft.UI.Xaml.Controls.Button)?.Tag?.ToString() ?? string.Empty;
        switch (action)
        {
            case "start":   await ViewModel.StartContainerCommand.ExecuteAsync(id); break;
            case "stop":    await ViewModel.StopContainerCommand.ExecuteAsync(id); break;
            case "kill":    await ViewModel.KillContainerCommand.ExecuteAsync(id); break;
            case "restart": await ViewModel.RestartContainerCommand.ExecuteAsync(id); break;
            case "pause":   await ViewModel.PauseContainerCommand.ExecuteAsync(id); break;
            case "unpause": await ViewModel.UnpauseContainerCommand.ExecuteAsync(id); break;
            case "remove":  await ViewModel.RemoveContainerCommand.ExecuteAsync(id); break;
        }
    }

    private async void InspectContainer_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = ContainerIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.InspectContainerCommand.ExecuteAsync(id);
    }

    private async void TopContainer_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = ContainerIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.ContainerTopCommand.ExecuteAsync(id);
    }

    private async void StatsContainer_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = ContainerIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.ContainerStatsCommand.ExecuteAsync(id);
    }

    private async void ChangesContainer_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = ContainerIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.ContainerChangesCommand.ExecuteAsync(id);
    }

    private async void LogsContainer_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = ContainerIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.ContainerLogsCommand.ExecuteAsync(id);
    }

    private async void RenameContainer_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var id = RenameIdBox.Text.Trim();
        if (!string.IsNullOrEmpty(id))
            await ViewModel.RenameContainerCommand.ExecuteAsync(id);
    }
}
