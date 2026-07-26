using System;
using System.Threading;
using System.Threading.Tasks;
using Grpc.Core;
using Grpc.Net.Client;
using Colimaui; // generated namespace from colima_ui.proto (package colimaui)

namespace ColimaDesktop.Windows.Services;

/// <summary>
/// gRPC client for the colima-desktop daemon. On Windows the daemon is reached over
/// TCP (remote colima/Lima host via SSH tunnel) or a local WSL2/Docker-backed daemon.
/// All callers go through this single client; the ConnectionSettings property can be
/// swapped at runtime to switch backends (triggers re-connect on next call).
/// </summary>
public sealed class DaemonClient : IDaemonClient
{
    private GrpcChannel? _channel;
    private string _currentAddress = string.Empty;
    private readonly object _lock = new();

    public ColimaService.ColimaServiceClient Colima => GetOrCreateClients().colima;
    public DockerService.DockerServiceClient Docker => GetOrCreateClients().docker;

    public DaemonClient(string address = "http://127.0.0.1:50051")
    {
        _currentAddress = DaemonEndpoint.RequireLoopback(address);
    }

    public string CurrentAddress
    {
        get { lock (_lock) return _currentAddress; }
    }

    /// <summary>Re-connects to a new daemon address (e.g. when switching remote/WSL2).</summary>
    public void Reconnect(string address)
    {
        address = DaemonEndpoint.RequireLoopback(address);
        lock (_lock)
        {
            if (_currentAddress == address) return;
            _channel?.Dispose();
            _channel = null;
            _currentAddress = address;
        }
    }

    // ─── ColimaService helpers ───────────────────────────────────────────────

    public Task<VMStatus> StatusAsync(string profile, CancellationToken ct = default) =>
        Colima.StatusAsync(new StatusRequest { Profile = ConnectionSettings.NormalizeProfile(profile) }, cancellationToken: ct).ResponseAsync;

    public Task<ProfileList> ListProfilesAsync(CancellationToken ct = default) =>
        Colima.ListProfilesAsync(new Empty(), cancellationToken: ct).ResponseAsync;

    public Task<MachineList> ListMachinesAsync(CancellationToken ct = default) =>
        Colima.ListMachinesAsync(new Empty(), cancellationToken: ct).ResponseAsync;

