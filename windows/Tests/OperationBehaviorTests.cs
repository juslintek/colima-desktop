using ColimaDesktop.Windows.Services;
using ColimaDesktop.Windows.ViewModels;
using Colimaui;
using Xunit;

namespace ColimaDesktop.Windows.Tests;

public sealed class OperationBehaviorTests
{
    [Fact]
    public void FailedStatusResponseBecomesActionableException()
    {
        var error = Assert.Throws<DaemonOperationException>(() => DaemonResponse.EnsureSuccess(
            new StatusResponse { Success = false, Error = "permission denied" }, "Stop VM"));

        Assert.Equal("Stop VM", error.Operation);
        Assert.Contains("permission denied", error.Message);
    }

    [Fact]
    public void JsonErrorIsNotTreatedAsData()
    {
        var error = Assert.Throws<DaemonOperationException>(() => DaemonResponse.EnsureJson(
            new JsonResponse { Json = "[]", Error = "socket unavailable" }, "List containers"));

        Assert.Contains("socket unavailable", error.Message);
    }

    [Fact]
    public void ProgressErrorStopsTheOperation()
    {
        Assert.Throws<DaemonOperationException>(() => DaemonResponse.EnsureProgress(
            new ProgressEvent { Done = true, Error = "pull interrupted" }, "Pull image"));
    }

    [Fact]
    public void OperationGateReportsBusyUntilLeaseIsReleased()
    {
        var gate = new OperationGate();

        Assert.True(gate.TryEnter(out var first));
        Assert.True(gate.IsBusy);
        Assert.False(gate.TryEnter(out _));

        first.Dispose();
        Assert.False(gate.IsBusy);
        Assert.True(gate.TryEnter(out var second));
        second.Dispose();
    }

    [Fact]
    public void StreamLifetimeCancelsAndDisposeIsIdempotent()
    {
        var lifetime = new StreamLifetime();
        var observed = false;
        using var registration = lifetime.Token.Register(() => observed = true);

        lifetime.Cancel();
        lifetime.Dispose();
        lifetime.Dispose();

        Assert.True(lifetime.IsCancellationRequested);
        Assert.True(observed);
    }

    [Theory]
    [InlineData(ConfirmationChoice.Cancel, false)]
    [InlineData(ConfirmationChoice.Confirm, true)]
    public void DestructiveActionRunsOnlyAfterConfirmation(ConfirmationChoice choice, bool expected)
    {
        Assert.Equal(expected, DestructiveConfirmation.ShouldExecute(choice));
    }

    [Fact]
    public async Task ViewModelReportsBusyInsteadOfStartingConcurrentOperation()
    {
        var viewModel = new TestViewModel();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var first = viewModel.ExecuteAsync(async _ =>
        {
            entered.SetResult();
            await release.Task;
        });
        await entered.Task;

        await viewModel.ExecuteAsync(_ => Task.CompletedTask);

        Assert.True(viewModel.HasError);
        Assert.Contains("already running", viewModel.ErrorMessage);
        release.SetResult();
        await first;
        Assert.False(viewModel.IsLoading);
    }

    [Fact]
    public async Task ViewModelMakesCancellationVisible()
    {
        var viewModel = new TestViewModel();
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();

        await viewModel.ExecuteAsync(_ => Task.FromCanceled(cancelled.Token));

        Assert.True(viewModel.HasError);
        Assert.Equal("Operation cancelled.", viewModel.ErrorMessage);
    }

    // ─── Bounded streamed output (Requirement 5.3 — Docker event/log/stat streams) ───────────

    [Fact]
    public void StreamOutputPreservesNewlineJoinedContentUnderBound()
    {
        var text = StreamOutput.AppendBounded(string.Empty, "first");
        text = StreamOutput.AppendBounded(text, "second");
        Assert.Equal("first\nsecond", text);
    }

    [Fact]
    public void StreamOutputTruncatesSingleOversizedFrameToBound()
    {
        var text = StreamOutput.AppendBounded(string.Empty, new string('x', 500), maxCharacters: 50);
        Assert.Equal(50, text.Length);
        Assert.Equal(new string('x', 50), text);
    }

