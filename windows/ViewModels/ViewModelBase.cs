using System;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ColimaDesktop.Windows.Services;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Base class for all view-models. Provides access to the shared
/// <see cref="DaemonClient"/>, <see cref="ConnectionSettings"/>,
/// and common loading/error state.
/// </summary>
public abstract partial class ViewModelBase : ObservableObject
{
    private readonly OperationGate _operationGate = new();

    protected IDaemonClient Client => App.DaemonClient;
    protected ConnectionSettings Settings => App.ConnectionSettings;

    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string _errorMessage = string.Empty;
    [ObservableProperty] private bool _hasError;

    /// <summary>
    /// The accessible confirmation prompt for destructive operations. The view (code-behind) sets
    /// this once to present a <see cref="Microsoft.UI.Xaml.Controls.ContentDialog"/> (via
    /// <c>DestructiveConfirmationDialog</c>); tests set it to a deterministic stub. It returns
    /// <c>true</c> only when the user explicitly confirms.
    /// <para/>
    /// Fail-closed by design: when this handler is <c>null</c> (not wired) or returns <c>false</c>
    /// (denied/dismissed), <see cref="RunDestructiveAsync"/> issues NO daemon RPC. This makes the
    /// "no destructive RPC without confirmation" guarantee hold at the RPC boundary regardless of
    /// how the command is invoked, and makes it headlessly testable.
    /// </summary>
    public Func<DestructiveAction, Task<bool>>? DestructiveConfirmationHandler { get; set; }

    /// <summary>Bindable refresh command delegating to <see cref="LoadAsync"/>.</summary>
    [RelayCommand]
    private Task Load() => LoadAsync();

    protected async Task RunAsync(Func<CancellationToken, Task> action, CancellationToken ct = default)
    {
        if (!_operationGate.TryEnter(out var lease))
        {
            ErrorMessage = "Another operation is already running. Wait for it to finish or cancel it first.";
            HasError = true;
            return;
        }

        using (lease)
        {
            IsLoading = true;
            ErrorMessage = string.Empty;
            HasError = false;
            try
            {
                await action(ct);
            }
            catch (OperationCanceledException)
            {
                ErrorMessage = "Operation cancelled.";
                HasError = true;
            }
            catch (Exception ex)
            {
                ErrorMessage = ex.Message;
                HasError = true;
            }
            finally
            {
                IsLoading = false;
            }
        }
    }

    /// <summary>
    /// Runs a destructive operation behind the accessible confirmation gate. The operation (which
    /// issues the daemon RPC) executes ONLY after <see cref="DestructiveConfirmationHandler"/>
    /// returns <c>true</c>; it then runs through <see cref="RunAsync"/> so it also gets the
    /// non-reentrant busy gate and error surfacing. Denying, dismissing, or having no handler wired
    /// issues no RPC (fail-closed), and a handler that throws surfaces as an error without running
    /// the operation.
    /// </summary>
    protected async Task RunDestructiveAsync(
        DestructiveAction action, Func<CancellationToken, Task> operation, CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(action);
        ArgumentNullException.ThrowIfNull(operation);

        bool confirmed;
        try
        {
            var handler = DestructiveConfirmationHandler;
            confirmed = handler is not null && await handler(action);
        }
        catch (Exception ex)
        {
            // A failure presenting the confirmation must never fall through to the RPC.
            ErrorMessage = ex.Message;
            HasError = true;
            return;
        }

        if (!confirmed)
            return; // denied, dismissed, or no handler wired → no destructive RPC (fail-closed)

        await RunAsync(operation, ct);
    }

    /// <summary>Called when the view becomes visible. Override to load data.</summary>
    public virtual Task LoadAsync(CancellationToken ct = default) => Task.CompletedTask;
}
