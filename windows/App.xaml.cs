using ColimaDesktop.Windows.Services;
using Microsoft.UI.Xaml;

namespace ColimaDesktop.Windows;

public partial class App : Application
{
    private Window? _window;

    /// <summary>Singleton access to the shared daemon client and connection settings.</summary>
    public static DaemonClient DaemonClient { get; private set; } = null!;
    public static ConnectionSettings ConnectionSettings { get; private set; } = null!;
    public static DependencyManager DependencyManager { get; private set; } = null!;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        ConnectionSettings = new ConnectionSettings();
        DaemonClient = new DaemonClient(ConnectionSettings.DaemonAddress);
        DependencyManager = new DependencyManager();

        _window = new MainWindow();
        _window.Activate();
    }
}
