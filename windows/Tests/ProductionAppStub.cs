using ColimaDesktop.Windows.Services;

namespace ColimaDesktop.Windows;

// Headless test host for production view-model compilation. Native WinUI tests use the real App.
public static class App
{
    public static IDaemonClient DaemonClient { get; set; } = null!;
    public static ConnectionSettings ConnectionSettings { get; set; } = null!;
    public static DependencyManager DependencyManager { get; set; } = null!;
    public static DaemonConnectionManager DaemonConnectionManager { get; set; } = null!;
}
