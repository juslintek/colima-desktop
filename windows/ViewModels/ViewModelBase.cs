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
    protected DaemonClient Client => App.DaemonClient;
    protected ConnectionSettings Settings => App.ConnectionSettings;

    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string _errorMessage = string.Empty;
    [ObservableProperty] private bool _hasError;

    /// <summary>Bindable refresh command delegating to <see cref="LoadAsync"/>.</summary>
    [RelayCommand]
    private Task Load() => LoadAsync();

    protected async Task RunAsync(Func<CancellationToken, Task> action, CancellationToken ct = default)
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
            // Silently ignore cancellation
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

    /// <summary>Called when the view becomes visible. Override to load data.</summary>
    public virtual Task LoadAsync(CancellationToken ct = default) => Task.CompletedTask;
}