    public Task<VersionResponse> VersionAsync(CancellationToken ct = default) =>
        Colima.VersionAsync(new Empty(), cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> StopAsync(string profile, bool force = false, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.StopAsync(
            new StopRequest { Profile = ConnectionSettings.NormalizeProfile(profile), Force = force },
            cancellationToken: ct).ResponseAsync, "Stop VM");

    public Task<StatusResponse> DeleteAsync(string profile, bool data = false, bool force = false, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.DeleteAsync(
            new DeleteRequest { Profile = ConnectionSettings.NormalizeProfile(profile), Data = data, Force = force },
            cancellationToken: ct).ResponseAsync, "Delete VM");

    public Task<SSHConfigResponse> SSHConfigAsync(string profile, CancellationToken ct = default) =>
        Colima.SSHConfigAsync(Profile(profile), cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> CreateProfileAsync(string name, ColimaConfig config, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.CreateProfileAsync(
            new CreateProfileRequest { Name = DaemonRequestFactory.Required(name, nameof(name)), Config = config },
            cancellationToken: ct).ResponseAsync, "Create profile");

    public Task<StatusResponse> DeleteProfileAsync(string name, bool data = false, bool force = false, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.DeleteProfileAsync(
            new DeleteProfileRequest { Name = DaemonRequestFactory.Required(name, nameof(name)), Data = data, Force = force },
            cancellationToken: ct).ResponseAsync, "Delete profile");

    public Task<StatusResponse> CloneProfileAsync(string source, string destination, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.CloneProfileAsync(new CloneProfileRequest
        {
            Source = DaemonRequestFactory.Required(source, nameof(source)),
            Destination = DaemonRequestFactory.Required(destination, nameof(destination))
        }, cancellationToken: ct).ResponseAsync, "Clone profile");

    public Task<ColimaConfig> GetConfigAsync(string profile, CancellationToken ct = default) =>
        Colima.GetConfigAsync(Profile(profile), cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> SetConfigAsync(string profile, ColimaConfig config, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.SetConfigAsync(
            new SetConfigRequest { Profile = ConnectionSettings.NormalizeProfile(profile), Config = config },
            cancellationToken: ct).ResponseAsync, "Save configuration");

    public Task<ColimaConfig> GetTemplateAsync(CancellationToken ct = default) =>
        Colima.GetTemplateAsync(new Empty(), cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> SetTemplateAsync(ColimaConfig config, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.SetTemplateAsync(config, cancellationToken: ct).ResponseAsync, "Save template");

    public Task<StatusResponse> KubernetesStartAsync(string profile, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.KubernetesStartAsync(
            Profile(profile), cancellationToken: ct).ResponseAsync, "Start Kubernetes");

    public Task<StatusResponse> KubernetesStopAsync(string profile, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.KubernetesStopAsync(
            Profile(profile), cancellationToken: ct).ResponseAsync, "Stop Kubernetes");

    public Task<StatusResponse> KubernetesResetAsync(string profile, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.KubernetesResetAsync(
            Profile(profile), cancellationToken: ct).ResponseAsync, "Reset Kubernetes");

    public async Task<KubeExecResponse> KubernetesExecAsync(string profile, string command, CancellationToken ct = default) =>
        DaemonResponse.EnsureKubeExec(await Colima.KubernetesExecAsync(new KubeExecRequest
        {
            Profile = ConnectionSettings.NormalizeProfile(profile),
            Command = DaemonRequestFactory.Required(command, nameof(command))
        }, cancellationToken: ct).ResponseAsync.ConfigureAwait(false), "Run kubectl command");

    public Task<StatusResponse> ModelServeAsync(string profile, string model, string runner, int port, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.ModelServeAsync(new ModelServeRequest
        {
            Profile = ConnectionSettings.NormalizeProfile(profile),
            Model = DaemonRequestFactory.Required(model, nameof(model)),
            Runner = DaemonRequestFactory.Required(runner, nameof(runner)),
            Port = port
        }, cancellationToken: ct).ResponseAsync, "Serve model");

    public Task<StatusResponse> ModelStopAsync(string profile, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.ModelStopAsync(Profile(profile), cancellationToken: ct).ResponseAsync, "Stop model");

    public Task<StatusResponse> SwitchRuntimeAsync(string profile, string runtime, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.SwitchRuntimeAsync(new SwitchRuntimeRequest
        {
            Profile = ConnectionSettings.NormalizeProfile(profile),
            Runtime = DaemonRequestFactory.Required(runtime, nameof(runtime))
        }, cancellationToken: ct).ResponseAsync, "Switch runtime");

    public Task<StatusResponse> UpdateRuntimeAsync(string profile, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.UpdateRuntimeAsync(Profile(profile), cancellationToken: ct).ResponseAsync, "Update runtime");

    public Task<StatusResponse> UpdateAsync(string profile, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.UpdateAsync(
            DaemonRequestFactory.Profile(profile), cancellationToken: ct).ResponseAsync, "Update Colima");

    public Task<StatusResponse> PruneAsync(string profile, bool all = false, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.PruneAsync(
            DaemonRequestFactory.Prune(profile, all), cancellationToken: ct).ResponseAsync, "Prune Colima");

    public Task<ProcessListResponse> ProcessListAsync(string profile, CancellationToken ct = default) =>
        Colima.ProcessListAsync(Profile(profile), cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> KillProcessAsync(string profile, int pid, int signal = 9, CancellationToken ct = default) =>
        AwaitStatusAsync(Colima.KillProcessAsync(new KillProcessRequest
        {
            Profile = ConnectionSettings.NormalizeProfile(profile),
            Pid = pid,
            Signal = signal
        }, cancellationToken: ct).ResponseAsync, "Kill process");

    // streaming helpers return the async-enumerable from the server-streaming call
    public AsyncServerStreamingCall<ProgressEvent> StartStream(string profile, ColimaConfig? config = null, CancellationToken ct = default) =>
        Colima.Start(new StartRequest { Profile = ConnectionSettings.NormalizeProfile(profile), Config = config ?? new ColimaConfig() }, cancellationToken: ct);

    public AsyncServerStreamingCall<ProgressEvent> RestartStream(string profile, CancellationToken ct = default) =>
        Colima.Restart(new RestartRequest { Profile = ConnectionSettings.NormalizeProfile(profile) }, cancellationToken: ct);

    public AsyncServerStreamingCall<ProgressEvent> ModelSetupStream(string profile, string runner, CancellationToken ct = default) =>
        Colima.ModelSetup(new ModelRequest
        {
            Profile = ConnectionSettings.NormalizeProfile(profile),
            Runner = DaemonRequestFactory.Required(runner, nameof(runner))
        }, cancellationToken: ct);

    public AsyncServerStreamingCall<ProgressEvent> ModelRunStream(string profile, string model, string runner, string prompt = "", CancellationToken ct = default) =>
        Colima.ModelRun(new ModelRunRequest
        {
            Profile = ConnectionSettings.NormalizeProfile(profile),
            Model = DaemonRequestFactory.Required(model, nameof(model)),
            Runner = DaemonRequestFactory.Required(runner, nameof(runner)),
            Prompt = prompt ?? string.Empty
        }, cancellationToken: ct);

    public AsyncServerStreamingCall<VMStatsEvent> VMStatsStream(string profile, CancellationToken ct = default) =>
        Colima.VMStats(Profile(profile), cancellationToken: ct);

    // ─── DockerService helpers ───────────────────────────────────────────────

    public Task<JsonResponse> ListContainersAsync(DockerTarget target, bool all = true, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.ListContainersAsync(
            DaemonRequestFactory.DockerScope(target, all), cancellationToken: ct).ResponseAsync, "List containers");

    public Task<StatusResponse> ContainerActionAsync(string id, string action, DockerTarget target, CancellationToken ct = default) =>
        AwaitStatusAsync(Docker.ContainerActionAsync(
            DaemonRequestFactory.ContainerAction(id, action, target), cancellationToken: ct).ResponseAsync,
            $"{action} container");

    public Task<JsonResponse> CreateContainerAsync(string name, string image, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.CreateContainerAsync(
            DaemonRequestFactory.CreateContainer(name, image, target), cancellationToken: ct).ResponseAsync,
            "Create container");

    public Task<StatusResponse> RenameContainerAsync(string id, string newName, DockerTarget target, CancellationToken ct = default) =>
        AwaitStatusAsync(Docker.RenameContainerAsync(
            DaemonRequestFactory.RenameContainer(id, newName, target), cancellationToken: ct).ResponseAsync,
            "Rename container");

    public Task<JsonResponse> ContainerLogsAsync(string id, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.ContainerLogsAsync(
            DaemonRequestFactory.Id(id, target), cancellationToken: ct).ResponseAsync, "Get container logs");

    public Task<JsonResponse> InspectContainerAsync(string id, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.InspectContainerAsync(
            DaemonRequestFactory.Id(id, target), cancellationToken: ct).ResponseAsync, "Inspect container");

    public Task<JsonResponse> ContainerTopAsync(string id, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.ContainerTopAsync(
            DaemonRequestFactory.Id(id, target), cancellationToken: ct).ResponseAsync, "Get container processes");

    public Task<JsonResponse> ContainerStatsAsync(string id, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.ContainerStatsAsync(
            DaemonRequestFactory.Id(id, target), cancellationToken: ct).ResponseAsync, "Get container stats");

    public Task<JsonResponse> ContainerChangesAsync(string id, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.ContainerChangesAsync(
            DaemonRequestFactory.Id(id, target), cancellationToken: ct).ResponseAsync, "Get container changes");

    public Task<JsonResponse> PruneContainersAsync(DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.PruneContainersAsync(
            DaemonRequestFactory.DockerScope(target), cancellationToken: ct).ResponseAsync, "Prune containers");

    public Task<JsonResponse> ListImagesAsync(DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.ListImagesAsync(
            DaemonRequestFactory.DockerScope(target), cancellationToken: ct).ResponseAsync, "List images");

    public AsyncServerStreamingCall<ProgressEvent> PullImageStream(string name, DockerTarget target, CancellationToken ct = default) =>
        Docker.PullImage(DaemonRequestFactory.Name(name, target), cancellationToken: ct);

    public Task<StatusResponse> RemoveImageAsync(string id, DockerTarget target, CancellationToken ct = default) =>
        AwaitStatusAsync(Docker.RemoveImageAsync(
            DaemonRequestFactory.Id(id, target), cancellationToken: ct).ResponseAsync, "Remove image");

    public Task<JsonResponse> InspectImageAsync(string name, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.InspectImageAsync(
            DaemonRequestFactory.Name(name, target), cancellationToken: ct).ResponseAsync, "Inspect image");

    public Task<JsonResponse> ImageHistoryAsync(string name, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.ImageHistoryAsync(
            DaemonRequestFactory.Name(name, target), cancellationToken: ct).ResponseAsync, "Get image history");

    public Task<StatusResponse> TagImageAsync(string name, string repo, string tag, DockerTarget target, CancellationToken ct = default) =>
        AwaitStatusAsync(Docker.TagImageAsync(
            DaemonRequestFactory.TagImage(name, repo, tag, target), cancellationToken: ct).ResponseAsync,
            "Tag image");

    public AsyncServerStreamingCall<ProgressEvent> PushImageStream(string name, DockerTarget target, CancellationToken ct = default) =>
        Docker.PushImage(DaemonRequestFactory.Name(name, target), cancellationToken: ct);

    public Task<JsonResponse> SearchImagesAsync(string term, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.SearchImagesAsync(
            DaemonRequestFactory.SearchImages(term, target), cancellationToken: ct).ResponseAsync,
            "Search images");

    public Task<JsonResponse> PruneImagesAsync(DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.PruneImagesAsync(
            DaemonRequestFactory.DockerScope(target), cancellationToken: ct).ResponseAsync, "Prune images");

    public Task<JsonResponse> ListVolumesAsync(DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.ListVolumesAsync(
            DaemonRequestFactory.DockerScope(target), cancellationToken: ct).ResponseAsync, "List volumes");

    public Task<JsonResponse> CreateVolumeAsync(string name, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.CreateVolumeAsync(
            DaemonRequestFactory.Name(name, target), cancellationToken: ct).ResponseAsync, "Create volume");

    public Task<StatusResponse> RemoveVolumeAsync(string name, DockerTarget target, CancellationToken ct = default) =>
        AwaitStatusAsync(Docker.RemoveVolumeAsync(
            DaemonRequestFactory.Name(name, target), cancellationToken: ct).ResponseAsync, "Remove volume");

    public Task<JsonResponse> InspectVolumeAsync(string name, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.InspectVolumeAsync(
            DaemonRequestFactory.Name(name, target), cancellationToken: ct).ResponseAsync, "Inspect volume");

    public Task<JsonResponse> PruneVolumesAsync(DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.PruneVolumesAsync(
            DaemonRequestFactory.DockerScope(target), cancellationToken: ct).ResponseAsync, "Prune volumes");

    public Task<JsonResponse> ListNetworksAsync(DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.ListNetworksAsync(
            DaemonRequestFactory.DockerScope(target), cancellationToken: ct).ResponseAsync, "List networks");

    public Task<JsonResponse> CreateNetworkAsync(string name, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.CreateNetworkAsync(
            DaemonRequestFactory.Name(name, target), cancellationToken: ct).ResponseAsync, "Create network");

    public Task<StatusResponse> RemoveNetworkAsync(string id, DockerTarget target, CancellationToken ct = default) =>
        AwaitStatusAsync(Docker.RemoveNetworkAsync(
            DaemonRequestFactory.Id(id, target), cancellationToken: ct).ResponseAsync, "Remove network");

    public Task<JsonResponse> InspectNetworkAsync(string id, DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.InspectNetworkAsync(
            DaemonRequestFactory.Id(id, target), cancellationToken: ct).ResponseAsync, "Inspect network");

    public Task<StatusResponse> ConnectNetworkAsync(string networkId, string containerId, DockerTarget target, CancellationToken ct = default) =>
        AwaitStatusAsync(Docker.ConnectNetworkAsync(
            DaemonRequestFactory.NetworkContainer(networkId, containerId, target), cancellationToken: ct).ResponseAsync,
            "Connect network");

    public Task<StatusResponse> DisconnectNetworkAsync(string networkId, string containerId, DockerTarget target, CancellationToken ct = default) =>
        AwaitStatusAsync(Docker.DisconnectNetworkAsync(
            DaemonRequestFactory.NetworkContainer(networkId, containerId, target), cancellationToken: ct).ResponseAsync,
            "Disconnect network");

    public Task<JsonResponse> PruneNetworksAsync(DockerTarget target, CancellationToken ct = default) =>
        AwaitJsonAsync(Docker.PruneNetworksAsync(
            DaemonRequestFactory.DockerScope(target), cancellationToken: ct).ResponseAsync, "Prune networks");

    public AsyncServerStreamingCall<JsonResponse> StreamEventsStream(DockerTarget target, CancellationToken ct = default) =>
        Docker.StreamEvents(DaemonRequestFactory.DockerScope(target), cancellationToken: ct);

    public AsyncServerStreamingCall<JsonResponse> StreamLogsStream(string id, DockerTarget target, CancellationToken ct = default) =>
        Docker.StreamLogs(DaemonRequestFactory.Id(id, target), cancellationToken: ct);

    public AsyncServerStreamingCall<JsonResponse> StreamStatsStream(string id, DockerTarget target, CancellationToken ct = default) =>
        Docker.StreamStats(DaemonRequestFactory.Id(id, target), cancellationToken: ct);

    // ─── Internal ────────────────────────────────────────────────────────────

    public async Task<DaemonHealthResult> CheckHealthAsync(
        TimeSpan? timeout = null,
        CancellationToken ct = default)
    {
        using var bounded = CancellationTokenSource.CreateLinkedTokenSource(ct);
        bounded.CancelAfter(timeout ?? TimeSpan.FromSeconds(3));
        try
        {
            var version = await VersionAsync(bounded.Token).ConfigureAwait(false);
            var label = string.IsNullOrWhiteSpace(version.Version) ? "unknown version" : version.Version;
            return new DaemonHealthResult(true, $"Connected to colima-daemon {label}");
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            return new DaemonHealthResult(false, $"Daemon health check timed out at {CurrentAddress}");
        }
        catch (Exception ex)
        {
            return new DaemonHealthResult(false, $"Cannot connect to daemon at {CurrentAddress}: {ex.Message}");
        }
    }

    private static ProfileRequest Profile(string profile) => new()
    {
        Profile = ConnectionSettings.NormalizeProfile(profile)
    };

    private static async Task<StatusResponse> AwaitStatusAsync(Task<StatusResponse> response, string operation) =>
        DaemonResponse.EnsureSuccess(await response.ConfigureAwait(false), operation);

    private static async Task<JsonResponse> AwaitJsonAsync(Task<JsonResponse> response, string operation) =>
        DaemonResponse.EnsureJson(await response.ConfigureAwait(false), operation);

    private (ColimaService.ColimaServiceClient colima, DockerService.DockerServiceClient docker) GetOrCreateClients()
    {
        lock (_lock)
        {
            if (_channel is null)
                _channel = GrpcChannel.ForAddress(_currentAddress);
            return (
                new ColimaService.ColimaServiceClient(_channel),
                new DockerService.DockerServiceClient(_channel)
            );
        }
    }

    public void Dispose()
    {
        lock (_lock)
        {
            _channel?.Dispose();
            _channel = null;
        }
    }
}

public readonly record struct DaemonHealthResult(bool IsConnected, string Message);
