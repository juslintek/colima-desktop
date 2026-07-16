using System;
using System.Runtime.CompilerServices;
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
public sealed class DaemonClient : IDisposable
{
    private GrpcChannel? _channel;
    private string _currentAddress = string.Empty;
    private readonly object _lock = new();

    public ColimaService.ColimaServiceClient Colima => GetOrCreateClients().colima;
    public DockerService.DockerServiceClient Docker => GetOrCreateClients().docker;

    public DaemonClient(string address = "http://127.0.0.1:50051")
    {
        _currentAddress = address;
    }

    /// <summary>Re-connects to a new daemon address (e.g. when switching remote/WSL2).</summary>
    public void Reconnect(string address)
    {
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
        Colima.StatusAsync(new StatusRequest { Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<ProfileList> ListProfilesAsync(CancellationToken ct = default) =>
        Colima.ListProfilesAsync(new Empty(), cancellationToken: ct).ResponseAsync;

    public Task<MachineList> ListMachinesAsync(CancellationToken ct = default) =>
        Colima.ListMachinesAsync(new Empty(), cancellationToken: ct).ResponseAsync;

    public Task<VersionResponse> VersionAsync(CancellationToken ct = default) =>
        Colima.VersionAsync(new Empty(), cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> StopAsync(string profile, bool force = false, CancellationToken ct = default) =>
        Colima.StopAsync(new StopRequest { Profile = profile, Force = force }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> DeleteAsync(string profile, bool data = false, bool force = false, CancellationToken ct = default) =>
        Colima.DeleteAsync(new DeleteRequest { Profile = profile, Data = data, Force = force }, cancellationToken: ct).ResponseAsync;

    public Task<SSHConfigResponse> SSHConfigAsync(string profile, CancellationToken ct = default) =>
        Colima.SSHConfigAsync(new ProfileRequest { Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> CreateProfileAsync(string name, ColimaConfig config, CancellationToken ct = default) =>
        Colima.CreateProfileAsync(new CreateProfileRequest { Name = name, Config = config }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> DeleteProfileAsync(string name, bool data = false, bool force = false, CancellationToken ct = default) =>
        Colima.DeleteProfileAsync(new DeleteProfileRequest { Name = name, Data = data, Force = force }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> CloneProfileAsync(string source, string destination, CancellationToken ct = default) =>
        Colima.CloneProfileAsync(new CloneProfileRequest { Source = source, Destination = destination }, cancellationToken: ct).ResponseAsync;

    public Task<ColimaConfig> GetConfigAsync(string profile, CancellationToken ct = default) =>
        Colima.GetConfigAsync(new ProfileRequest { Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> SetConfigAsync(string profile, ColimaConfig config, CancellationToken ct = default) =>
        Colima.SetConfigAsync(new SetConfigRequest { Profile = profile, Config = config }, cancellationToken: ct).ResponseAsync;

    public Task<ColimaConfig> GetTemplateAsync(CancellationToken ct = default) =>
        Colima.GetTemplateAsync(new Empty(), cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> SetTemplateAsync(ColimaConfig config, CancellationToken ct = default) =>
        Colima.SetTemplateAsync(config, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> KubernetesStartAsync(string profile, CancellationToken ct = default) =>
        Colima.KubernetesStartAsync(new ProfileRequest { Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> KubernetesStopAsync(string profile, CancellationToken ct = default) =>
        Colima.KubernetesStopAsync(new ProfileRequest { Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> KubernetesResetAsync(string profile, CancellationToken ct = default) =>
        Colima.KubernetesResetAsync(new ProfileRequest { Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<KubeExecResponse> KubernetesExecAsync(string profile, string command, CancellationToken ct = default) =>
        Colima.KubernetesExecAsync(new KubeExecRequest { Profile = profile, Command = command }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> ModelServeAsync(string profile, string model, string runner, int port, CancellationToken ct = default) =>
        Colima.ModelServeAsync(new ModelServeRequest { Profile = profile, Model = model, Runner = runner, Port = port }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> ModelStopAsync(string profile, CancellationToken ct = default) =>
        Colima.ModelStopAsync(new ProfileRequest { Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> SwitchRuntimeAsync(string profile, string runtime, CancellationToken ct = default) =>
        Colima.SwitchRuntimeAsync(new SwitchRuntimeRequest { Profile = profile, Runtime = runtime }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> UpdateRuntimeAsync(string profile, CancellationToken ct = default) =>
        Colima.UpdateRuntimeAsync(new ProfileRequest { Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> UpdateAsync(CancellationToken ct = default) =>
        Colima.UpdateAsync(new Empty(), cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> PruneAsync(bool all = false, CancellationToken ct = default) =>
        Colima.PruneAsync(new PruneRequest { All = all }, cancellationToken: ct).ResponseAsync;

    public Task<ProcessListResponse> ProcessListAsync(string profile, CancellationToken ct = default) =>
        Colima.ProcessListAsync(new ProfileRequest { Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> KillProcessAsync(string profile, int pid, int signal = 9, CancellationToken ct = default) =>
        Colima.KillProcessAsync(new KillProcessRequest { Profile = profile, Pid = pid, Signal = signal }, cancellationToken: ct).ResponseAsync;

    // streaming helpers return the async-enumerable from the server-streaming call
    public AsyncServerStreamingCall<ProgressEvent> StartStream(string profile, ColimaConfig? config = null) =>
        Colima.Start(new StartRequest { Profile = profile, Config = config ?? new ColimaConfig() });

    public AsyncServerStreamingCall<ProgressEvent> RestartStream(string profile) =>
        Colima.Restart(new RestartRequest { Profile = profile });

    public AsyncServerStreamingCall<ProgressEvent> ModelSetupStream(string profile, string runner) =>
        Colima.ModelSetup(new ModelRequest { Profile = profile, Runner = runner });

    public AsyncServerStreamingCall<ProgressEvent> ModelRunStream(string profile, string model, string runner, string prompt = "") =>
        Colima.ModelRun(new ModelRunRequest { Profile = profile, Model = model, Runner = runner, Prompt = prompt });

    public AsyncServerStreamingCall<VMStatsEvent> VMStatsStream(string profile) =>
        Colima.VMStats(new ProfileRequest { Profile = profile });

    // ─── DockerService helpers ───────────────────────────────────────────────

    public Task<JsonResponse> ListContainersAsync(string profile, bool all = true, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.ListContainersAsync(new DockerScope { Profile = profile, All = all, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> ContainerActionAsync(string id, string action, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.ContainerActionAsync(new ContainerActionRequest { Id = id, Action = action, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> CreateContainerAsync(string name, string image, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.CreateContainerAsync(new CreateContainerRequest { Name = name, Image = image, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> RenameContainerAsync(string id, string newName, string profile, CancellationToken ct = default) =>
        Docker.RenameContainerAsync(new RenameRequest { Id = id, NewName = newName, Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> ContainerLogsAsync(string id, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.ContainerLogsAsync(new IdRequest { Id = id, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> InspectContainerAsync(string id, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.InspectContainerAsync(new IdRequest { Id = id, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> ContainerTopAsync(string id, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.ContainerTopAsync(new IdRequest { Id = id, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> ContainerStatsAsync(string id, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.ContainerStatsAsync(new IdRequest { Id = id, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> ContainerChangesAsync(string id, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.ContainerChangesAsync(new IdRequest { Id = id, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> PruneContainersAsync(string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.PruneContainersAsync(new DockerScope { Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> ListImagesAsync(string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.ListImagesAsync(new DockerScope { Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public AsyncServerStreamingCall<ProgressEvent> PullImageStream(string name, string profile, bool wsl2 = false) =>
        Docker.PullImage(new NameRequest { Name = name, Profile = profile, Wsl2 = wsl2 });

    public Task<StatusResponse> RemoveImageAsync(string id, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.RemoveImageAsync(new IdRequest { Id = id, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> InspectImageAsync(string name, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.InspectImageAsync(new NameRequest { Name = name, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> ImageHistoryAsync(string name, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.ImageHistoryAsync(new NameRequest { Name = name, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> TagImageAsync(string name, string repo, string tag, string profile, CancellationToken ct = default) =>
        Docker.TagImageAsync(new TagRequest { Name = name, Repo = repo, Tag = tag, Profile = profile }, cancellationToken: ct).ResponseAsync;

    public AsyncServerStreamingCall<ProgressEvent> PushImageStream(string name, string profile, bool wsl2 = false) =>
        Docker.PushImage(new NameRequest { Name = name, Profile = profile, Wsl2 = wsl2 });

    public Task<JsonResponse> SearchImagesAsync(string term, string profile, CancellationToken ct = default) =>
        Docker.SearchImagesAsync(new SearchRequest { Term = term, Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> PruneImagesAsync(string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.PruneImagesAsync(new DockerScope { Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> ListVolumesAsync(string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.ListVolumesAsync(new DockerScope { Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> CreateVolumeAsync(string name, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.CreateVolumeAsync(new NameRequest { Name = name, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> RemoveVolumeAsync(string name, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.RemoveVolumeAsync(new NameRequest { Name = name, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> InspectVolumeAsync(string name, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.InspectVolumeAsync(new NameRequest { Name = name, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> PruneVolumesAsync(string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.PruneVolumesAsync(new DockerScope { Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> ListNetworksAsync(string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.ListNetworksAsync(new DockerScope { Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> CreateNetworkAsync(string name, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.CreateNetworkAsync(new NameRequest { Name = name, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> RemoveNetworkAsync(string id, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.RemoveNetworkAsync(new IdRequest { Id = id, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> InspectNetworkAsync(string id, string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.InspectNetworkAsync(new IdRequest { Id = id, Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> ConnectNetworkAsync(string networkId, string containerId, string profile, CancellationToken ct = default) =>
        Docker.ConnectNetworkAsync(new NetworkContainerRequest { NetworkId = networkId, ContainerId = containerId, Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<StatusResponse> DisconnectNetworkAsync(string networkId, string containerId, string profile, CancellationToken ct = default) =>
        Docker.DisconnectNetworkAsync(new NetworkContainerRequest { NetworkId = networkId, ContainerId = containerId, Profile = profile }, cancellationToken: ct).ResponseAsync;

    public Task<JsonResponse> PruneNetworksAsync(string profile, bool wsl2 = false, CancellationToken ct = default) =>
        Docker.PruneNetworksAsync(new DockerScope { Profile = profile, Wsl2 = wsl2 }, cancellationToken: ct).ResponseAsync;

    public AsyncServerStreamingCall<JsonResponse> StreamEventsStream(string profile, bool wsl2 = false) =>
        Docker.StreamEvents(new DockerScope { Profile = profile, Wsl2 = wsl2 });

    public AsyncServerStreamingCall<JsonResponse> StreamLogsStream(string id, string profile, bool wsl2 = false) =>
        Docker.StreamLogs(new IdRequest { Id = id, Profile = profile, Wsl2 = wsl2 });

    public AsyncServerStreamingCall<JsonResponse> StreamStatsStream(string id, string profile, bool wsl2 = false) =>
        Docker.StreamStats(new IdRequest { Id = id, Profile = profile, Wsl2 = wsl2 });

    // ─── Internal ────────────────────────────────────────────────────────────

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
