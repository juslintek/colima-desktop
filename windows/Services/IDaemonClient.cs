using System;
using System.Threading;
using System.Threading.Tasks;
using Grpc.Core;
using Colimaui; // generated namespace from colima_ui.proto (package colimaui)

namespace ColimaDesktop.Windows.Services;

/// <summary>
/// Abstraction over the daemon gRPC client so view-models depend on a seam rather than the
/// concrete <see cref="DaemonClient"/>. The production <see cref="DaemonClient"/> implements this
/// interface unchanged; the headless test project injects a recording fake through
/// <c>App.DaemonClient</c>, making per-view-model command dispatch (Property 12), the
/// destructive-confirmation gate (Property 13), non-reentrant busy state (Property 16),
/// response-error handling, and streaming/cancellation deterministically testable without the
/// Windows SDK / a live daemon.
/// <para/>
/// The member set mirrors the concrete <see cref="DaemonClient"/> public surface exactly (same
/// signatures + default arguments) so callers compile identically whether <c>Client</c> resolves to
/// the concrete client or a fake. The raw generated <c>Colima</c>/<c>Docker</c> stub properties are
/// intentionally NOT part of this seam — every consumer goes through the typed helpers below.
/// </summary>
public interface IDaemonClient : IDisposable
{
    string CurrentAddress { get; }

    void Reconnect(string address);

    // ─── ColimaService helpers ───────────────────────────────────────────────
    Task<VMStatus> StatusAsync(string profile, CancellationToken ct = default);
    Task<ProfileList> ListProfilesAsync(CancellationToken ct = default);
    Task<MachineList> ListMachinesAsync(CancellationToken ct = default);
    Task<VersionResponse> VersionAsync(CancellationToken ct = default);
    Task<StatusResponse> StopAsync(string profile, bool force = false, CancellationToken ct = default);
    Task<StatusResponse> DeleteAsync(string profile, bool data = false, bool force = false, CancellationToken ct = default);
    Task<SSHConfigResponse> SSHConfigAsync(string profile, CancellationToken ct = default);
    Task<StatusResponse> CreateProfileAsync(string name, ColimaConfig config, CancellationToken ct = default);
    Task<StatusResponse> DeleteProfileAsync(string name, bool data = false, bool force = false, CancellationToken ct = default);
    Task<StatusResponse> CloneProfileAsync(string source, string destination, CancellationToken ct = default);
    Task<ColimaConfig> GetConfigAsync(string profile, CancellationToken ct = default);
    Task<StatusResponse> SetConfigAsync(string profile, ColimaConfig config, CancellationToken ct = default);
    Task<ColimaConfig> GetTemplateAsync(CancellationToken ct = default);
    Task<StatusResponse> SetTemplateAsync(ColimaConfig config, CancellationToken ct = default);
    Task<StatusResponse> KubernetesStartAsync(string profile, CancellationToken ct = default);
    Task<StatusResponse> KubernetesStopAsync(string profile, CancellationToken ct = default);
    Task<StatusResponse> KubernetesResetAsync(string profile, CancellationToken ct = default);
    Task<KubeExecResponse> KubernetesExecAsync(string profile, string command, CancellationToken ct = default);
    Task<StatusResponse> ModelServeAsync(string profile, string model, string runner, int port, CancellationToken ct = default);
    Task<StatusResponse> ModelStopAsync(string profile, CancellationToken ct = default);
    Task<StatusResponse> SwitchRuntimeAsync(string profile, string runtime, CancellationToken ct = default);
    Task<StatusResponse> UpdateRuntimeAsync(string profile, CancellationToken ct = default);
    Task<StatusResponse> UpdateAsync(string profile, CancellationToken ct = default);
    Task<StatusResponse> PruneAsync(string profile, bool all = false, CancellationToken ct = default);
    Task<ProcessListResponse> ProcessListAsync(string profile, CancellationToken ct = default);
    Task<StatusResponse> KillProcessAsync(string profile, int pid, int signal = 9, CancellationToken ct = default);

    AsyncServerStreamingCall<ProgressEvent> StartStream(string profile, ColimaConfig? config = null, CancellationToken ct = default);
    AsyncServerStreamingCall<ProgressEvent> RestartStream(string profile, CancellationToken ct = default);
    AsyncServerStreamingCall<ProgressEvent> ModelSetupStream(string profile, string runner, CancellationToken ct = default);
    AsyncServerStreamingCall<ProgressEvent> ModelRunStream(string profile, string model, string runner, string prompt = "", CancellationToken ct = default);
    AsyncServerStreamingCall<VMStatsEvent> VMStatsStream(string profile, CancellationToken ct = default);

    // ─── DockerService helpers ───────────────────────────────────────────────
    Task<JsonResponse> ListContainersAsync(DockerTarget target, bool all = true, CancellationToken ct = default);
    Task<StatusResponse> ContainerActionAsync(string id, string action, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> CreateContainerAsync(string name, string image, DockerTarget target, CancellationToken ct = default);
    Task<StatusResponse> RenameContainerAsync(string id, string newName, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> ContainerLogsAsync(string id, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> InspectContainerAsync(string id, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> ContainerTopAsync(string id, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> ContainerStatsAsync(string id, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> ContainerChangesAsync(string id, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> PruneContainersAsync(DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> ListImagesAsync(DockerTarget target, CancellationToken ct = default);
    AsyncServerStreamingCall<ProgressEvent> PullImageStream(string name, DockerTarget target, CancellationToken ct = default);
    Task<StatusResponse> RemoveImageAsync(string id, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> InspectImageAsync(string name, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> ImageHistoryAsync(string name, DockerTarget target, CancellationToken ct = default);
    Task<StatusResponse> TagImageAsync(string name, string repo, string tag, DockerTarget target, CancellationToken ct = default);
    AsyncServerStreamingCall<ProgressEvent> PushImageStream(string name, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> SearchImagesAsync(string term, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> PruneImagesAsync(DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> ListVolumesAsync(DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> CreateVolumeAsync(string name, DockerTarget target, CancellationToken ct = default);
    Task<StatusResponse> RemoveVolumeAsync(string name, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> InspectVolumeAsync(string name, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> PruneVolumesAsync(DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> ListNetworksAsync(DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> CreateNetworkAsync(string name, DockerTarget target, CancellationToken ct = default);
    Task<StatusResponse> RemoveNetworkAsync(string id, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> InspectNetworkAsync(string id, DockerTarget target, CancellationToken ct = default);
    Task<StatusResponse> ConnectNetworkAsync(string networkId, string containerId, DockerTarget target, CancellationToken ct = default);
    Task<StatusResponse> DisconnectNetworkAsync(string networkId, string containerId, DockerTarget target, CancellationToken ct = default);
    Task<JsonResponse> PruneNetworksAsync(DockerTarget target, CancellationToken ct = default);
    AsyncServerStreamingCall<JsonResponse> StreamEventsStream(DockerTarget target, CancellationToken ct = default);
    AsyncServerStreamingCall<JsonResponse> StreamLogsStream(string id, DockerTarget target, CancellationToken ct = default);
    AsyncServerStreamingCall<JsonResponse> StreamStatsStream(string id, DockerTarget target, CancellationToken ct = default);

    Task<DaemonHealthResult> CheckHealthAsync(TimeSpan? timeout = null, CancellationToken ct = default);
}
