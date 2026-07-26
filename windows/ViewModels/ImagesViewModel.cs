using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ColimaDesktop.Windows.Services;

namespace ColimaDesktop.Windows.ViewModels;

/// <summary>
/// Images view: list/pull/remove/inspect/history/tag/push/search/prune.
/// CONTRACT Part B DockerService.
/// </summary>
public sealed partial class ImagesViewModel : ViewModelBase
{
    [ObservableProperty] private string _rawJson = string.Empty;
    [ObservableProperty] private string _detailJson = string.Empty;
    [ObservableProperty] private string _pullImageName = string.Empty;
    [ObservableProperty] private string _searchTerm = string.Empty;
    [ObservableProperty] private string _tagName = string.Empty;
    [ObservableProperty] private string _tagRepo = string.Empty;
    [ObservableProperty] private string _tagTag = string.Empty;
    [ObservableProperty] private string _progressMessage = string.Empty;
    [ObservableProperty] private float _progressValue;
    [ObservableProperty] private bool _isProgressVisible;

    public override Task LoadAsync(CancellationToken ct = default) =>
        RunAsync(LoadCoreAsync, ct);

    private async Task LoadCoreAsync(CancellationToken t)
    {
        await LoadCoreAsync(Settings.CaptureDockerTarget(), t);
    }

    private async Task LoadCoreAsync(DockerTarget target, CancellationToken t)
    {
        var resp = await Client.ListImagesAsync(target, t);
        RawJson = resp.Json;
    }

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task PullImageAsync(CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            IsProgressVisible = true;
            ProgressMessage = $"Pulling {PullImageName}…";
            ProgressValue = 0;
            var completed = false;
            try
            {
                var target = Settings.CaptureDockerTarget();
                using var call = Client.PullImageStream(PullImageName, target, token);
                await foreach (var rawEvent in call.ResponseStream.ReadAllAsync(token))
                {
                    var evt = DaemonResponse.EnsureProgress(rawEvent, "Pull image");
                    ProgressMessage = evt.Message;
                    ProgressValue = evt.Progress;
                    if (evt.Done) { completed = true; break; }
                }
                if (!completed)
                    throw new DaemonOperationException("Pull image", "the progress stream ended before completion");
                await LoadCoreAsync(target, token);
                PullImageName = string.Empty;
            }
            finally { IsProgressVisible = false; }
        }, ct);
    }

    [RelayCommand]
    private Task RemoveImageAsync(string id) =>
        RunDestructiveAsync(
            new DestructiveAction("RemoveImage", $"remove image {id}",
                $"Image '{id}' will be removed from the selected profile/provider.", "Remove"),
            async t =>
            {
                var target = Settings.CaptureDockerTarget();
                await Client.RemoveImageAsync(id, target, t);
                await LoadCoreAsync(target, t);
            });

    [RelayCommand]
    private Task InspectImageAsync(string name) =>
        RunAsync(async t =>
        {
            var resp = await Client.InspectImageAsync(name, Settings.CaptureDockerTarget(), t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ImageHistoryAsync(string name) =>
        RunAsync(async t =>
        {
            var resp = await Client.ImageHistoryAsync(name, Settings.CaptureDockerTarget(), t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task TagImageAsync() =>
        RunAsync(async t =>
        {
            var target = Settings.CaptureDockerTarget();
            await Client.TagImageAsync(TagName, TagRepo, TagTag, target, t);
            await LoadCoreAsync(target, t);
        });

    [RelayCommand(IncludeCancelCommand = true)]
    private async Task PushImageAsync(string name, CancellationToken ct = default)
    {
        await RunAsync(async token =>
        {
            IsProgressVisible = true;
            ProgressMessage = $"Pushing {name}…";
            ProgressValue = 0;
            var completed = false;
            try
            {
                using var call = Client.PushImageStream(name, Settings.CaptureDockerTarget(), token);
                await foreach (var rawEvent in call.ResponseStream.ReadAllAsync(token))
                {
                    var evt = DaemonResponse.EnsureProgress(rawEvent, "Push image");
                    ProgressMessage = evt.Message;
                    ProgressValue = evt.Progress;
                    if (evt.Done) { completed = true; break; }
                }
                if (!completed)
                    throw new DaemonOperationException("Push image", "the progress stream ended before completion");
            }
            finally { IsProgressVisible = false; }
        }, ct);
    }

    [RelayCommand]
    private Task SearchImagesAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.SearchImagesAsync(SearchTerm, Settings.CaptureDockerTarget(), t);
            RawJson = resp.Json;
        });

    [RelayCommand]
    private Task PruneImagesAsync() =>
        RunDestructiveAsync(
            new DestructiveAction("PruneImages", "prune unused images",
                "Unused images in the selected profile/provider will be removed.", "Prune"),
            async t =>
            {
                var target = Settings.CaptureDockerTarget();
                await Client.PruneImagesAsync(target, t);
                await LoadCoreAsync(target, t);
            });

    [RelayCommand]
    private void CancelTransfer()
    {
        PullImageCommand.Cancel();
        PushImageCommand.Cancel();
    }
}
