using Microsoft.UI.Xaml;

namespace ColimaDesktop.Windows;

public partial class App : Application
{
    private Window? _window;
    public App() { }
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }
}
