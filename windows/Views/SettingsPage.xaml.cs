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
        // Subscribe to IsReady changes so we can set Severity (enum x:Bind not supported in WinUI 3)
        ViewModel.DependencyManager.PropertyChanged += DependencyManager_PropertyChanged;
        UpdateDepsSeverity();
        await ViewModel.LoadAsync();
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        ViewModel.DependencyManager.PropertyChanged -= DependencyManager_PropertyChanged;
    }

    private void DependencyManager_PropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(DependencyManager.IsReady))
            UpdateDepsSeverity();
    }

    private void UpdateDepsSeverity()
    {
        DepsOverallInfoBar.Severity = ViewModel.DependencyManager.IsReady
            ? InfoBarSeverity.Success
            : InfoBarSeverity.Warning;
    }

    private void RadioLocalWSL2_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        => ViewModel.SwitchToLocalWsl2Command.Execute(null);

    private void RadioRemoteSSH_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        => ViewModel.SwitchToRemoteSSHCommand.Execute(null);
}