    [Fact]
    public void StreamOutputKeepsMostRecentTailWhenCombinedExceedsBound()
    {
        var text = StreamOutput.AppendBounded(new string('a', 50), "TAIL", maxCharacters: 50);
        Assert.Equal(50, text.Length);
        Assert.EndsWith("TAIL", text);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(-1000)]
    public void StreamOutputRejectsNonPositiveBound(int bound)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => StreamOutput.AppendBounded("a", "b", bound));
    }

    [Fact]
    public void StreamOutputNeverExceedsBoundAndKeepsMostRecentTail()
    {
        // Property (Requirement 5.3 — bound streamed output): for ANY sequence of appended Docker
        // stream frames, the retained text never exceeds the bound and is always the most-recent
        // tail of the full concatenated stream — so a long-running stream cannot grow without limit.
        const int bound = 1_000;
        var rng = new Random(5303);
        for (var iteration = 0; iteration < 250; iteration++)
        {
            var retained = string.Empty;
            var full = string.Empty;
            var frames = rng.Next(1, 40);
            for (var f = 0; f < frames; f++)
            {
                var frame = new string((char)('a' + rng.Next(0, 26)), rng.Next(0, 300));
                full = full.Length == 0 ? frame : full + "\n" + frame;
                retained = StreamOutput.AppendBounded(retained, frame, bound);
                Assert.True(retained.Length <= bound);
            }
            var expectedTail = full.Length <= bound ? full : full[^bound..];
            Assert.Equal(expectedTail, retained);
        }
    }

    // ─── Bounded streamed output — no-separator concatenation (Requirement 5.4 — AI ModelRun) ────

    [Fact]
    public void StreamOutputConcatenatesWithoutSeparatorWhenRequested()
    {
        // AIWorkloadsViewModel.RunModelAsync bounds RunOutput with separator: string.Empty so
        // model-token fragments concatenate directly (identical to the old `RunOutput += evt.Message`).
        var text = StreamOutput.AppendBounded(string.Empty, "Hel", separator: string.Empty);
        text = StreamOutput.AppendBounded(text, "lo, ", separator: string.Empty);
        text = StreamOutput.AppendBounded(text, "world", separator: string.Empty);
        Assert.Equal("Hello, world", text);
    }

    [Fact]
    public void StreamOutputNoSeparatorKeepsMostRecentTailWithoutInjectingNewlines()
    {
        var text = StreamOutput.AppendBounded(new string('a', 50), "TAIL", maxCharacters: 50, separator: string.Empty);
        Assert.Equal(50, text.Length);
        Assert.EndsWith("TAIL", text);
        Assert.DoesNotContain('\n', text);
    }

    [Fact]
    public void StreamOutputNoSeparatorNeverExceedsBoundAndKeepsMostRecentTail()
    {
        // Property (Requirement 5.4 — AI ModelRun output): for ANY sequence of appended model-token
        // fragments, the retained text never exceeds the bound and is always the most-recent tail of
        // the full DIRECTLY-concatenated stream (no injected separators) — so a long model run can
        // never grow the retained UI text without limit.
        const int bound = 1_000;
        var rng = new Random(5404);
        for (var iteration = 0; iteration < 250; iteration++)
        {
            var retained = string.Empty;
            var full = string.Empty;
            var frames = rng.Next(1, 40);
            for (var f = 0; f < frames; f++)
            {
                var frame = new string((char)('a' + rng.Next(0, 26)), rng.Next(0, 300));
                full += frame;
                retained = StreamOutput.AppendBounded(retained, frame, bound, separator: string.Empty);
                Assert.True(retained.Length <= bound);
            }
            var expectedTail = full.Length <= bound ? full : full[^bound..];
            Assert.Equal(expectedTail, retained);
        }
    }

    private sealed class TestViewModel : ViewModelBase
    {
        public Task ExecuteAsync(Func<CancellationToken, Task> action) => RunAsync(action);
    }
}
