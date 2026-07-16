using ColimaDesktop.Windows.Views;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "Colima Desktop";
    }

    private void NavView_Loaded(object sender, RoutedEventArgs e)
    {
        // Navigate to Dashboard by default
        NavView.SelectedItem = NavDashboard;
        ContentFrame.Navigate(typeof(DashboardPage));
    }

    private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ContentFrame.Navigate(typeof(SettingsPage));
            return;
        }

        if (args.SelectedItem is not NavigationViewItem item) return;

        var tag = item.Tag?.ToString();
        var pageType = tag switch
        {
            "Dashboard"     => typeof(DashboardPage),
            "Containers"    => typeof(ContainersPage),
            "Images"        => typeof(ImagesPage),
            "Volumes"       => typeof(VolumesPage),
            "Networks"      => typeof(NetworksPage),
            "Machines"      => typeof(MachinesPage),
            "Kubernetes"    => typeof(KubernetesPage),
            "Configuration" => typeof(ConfigurationPage),
            "Runtime"       => typeof(RuntimePage),
            "AIWorkloads"   => typeof(AIWorkloadsPage),
            "Profiles"      => typeof(ProfilesPage),
            "Monitoring"    => typeof(MonitoringPage),
            "Settings"      => typeof(SettingsPage),
            _               => typeof(DashboardPage),
        };

        ContentFrame.Navigate(pageType);
    }
}
