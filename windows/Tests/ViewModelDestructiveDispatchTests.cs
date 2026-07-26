using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using ColimaDesktop.Windows.Tests.Fakes;
using ColimaDesktop.Windows.ViewModels;
using Xunit;

namespace ColimaDesktop.Windows.Tests;

/// <summary>
/// Property 13 (destructive-action confirmation gate) applied to every real destructive view-model
/// command on the Windows frontend. The base <c>ViewModelBase.RunDestructiveAsync</c> gate is unit-
/// tested in <see cref="DestructiveConfirmationGateTests"/>; here we prove each concrete destructive
/// <c>[RelayCommand]</c> actually routes through that gate: denying issues NO daemon RPC (fail-
/// closed), and confirming issues exactly the mapped Frozen_Contract RPC. This closes the gap that
/// no per-view-model destructive-command coverage existed.
/// <para/>
/// Feature: cross-platform-live-verification, Property 13.
/// </summary>
[Trait("Feature", "cross-platform-live-verification")]
[Trait("Property", "13")]
public sealed class ViewModelDestructiveDispatchTests
{
    private const string Profile = TestApp.DefaultProfile;

    /// <summary>A destructive command: how to build its view-model, invoke it, and the RPC it maps to.</summary>
    private sealed record Case(string Name, string MappedRpc, Func<ViewModelBase> Make, Func<ViewModelBase, Task> Invoke);

    private static IReadOnlyList<Case> AllCases() => new[]
    {
        new Case("Dashboard.Delete", "DeleteAsync",
            () => new DashboardViewModel(), vm => ((DashboardViewModel)vm).DeleteCommand.Run(false)),
        new Case("Kubernetes.Reset", "KubernetesResetAsync",
            () => new KubernetesViewModel(), vm => ((KubernetesViewModel)vm).ResetKubernetesCommand.Run()),
        new Case("Runtime.Prune", "PruneAsync",
            () => new RuntimeViewModel(), vm => ((RuntimeViewModel)vm).PruneCommand.Run(false)),
        new Case("Runtime.PruneAll", "PruneAsync",
            () => new RuntimeViewModel(), vm => ((RuntimeViewModel)vm).PruneCommand.Run(true)),
        new Case("Monitoring.Kill", "KillProcessAsync",
            () => new MonitoringViewModel(), vm => ((MonitoringViewModel)vm).KillProcessCommand.Run(4321)),
        new Case("Profiles.Delete", "DeleteProfileAsync",
            () => new ProfilesViewModel(), vm => ((ProfilesViewModel)vm).DeleteProfileCommand.Run("victim")),
        new Case("Containers.Kill", "ContainerActionAsync",
            () => new ContainersViewModel(), vm => ((ContainersViewModel)vm).KillContainerCommand.Run("c1")),
        new Case("Containers.Remove", "ContainerActionAsync",
            () => new ContainersViewModel(), vm => ((ContainersViewModel)vm).RemoveContainerCommand.Run("c1")),
        new Case("Containers.Prune", "PruneContainersAsync",
            () => new ContainersViewModel(), vm => ((ContainersViewModel)vm).PruneContainersCommand.Run()),
        new Case("Images.Remove", "RemoveImageAsync",
            () => new ImagesViewModel(), vm => ((ImagesViewModel)vm).RemoveImageCommand.Run("img")),
        new Case("Images.Prune", "PruneImagesAsync",
            () => new ImagesViewModel(), vm => ((ImagesViewModel)vm).PruneImagesCommand.Run()),
        new Case("Volumes.Remove", "RemoveVolumeAsync",
            () => new VolumesViewModel(), vm => ((VolumesViewModel)vm).RemoveVolumeCommand.Run("vol")),
        new Case("Volumes.Prune", "PruneVolumesAsync",
            () => new VolumesViewModel(), vm => ((VolumesViewModel)vm).PruneVolumesCommand.Run()),
        new Case("Networks.Remove", "RemoveNetworkAsync",
            () => new NetworksViewModel(), vm => ((NetworksViewModel)vm).RemoveNetworkCommand.Run("net")),
        new Case("Networks.Prune", "PruneNetworksAsync",
            () => new NetworksViewModel(), vm => ((NetworksViewModel)vm).PruneNetworksCommand.Run()),
    };

    [Fact]
    public async Task DeniedConfirmationIssuesNoRpcForAnyDestructiveCommand()
    {
        foreach (var c in AllCases())
        {
            var (client, _) = TestApp.Configure(Profile);
            var vm = c.Make();
            vm.DestructiveConfirmationHandler = _ => Task.FromResult(false); // user dismisses

            await c.Invoke(vm);

            // Fail-closed: a denied destructive command must not reach the daemon at all — not the
            // destructive RPC, not even the follow-up refresh.
            Assert.False(vm.HasError, $"{c.Name}: dismissing a confirmation is a normal outcome, not an error");
            Assert.Equal(0, client.CallCount);
            Assert.False(client.Invoked(c.MappedRpc), $"{c.Name}: destructive RPC issued despite denial");
        }
    }

    [Fact]
    public async Task NoConfirmationHandlerIsFailClosedForAnyDestructiveCommand()
    {
        foreach (var c in AllCases())
        {
            var (client, _) = TestApp.Configure(Profile);
            var vm = c.Make();
            vm.DestructiveConfirmationHandler = null; // view never wired a confirmation surface

            await c.Invoke(vm);

            Assert.Equal(0, client.CallCount);
            Assert.False(client.Invoked(c.MappedRpc), $"{c.Name}: destructive RPC issued with no confirmation handler");
        }
    }

    [Fact]
    public async Task ConfirmedConfirmationIssuesExactlyTheMappedDestructiveRpc()
    {
        foreach (var c in AllCases())
        {
            var (client, _) = TestApp.Configure(Profile);
            var vm = c.Make();
            vm.DestructiveConfirmationHandler = _ => Task.FromResult(true); // user confirms

            await c.Invoke(vm);

            Assert.False(vm.HasError, $"{c.Name}: confirmed destructive command surfaced an unexpected error");
            // Single(...) throws unless the mapped RPC was invoked exactly once.
            var call = client.Single(c.MappedRpc);
            Assert.Equal(c.MappedRpc, call.Method);
        }
    }

    [Fact]
    public async Task RpcIssuedIffConfirmed_AcrossRandomDestructiveDecisions()
    {
        // Property 13 (randomized): for ANY destructive command and ANY confirm/deny decision, the
        // mapped RPC is issued if and only if the decision was to confirm.
        var cases = AllCases();
        var rng = new Random(1313);
        for (var i = 0; i < 200; i++)
        {
            var c = cases[rng.Next(cases.Count)];
            var confirm = rng.Next(2) == 0;

            var (client, _) = TestApp.Configure(Profile);
            var vm = c.Make();
            vm.DestructiveConfirmationHandler = _ => Task.FromResult(confirm);

            await c.Invoke(vm);

            Assert.Equal(confirm, client.Invoked(c.MappedRpc));
            if (!confirm)
                Assert.Equal(0, client.CallCount);
        }
    }
}
