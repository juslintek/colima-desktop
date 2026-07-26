using System;
using System.Threading;
using System.Threading.Tasks;
using Colimaui;

namespace ColimaDesktop.Windows.Services;

public sealed class DaemonOperationException : Exception
{
    public DaemonOperationException(string operation, string detail)
        : base($"{operation} failed: {NormalizeDetail(detail)}")
    {
        Operation = operation;
    }

    public string Operation { get; }

    private static string NormalizeDetail(string detail) =>
        string.IsNullOrWhiteSpace(detail) ? "the daemon did not provide an error message" : detail.Trim();
}

/// <summary>Central validation for application-level failures returned with an OK gRPC status.</summary>
public static class DaemonResponse
{
    public static StatusResponse EnsureSuccess(StatusResponse response, string operation)
    {
        ArgumentNullException.ThrowIfNull(response);
        if (!response.Success)
            throw new DaemonOperationException(operation, response.Error);
        return response;
    }

    public static JsonResponse EnsureJson(JsonResponse response, string operation)
    {
        ArgumentNullException.ThrowIfNull(response);
        if (!string.IsNullOrWhiteSpace(response.Error))
            throw new DaemonOperationException(operation, response.Error);
        return response;
    }

    public static ProgressEvent EnsureProgress(ProgressEvent response, string operation)
    {
        ArgumentNullException.ThrowIfNull(response);
        if (!string.IsNullOrWhiteSpace(response.Error))
            throw new DaemonOperationException(operation, response.Error);
        return response;
    }

    public static KubeExecResponse EnsureKubeExec(KubeExecResponse response, string operation)
    {
        ArgumentNullException.ThrowIfNull(response);
        if (response.ExitCode != 0 || !string.IsNullOrWhiteSpace(response.Error))
            throw new DaemonOperationException(operation,
                string.IsNullOrWhiteSpace(response.Error) ? $"kubectl exited with code {response.ExitCode}" : response.Error);
        return response;
    }
}

/// <summary>A deterministic non-reentrant gate shared by view-model operations.</summary>
public sealed class OperationGate
{
    private int _entered;

    public bool IsBusy => Volatile.Read(ref _entered) != 0;

    public bool TryEnter(out IDisposable lease)
    {
        if (Interlocked.CompareExchange(ref _entered, 1, 0) != 0)
        {
            lease = EmptyLease.Instance;
            return false;
        }

        lease = new Lease(this);
        return true;
    }

    private sealed class Lease(OperationGate owner) : IDisposable
    {
        private OperationGate? _owner = owner;

        public void Dispose()
        {
            var current = Interlocked.Exchange(ref _owner, null);
            if (current is not null)
                Volatile.Write(ref current._entered, 0);
        }
    }

    private sealed class EmptyLease : IDisposable
    {
        public static EmptyLease Instance { get; } = new();
        public void Dispose() { }
    }
}

/// <summary>Owns cancellation for one long-running stream and makes disposal observable in tests.</summary>
public sealed class StreamLifetime : IDisposable
{
    private readonly CancellationTokenSource _source = new();
    private int _disposed;

    public CancellationToken Token => _source.Token;
    public bool IsCancellationRequested => _source.IsCancellationRequested;

    public void Cancel()
    {
        if (Volatile.Read(ref _disposed) == 0)
            _source.Cancel();
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
            return;
        _source.Cancel();
        _source.Dispose();
    }
}

/// <summary>
/// Bounds accumulated streamed output (Docker event/log/stat streams) so a long-running stream can
/// never grow the retained text without limit. Retains the most recent <c>maxCharacters</c>
/// characters, which is what the UI shows.
/// </summary>
public static class StreamOutput
{
    /// <summary>Default cap on retained streamed-output characters.</summary>
    public const int DefaultMaxCharacters = 200_000;

    /// <summary>
    /// Appends <paramref name="next"/> to <paramref name="current"/> (joined with
    /// <paramref name="separator"/> when <paramref name="current"/> is non-empty) and truncates the
    /// result to the most recent <paramref name="maxCharacters"/> characters, so bounded streamed
    /// output never exceeds the limit regardless of how much the backend emits.
    /// <paramref name="separator"/> defaults to a newline (Docker event/log/stat frames are discrete
    /// lines); pass <see cref="string.Empty"/> for streams whose frames concatenate directly (e.g.
    /// the AI model-run token stream).
    /// </summary>
    public static string AppendBounded(
        string current, string next, int maxCharacters = DefaultMaxCharacters, string separator = "\n")
    {
        if (maxCharacters <= 0)
            throw new ArgumentOutOfRangeException(nameof(maxCharacters), "The output bound must be positive.");
        current ??= string.Empty;
        next ??= string.Empty;
        separator ??= string.Empty;
        var combined = current.Length == 0 ? next : $"{current}{separator}{next}";
        return combined.Length <= maxCharacters ? combined : combined[^maxCharacters..];
    }
}

public enum ConfirmationChoice
{
    Cancel,
    Confirm
}

public static class DestructiveConfirmation
{
    public static bool ShouldExecute(ConfirmationChoice choice) => choice == ConfirmationChoice.Confirm;
}

/// <summary>
/// Describes a destructive operation for the accessible confirmation gate. Carries everything the
/// UI needs to present an accessible confirmation (<see cref="ContentDialog"/> via
/// <c>DestructiveConfirmationDialog</c>): a stable <see cref="ActionId"/> (used for the dialog's
/// <c>AutomationProperties.AutomationId</c> = <c>Confirm{ActionId}Dialog</c>), a human-readable
/// <see cref="Title"/> and <see cref="Message"/>, and the primary-button <see cref="ConfirmLabel"/>.
/// The view-model constructs this and hands it to <see cref="object"/>-free
/// <c>ViewModelBase.DestructiveConfirmationHandler</c>, so the confirmation requirement is enforced
/// at the RPC boundary (fail-closed) rather than only in view code-behind.
/// </summary>
public sealed record DestructiveAction(string ActionId, string Title, string Message, string ConfirmLabel)
{
    /// <summary>The stable AutomationId a confirmation dialog should expose for UIA targeting.</summary>
    public string DialogAutomationId => $"Confirm{ActionId}Dialog";
}
