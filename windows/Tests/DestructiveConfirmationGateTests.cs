using ColimaDesktop.Windows.Services;
using ColimaDesktop.Windows.ViewModels;
using Xunit;

namespace ColimaDesktop.Windows.Tests;

/// <summary>
/// Property 13 (destructive-action confirmation gate) + Property 16 interplay for the Windows
/// frontend. Exercises <c>ViewModelBase.RunDestructiveAsync</c> — the single, fail-closed gate every
/// destructive view-model command routes through — so "no destructive RPC without an explicit
/// confirmation" is asserted at the RPC boundary, headlessly, independent of the WinUI dialog.
/// Feature: cross-platform-live-verification, Property 13; Property 16.
/// </summary>
[Trait("Feature", "cross-platform-live-verification")]
public sealed class DestructiveConfirmationGateTests
{
    private static readonly DestructiveAction SampleAction =
        new("RemoveContainer", "remove container c1", "Container 'c1' will be removed.", "Remove");

    // A view-model exposing the protected gate + a scriptable confirmation handler and an operation
    // that records whether (and how often) the destructive RPC-equivalent actually ran.
    private sealed class GateViewModel : ViewModelBase
    {
        public int OperationRuns;

        public Task RunDestructive(DestructiveAction action, Func<CancellationToken, Task>? op = null) =>
            RunDestructiveAsync(action, op ?? (_ =>
            {
                Interlocked.Increment(ref OperationRuns);
                return Task.CompletedTask;
            }));
    }

    [Trait("Property", "13")]
    [Fact]
    public async Task ConfirmedActionRunsTheOperationExactlyOnce()
    {
        var vm = new GateViewModel { DestructiveConfirmationHandler = _ => Task.FromResult(true) };

        await vm.RunDestructive(SampleAction);

        Assert.Equal(1, vm.OperationRuns);
        Assert.False(vm.HasError);
    }

    [Trait("Property", "13")]
    [Fact]
    public async Task DeniedConfirmationIssuesNoOperationAndNoError()
    {
        var vm = new GateViewModel { DestructiveConfirmationHandler = _ => Task.FromResult(false) };

        await vm.RunDestructive(SampleAction);

        Assert.Equal(0, vm.OperationRuns);
        Assert.False(vm.HasError); // dismissing is a normal outcome, not an error
    }

    [Trait("Property", "13")]
    [Fact]
    public async Task NoConfirmationHandlerIsFailClosed()
    {
        // A destructive command whose view never wired a confirmation handler must NOT fire the RPC.
        var vm = new GateViewModel { DestructiveConfirmationHandler = null };

        await vm.RunDestructive(SampleAction);

        Assert.Equal(0, vm.OperationRuns);
    }

    [Trait("Property", "13")]
    [Fact]
    public async Task ConfirmationThatThrowsDoesNotRunTheOperationAndSurfacesError()
    {
        var vm = new GateViewModel
        {
            DestructiveConfirmationHandler = _ => throw new InvalidOperationException("dialog failed")
        };

        await vm.RunDestructive(SampleAction);

        Assert.Equal(0, vm.OperationRuns);
        Assert.True(vm.HasError);
        Assert.Contains("dialog failed", vm.ErrorMessage);
    }

    [Trait("Property", "13")]
    [Fact]
    public void DestructiveActionExposesStableAccessibleDialogId()
    {
        // The dialog id is the stable AutomationId UIA targets for the confirmation surface.
        Assert.Equal("ConfirmRemoveContainer" + "Dialog", SampleAction.DialogAutomationId);
        Assert.Equal("ConfirmDeleteVmDialog", new DestructiveAction("DeleteVm", "t", "m", "c").DialogAutomationId);
    }

    [Trait("Property", "13")]
    [Fact]
    public async Task OperationRunCountAlwaysEqualsConfirmCountAcrossRandomDecisions()
    {
        // Property: for ANY sequence of confirm/deny decisions, the destructive operation runs
        // exactly as many times as it was confirmed — never on a denial, never without a decision.
        var rng = new Random(51316);
        for (var iteration = 0; iteration < 200; iteration++)
        {
            var confirm = rng.Next(2) == 0;
            var vm = new GateViewModel { DestructiveConfirmationHandler = _ => Task.FromResult(confirm) };

            await vm.RunDestructive(SampleAction);

            Assert.Equal(confirm ? 1 : 0, vm.OperationRuns);
        }
    }

    [Trait("Property", "16")]
    [Fact]
    public async Task ConfirmedDestructiveOperationIsNonReentrant()
    {
        // Property 16 interplay: even after BOTH confirmations pass, a second destructive operation
        // launched while the first is in-flight is blocked by the busy gate — so it never issues a
        // concurrent RPC.
        var vm = new GateViewModel { DestructiveConfirmationHandler = _ => Task.FromResult(true) };
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        var first = vm.RunDestructive(SampleAction, async _ =>
        {
            Interlocked.Increment(ref vm.OperationRuns);
            entered.SetResult();
            await release.Task;
        });
        await entered.Task;

        // Second confirmed destructive op while the first holds the gate.
        await vm.RunDestructive(SampleAction);

        Assert.Equal(1, vm.OperationRuns);       // the second operation never ran
        Assert.True(vm.HasError);
        Assert.Contains("already running", vm.ErrorMessage);

        release.SetResult();
        await first;
        Assert.False(vm.IsLoading);
    }
}
