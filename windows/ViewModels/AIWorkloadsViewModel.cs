using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ColimaDesktop.Windows.Services;

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
    // NumberBox.Value is double; cast to int when using as a port number.
    [ObservableProperty] private double _servePort = 8080;
    [ObservableProperty] private string _progressMessage = string.Empty;
    [ObservableProperty] private float _progressValue;
    [ObservableProperty] private bool _isProgressVisible;
    [ObservableProperty] private string _runOutput = string.Empty;
    [ObservableProperty] private string _statusMessage = string.Empty;

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task SetupModelAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            IsProgressVisible = true;
            ProgressMessage = $"Setting up {Runner}…";
            ProgressValue = 0;
            RunOutput = string.Empty;
            var completed = false;
            try
            {
                using var call = Client.ModelSetupStream(Settings.ActiveProfile, Runner, token);
                await foreach (var rawEvent in call.ResponseStream.ReadAllAsync(token))
                {
                    var evt = DaemonResponse.EnsureProgress(rawEvent, "Set up model runner");
                    ProgressMessage = evt.Message;
                    ProgressValue = evt.Progress;
                    if (evt.Done) { completed = true; break; }
                }
                if (!completed)
                    throw new DaemonOperationException("Set up model runner", "the progress stream ended before completion");
                StatusMessage = "Model runner setup complete.";
            }
            finally { IsProgressVisible = false; }
        }, ct);
    }

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task RunModelAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            IsProgressVisible = true;
            ProgressMessage = $"Running {ModelName}…";
            ProgressValue = 0;
            RunOutput = string.Empty;
            var completed = false;
            try
            {
                using var call = Client.ModelRunStream(Settings.ActiveProfile, ModelName, Runner, Prompt, token);
                await foreach (var rawEvent in call.ResponseStream.ReadAllAsync(token))
                {
                    var evt = DaemonResponse.EnsureProgress(rawEvent, "Run model");
                    // Bound the accumulated model output so a long run cannot grow the retained UI
                    // text without limit. Empty separator: model-token fragments concatenate directly
                    // (identical rendering to `+=` for any run under the bound).
                    RunOutput = StreamOutput.AppendBounded(RunOutput, evt.Message, separator: string.Empty);
                    ProgressValue = evt.Progress;
                    if (evt.Done) { completed = true; break; }
                }
                if (!completed)
                    throw new DaemonOperationException("Run model", "the progress stream ended before completion");
            }
            finally { IsProgressVisible = false; }
        }, ct);
    }

    [RelayCommand]
    private Task ServeModelAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.ModelServeAsync(Settings.ActiveProfile, ModelName, Runner, (int)ServePort, t);
            StatusMessage = resp.Success ? $"Serving on port {(int)ServePort}" : $"Error: {resp.Error}";
        });

    [RelayCommand]
    private Task StopModelAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.ModelStopAsync(Settings.ActiveProfile, t);
            StatusMessage = resp.Success ? "Model stopped." : $"Error: {resp.Error}";
        });

    [RelayCommand]
    private void CancelModelOperation()
    {
        SetupModelCommand.Cancel();
        RunModelCommand.Cancel();
    }
}
