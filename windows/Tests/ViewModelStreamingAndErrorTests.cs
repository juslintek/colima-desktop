using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;
using Colimaui;
using ColimaDesktop.Windows.Services;
using ColimaDesktop.Windows.Tests.Fakes;
using ColimaDesktop.Windows.ViewModels;
using Xunit;

namespace ColimaDesktop.Windows.Tests;

/// <summary>
/// Per-view-model coverage for the Windows streaming/cancellation surfaces, non-reentrant busy state
/// (Property 16), and backend-error surfacing (Requirement 5.6). Uses the <see cref="RecordingDaemonClient"/>
/// scripted stream reader so streaming completion, mid-stream cancellation, incomplete-stream
/// detection, and error frames are all deterministic and cannot hang.
/// <para/>
/// Feature: cross-platform-live-verification, Property 12; Property 16; Requirement 5.6.
/// </summary>
[Trait("Feature", "cross-platform-live-verification")]
public sealed class ViewModelStreamingAndErrorTests
{
    private const string Profile = TestApp.DefaultProfile;

    // ─── Docker stream dispatch + bounded accumulation (Property 12 / Requirement 5.3) ────────

    [Trait("Property", "12")]
    [Fact]
    public async Task ContainerStreamCommandsDispatchScopedDockerStreamsAndAccumulateOutput()
    {
        var (client, _) = TestApp.Configure(Profile, ConnectionSettings.BackendMode.LocalWSL2);
        client.DockerStreamFrames = new[]
        {
            new JsonResponse { Json = "{\"a\":1}" },
            new JsonResponse { Json = "{\"b\":2}" },
            new JsonResponse { Json = "{\"c\":3}" },
        };
        var vm = new ContainersViewModel();

        await vm.StreamEventsCommand.Run();

        var call = client.Single("StreamEventsStream");
        Assert.Equal(Profile, call.Profile);
        Assert.True(call.Wsl2);
        Assert.False(vm.IsStreaming);
        // Frames are appended (bounded, newline-joined) into the retained UI text.
        Assert.Contains("{\"a\":1}", vm.StreamText);
        Assert.Contains("{\"c\":3}", vm.StreamText);
    }

    [Trait("Property", "12")]
    [Fact]
    public async Task ContainerLogAndStatStreamsDispatchTheMappedStreamRpc()
    {
        var (client, _) = TestApp.Configure(Profile);
        var vm = new ContainersViewModel();

        await vm.StreamLogsCommand.Run("c1");
        Assert.Equal("c1", client.Single("StreamLogsStream").Arg(0));

        await vm.StreamStatsCommand.Run("c1");
        Assert.Equal("c1", client.Single("StreamStatsStream").Arg(0));
    }

    // ─── Mid-stream cancellation is honored (Requirement 5.6) ─────────────────────────────────

    [Fact]
    public async Task ContainerDockerStreamHonorsCancellationAndClearsStreamingState()
    {
        var (client, _) = TestApp.Configure(Profile);
        client.BlockStreamsAfterFrames = true; // reader parks after frames until cancelled
        var vm = new ContainersViewModel();

        var streaming = vm.StreamEventsCommand.Run();
        await WaitUntil(() => vm.IsStreaming);

        vm.StopDockerStreamCommand.Execute(null); // cancels the stream lifetime
        await streaming;

        Assert.False(vm.IsStreaming);
    }

    [Fact]
    public async Task MonitoringStatsStreamHonorsCancellationAndReportsStopped()
    {
        var (client, _) = TestApp.Configure(Profile);
        client.BlockStreamsAfterFrames = true;
        var vm = new MonitoringViewModel();

        var streaming = vm.StartStatsStreamCommand.Run();
        await WaitUntil(() => vm.IsStreaming);

        vm.StopStatsStreamCommand.Execute(null);
        await streaming;

        Assert.False(vm.IsStreaming);
        Assert.Contains("stopped", vm.StatusMessage, StringComparison.OrdinalIgnoreCase);
    }

    // ─── Non-reentrant busy state via a real command path (Property 16) ───────────────────────

