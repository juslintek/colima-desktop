using Xunit;
using CommunityToolkit.Mvvm.Input;
using ColimaDesktop.Windows;
using ColimaDesktop.Windows.Services;
using ColimaDesktop.Windows.Tests.Fakes;

// The per-view-model tests drive real view-models, which reach the daemon client + connection
// settings through the static App singletons (the headless ProductionAppStub). Those statics are
// shared process-wide, so tests must not run in parallel across classes. Serial execution is fine —
// the whole suite is sub-second.
[assembly: CollectionBehavior(DisableTestParallelization = true)]

namespace ColimaDesktop.Windows.Tests;

/// <summary>
/// Configures the headless <see cref="App"/> singletons with a <see cref="RecordingDaemonClient"/>
/// and a fresh <see cref="ConnectionSettings"/> so a view-model constructed afterwards dispatches
/// through the recording fake. Call once at the start of each test (xUnit builds a fresh test-class
/// instance per test; parallelization is disabled above, so there is no cross-test race).
/// </summary>
public static class TestApp
{
    public const string DefaultProfile = "proj-x";

    public static (RecordingDaemonClient client, ConnectionSettings settings) Configure(
        string profile = DefaultProfile,
        ConnectionSettings.BackendMode mode = ConnectionSettings.BackendMode.LocalWSL2,
        string sshTarget = "user@remote")
    {
        var client = new RecordingDaemonClient();
        var settings = new ConnectionSettings
        {
            Mode = mode,
            ActiveProfile = profile,
            SshTarget = sshTarget,
        };

        App.DaemonClient = client;
        App.ConnectionSettings = settings;
        App.DependencyManager = new DependencyManager();
        App.DaemonConnectionManager = new DaemonConnectionManager();

        return (client, settings);
    }
}

/// <summary>
/// Invokes a generated <c>[RelayCommand]</c> through its async command surface — the exact dispatch
/// path the WinUI XAML binds to — so the per-view-model dispatch tests exercise commands the way the
/// UI does (Property 12), not by reaching past the command into a private method.
/// </summary>
public static class CommandExt
{
    public static Task Run(this IAsyncRelayCommand command, object? parameter = null)
        => command.ExecuteAsync(parameter);
}
