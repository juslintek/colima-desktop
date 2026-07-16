using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

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
        RunAsync(async t =>
        {
            var resp = await Client.ListImagesAsync(Settings.ActiveProfile, Settings.UseWsl2, t);
            RawJson = resp.Json;
        }, ct);

    [RelayCommand]
    private async Task PullImageAsync(CancellationToken ct = default)
    {
        IsProgressVisible = true;
        ProgressMessage = $"Pulling {PullImageName}…";
        ProgressValue = 0;
        try
        {
            using var call = Client.PullImageStream(PullImageName, Settings.ActiveProfile, Settings.UseWsl2);
            await foreach (var evt in call.ResponseStream.ReadAllAsync(ct))
            {
                ProgressMessage = evt.Message;
                ProgressValue = evt.Progress;
                if (evt.Done) break;
            }
            await LoadAsync(ct);
        }
        finally
        {
            IsProgressVisible = false;
            PullImageName = string.Empty;
        }
    }

    [RelayCommand]
    private Task RemoveImageAsync(string id) =>
        RunAsync(async t =>
        {
            await Client.RemoveImageAsync(id, Settings.ActiveProfile, Settings.UseWsl2, t);
            await LoadAsync(t);
        });

    [RelayCommand]
    private Task InspectImageAsync(string name) =>
        RunAsync(async t =>
        {
            var resp = await Client.InspectImageAsync(name, Settings.ActiveProfile, Settings.UseWsl2, t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task ImageHistoryAsync(string name) =>
        RunAsync(async t =>
        {
            var resp = await Client.ImageHistoryAsync(name, Settings.ActiveProfile, Settings.UseWsl2, t);
            DetailJson = resp.Json;
        });

    [RelayCommand]
    private Task TagImageAsync() =>
        RunAsync(async t =>
        {
            await Client.TagImageAsync(TagName, TagRepo, TagTag, Settings.ActiveProfile, t);
            await LoadAsync(t);
        });

    [RelayCommand]
    private async Task PushImageAsync(string name, CancellationToken ct = default)
    {
        IsProgressVisible = true;
        ProgressMessage = $"Pushing {name}…";
        ProgressValue = 0;
        try
        {
            using var call = Client.PushImageStream(name, Settings.ActiveProfile, Settings.UseWsl2);
            await foreach (var evt in call.ResponseStream.ReadAllAsync(ct))
            {
                ProgressMessage = evt.Message;
                ProgressValue = evt.Progress;
                if (evt.Done) break;
            }
        }
        finally { IsProgressVisible = false; }
    }

    [RelayCommand]
    private Task SearchImagesAsync() =>
        RunAsync(async t =>
        {
            var resp = await Client.SearchImagesAsync(SearchTerm, Settings.ActiveProfile, t);
            RawJson = resp.Json;
        });

    [RelayCommand]
    private Task PruneImagesAsync() =>
        RunAsync(async t =>
        {
            await Client.PruneImagesAsync(Settings.ActiveProfile, Settings.UseWsl2, t);
            await LoadAsync(t);
        });
}