    [Trait("Property", "16")]
    [Fact]
    public async Task AnInFlightStreamingCommandBlocksAConcurrentCommandOnTheSameViewModel()
    {
        var (client, _) = TestApp.Configure(Profile);
        client.BlockStreamsAfterFrames = true;
        var vm = new ContainersViewModel();

        // First command parks inside the operation gate (RunDockerStreamAsync → RunAsync).
        var streaming = vm.StreamEventsCommand.Run();
        await WaitUntil(() => vm.IsLoading);

        // A second command on the same view-model while the gate is held must be refused, not run.
        await vm.LoadCommand.Run();

        Assert.True(vm.HasError);
        Assert.Contains("already running", vm.ErrorMessage);

        vm.StopDockerStreamCommand.Execute(null);
        await streaming;
    }

    // ─── Streaming error + incompletion surfacing (Requirement 5.6) ───────────────────────────

    [Fact]
    public async Task ErrorFrameOnAStreamSurfacesAContextualError()
    {
        var (client, _) = TestApp.Configure(Profile);
        client.ProgressFrames = new[] { new ProgressEvent { Error = "registry unreachable" } };
        var vm = new AIWorkloadsViewModel { ModelName = "llama3", Runner = "docker" };

        await vm.RunModelCommand.Run();

        Assert.True(vm.HasError);
        Assert.Contains("registry unreachable", vm.ErrorMessage);
    }

    [Fact]
    public async Task IncompleteProgressStreamThatNeverCompletesIsDetected()
    {
        var (client, _) = TestApp.Configure(Profile);
        // Frames without a terminal Done=true: the operation must not report success.
        client.ProgressFrames = new[] { new ProgressEvent { Message = "50%", Progress = 0.5f } };
        var vm = new ImagesViewModel { PullImageName = "alpine:latest" };

        await vm.PullImageCommand.Run();

        Assert.True(vm.HasError);
        Assert.Contains("before completion", vm.ErrorMessage);
        Assert.False(vm.IsProgressVisible); // progress banner hidden in finally, even on failure
    }

    // ─── Backend-error surfacing on non-streaming commands (Requirement 5.6) ──────────────────

    private sealed record ErrorCase(string Name, string FailingRpc, Func<ViewModelBase> Make, Func<ViewModelBase, Task> Invoke);

    private static IReadOnlyList<ErrorCase> ErrorCases() => new[]
    {
        new ErrorCase("Kubernetes.Start", "KubernetesStartAsync",
            () => new KubernetesViewModel(), vm => ((KubernetesViewModel)vm).StartKubernetesCommand.Run()),
        new ErrorCase("Runtime.UpdateColima", "UpdateAsync",
            () => new RuntimeViewModel(), vm => ((RuntimeViewModel)vm).UpdateColimaCommand.Run()),
        new ErrorCase("Containers.Create", "CreateContainerAsync",
            () => new ContainersViewModel { NewContainerName = "web", NewContainerImage = "nginx" },
            vm => ((ContainersViewModel)vm).CreateContainerCommand.Run()),
        new ErrorCase("Volumes.Create", "CreateVolumeAsync",
            () => new VolumesViewModel { NewVolumeName = "data" },
            vm => ((VolumesViewModel)vm).CreateVolumeCommand.Run()),
        new ErrorCase("Profiles.Clone", "CloneProfileAsync",
            () => new ProfilesViewModel { CloneSource = "a", CloneDestination = "b" },
            vm => ((ProfilesViewModel)vm).CloneProfileCommand.Run()),
    };

    [Fact]
    public async Task BackendFailureSurfacesAsAContextualErrorForEveryCommandGroup()
    {
        foreach (var c in ErrorCases())
        {
            var (client, _) = TestApp.Configure(Profile);
            client.FailingMethods.Add(c.FailingRpc);
            var vm = c.Make();

            await c.Invoke(vm);

            Assert.True(vm.HasError, $"{c.Name}: backend failure did not surface as an error");
            Assert.Contains("failed", vm.ErrorMessage, StringComparison.OrdinalIgnoreCase);
            Assert.False(vm.IsLoading, $"{c.Name}: loading state not cleared after failure");
        }
    }

    private static async Task WaitUntil(Func<bool> condition, int timeoutMs = 5000)
    {
        var sw = Stopwatch.StartNew();
        while (!condition())
        {
            if (sw.ElapsedMilliseconds > timeoutMs)
                throw new TimeoutException("Condition was not met within the timeout.");
            await Task.Delay(10);
        }
    }
}
