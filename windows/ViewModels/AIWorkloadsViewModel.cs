using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// AI Workloads view: model setup/pull, run (streaming), serve, stop.
/// CONTRACT Part A ModelSetup/ModelRun/ModelServe/ModelStop.
/// </summary>
public sealed partial class AIWorkloadsViewModel : ViewModelBase
{
    [ObservableProperty] private string _modelName = string.Empty;
    [ObservableProperty] private string _runner = "docker";
    [ObservableProperty] private string _prompt = string.Empty;
    [ObservableProperty] private int _servePort = 8080;
    [ObservableProperty] private string _progressMessage = string.Empty;
    [ObservableProperty] private float _progressValue;
    [ObservableProperty] private bool _isProgressVisible;
    [ObservableProperty] private string _runOutput = string.Empty;
    [ObservableProperty] private string _statusMessage = string.Empty;

    [RelayCommand]
    private async Task SetupModelAsync(CancellationToken ct = default)
    {
        IsProgressVisible = true;
        ProgressMessage = $"Setting up {ModelName}…";
        ProgressValue = 0;
        RunOutput = string.Empty;
        try
        {
            using var call = Client.ModelSetupStream(Settings.ActiveProfile, Runner);
            await foreach (var evt in call.ResponseStream.ReadAllAsync(ct))
            {
                ProgressMessage = evt.Message;
                ProgressValue = evt.Progress;
                if (evt.Done) break;
            }
            StatusMessage = "Model setup complete.";
        }
        catch (Exception ex) { StatusMessage = $"Error: {ex.Message}"; }
        finally { IsProgressVisible = false; }
    }

    [RelayCommand]
    private async Task RunModelAsync(CancellationToken ct = default)
    {
        IsProgressVisible = true;
        ProgressMessage = $"Running {ModelName}…";
        ProgressValue = 0;
        RunOutput = string.Empty;
        try
        {
            using var call = Client.ModelRunStream(Settings.ActiveProfile, ModelName, Runner, Prompt);
            await foreach (var evt in call.ResponseStream.ReadAllAsync(ct))
            {
                RunOutput += evt.Message;
                ProgressValue = evt.Progress;
                if (evt.Done) break;
            }
        }
        catch (Exception ex) { StatusMessage = $"Error: {ex.Message}"; }
        finally { IsProgressVisible = false; }
    }

    [RelayCommand]
    private Task ServeModelAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.ModelServeAsync(Settings.ActiveProfile, ModelName, Runner, ServePort, t);
            StatusMessage = resp.Success ? $"Serving on port {ServePort}" : $"Error: {resp.Error}";
        });

    [RelayCommand]
    private Task StopModelAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.ModelStopAsync(Settings.ActiveProfile, t);
            StatusMessage = resp.Success ? "Model stopped." : $"Error: {resp.Error}";
        });
}
