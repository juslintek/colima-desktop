using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Grpc.Core;
using ColimaDesktop.Windows.Services;
using Colimaui;

namespace ColimaDesktop.Windows.Tests.Fakes;

/// <summary>
/// One recorded invocation of an <see cref="IDaemonClient"/> method. Captures the method name plus
/// the profile/provider scope and the identifying arguments a dispatch test asserts on, so
/// "command X invoked exactly RPC Y for profile/target Z" (Property 12) is verifiable headlessly.
/// </summary>
public sealed class RecordedCall(string method)
{
    public string Method { get; } = method;
    public string Profile { get; init; } = string.Empty;
    public string Host { get; init; } = string.Empty;
    public bool Wsl2 { get; init; }
    public IReadOnlyList<string> Args { get; init; } = Array.Empty<string>();
    public bool All { get; init; }
    public bool Force { get; init; }
    public bool Data { get; init; }
    public int Port { get; init; }
    public int Pid { get; init; }
    public int Signal { get; init; }

    public string Arg(int index) => index >= 0 && index < Args.Count ? Args[index] : string.Empty;

    public override string ToString() =>
        $"{Method}(profile={Profile}, host={Host}, wsl2={Wsl2}, args=[{string.Join(",", Args)}])";
}

/// <summary>
/// A deterministic, in-memory <see cref="IDaemonClient"/> test double. It records every call, returns
/// canned success responses, can be told to fail specific methods (so response-error handling is
/// exercised), and backs the server-streaming methods with a scripted or blocking stream reader (so
/// streaming completion, error frames, incomplete-stream detection, cancellation, and bounded output
/// are all deterministic). No gRPC channel, no daemon, no Windows SDK.
/// </summary>
public sealed class RecordingDaemonClient : IDaemonClient
{
    private readonly object _lock = new();
    private readonly List<RecordedCall> _calls = new();
    private string _currentAddress = "http://127.0.0.1:50051";

    /// <summary>Method names configured to throw <see cref="DaemonOperationException"/> when invoked.</summary>
    public HashSet<string> FailingMethods { get; } = new();

    /// <summary>Progress frames returned by every ProgressEvent stream (pull/push/start/restart/model).</summary>
    public IReadOnlyList<ProgressEvent> ProgressFrames { get; set; } = new[]
    {
        new ProgressEvent { Message = "working", Progress = 0.5f },
        new ProgressEvent { Message = "done", Progress = 1f, Done = true },
    };

    /// <summary>VM-stats frames returned by <see cref="VMStatsStream"/>.</summary>
    public IReadOnlyList<VMStatsEvent> VMStatsFrames { get; set; } = new[] { new VMStatsEvent() };

    /// <summary>JSON frames returned by the Docker event/log/stat streams.</summary>
    public IReadOnlyList<JsonResponse> DockerStreamFrames { get; set; } = new[]
    {
        new JsonResponse { Json = "{\"line\":1}" },
        new JsonResponse { Json = "{\"line\":2}" },
    };

    /// <summary>When set, every stream reader blocks (awaiting cancellation) after emitting its frames.</summary>
    public bool BlockStreamsAfterFrames { get; set; }

    /// <summary>When set, every stream reader throws this after emitting its frames instead of ending.</summary>
    public Exception? ThrowAtStreamEnd { get; set; }

    // ─── Recorded-call inspection ─────────────────────────────────────────────

    public IReadOnlyList<RecordedCall> Calls { get { lock (_lock) return _calls.ToArray(); } }
    public int CallCount { get { lock (_lock) return _calls.Count; } }
    public RecordedCall LastCall { get { lock (_lock) return _calls[^1]; } }
    public IReadOnlyList<string> MethodsInvoked { get { lock (_lock) return _calls.Select(c => c.Method).ToArray(); } }

    /// <summary>The single recorded call for <paramref name="method"/>; throws if not exactly one.</summary>
    public RecordedCall Single(string method)
    {
        lock (_lock) return _calls.Single(c => c.Method == method);
    }

    public bool Invoked(string method)
    {
        lock (_lock) return _calls.Any(c => c.Method == method);
    }

    // ─── IDaemonClient: connection ────────────────────────────────────────────

    public string CurrentAddress { get { lock (_lock) return _currentAddress; } }

    public void Reconnect(string address)
    {
        Record(new RecordedCall("Reconnect") { Args = new[] { address } });
        lock (_lock) _currentAddress = address;
    }

    public Task<DaemonHealthResult> CheckHealthAsync(TimeSpan? timeout = null, CancellationToken ct = default)
    {
        Record(new RecordedCall("CheckHealthAsync"));
        return ShouldFail("CheckHealthAsync")
            ? Task.FromResult(new DaemonHealthResult(false, "fake unhealthy"))
            : Task.FromResult(new DaemonHealthResult(true, "fake connected"));
    }

    public void Dispose() { }

    // ─── IDaemonClient: ColimaService ─────────────────────────────────────────

    public Task<VMStatus> StatusAsync(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("StatusAsync") { Profile = profile });
        return Value("StatusAsync", new VMStatus());
    }

    public Task<ProfileList> ListProfilesAsync(CancellationToken ct = default)
    {
        Record(new RecordedCall("ListProfilesAsync"));
        return Value("ListProfilesAsync", new ProfileList());
    }

    public Task<MachineList> ListMachinesAsync(CancellationToken ct = default)
    {
        Record(new RecordedCall("ListMachinesAsync"));
        return Value("ListMachinesAsync", new MachineList());
    }

    public Task<VersionResponse> VersionAsync(CancellationToken ct = default)
    {
        Record(new RecordedCall("VersionAsync"));
        return Value("VersionAsync", new VersionResponse { Version = "fake-1.0" });
    }

    public Task<StatusResponse> StopAsync(string profile, bool force = false, CancellationToken ct = default)
    {
        Record(new RecordedCall("StopAsync") { Profile = profile, Force = force });
        return StatusResult("StopAsync");
    }

    public Task<StatusResponse> DeleteAsync(string profile, bool data = false, bool force = false, CancellationToken ct = default)
    {
        Record(new RecordedCall("DeleteAsync") { Profile = profile, Data = data, Force = force });
        return StatusResult("DeleteAsync");
    }

    public Task<SSHConfigResponse> SSHConfigAsync(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("SSHConfigAsync") { Profile = profile });
        return Value("SSHConfigAsync", new SSHConfigResponse { Config = "fake-ssh-config" });
    }

    public Task<StatusResponse> CreateProfileAsync(string name, ColimaConfig config, CancellationToken ct = default)
    {
        Record(new RecordedCall("CreateProfileAsync") { Args = new[] { name } });
        return StatusResult("CreateProfileAsync");
    }

    public Task<StatusResponse> DeleteProfileAsync(string name, bool data = false, bool force = false, CancellationToken ct = default)
    {
        Record(new RecordedCall("DeleteProfileAsync") { Args = new[] { name }, Data = data, Force = force });
        return StatusResult("DeleteProfileAsync");
    }

    public Task<StatusResponse> CloneProfileAsync(string source, string destination, CancellationToken ct = default)
    {
        Record(new RecordedCall("CloneProfileAsync") { Args = new[] { source, destination } });
        return StatusResult("CloneProfileAsync");
    }

    public Task<ColimaConfig> GetConfigAsync(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("GetConfigAsync") { Profile = profile });
        return Value("GetConfigAsync", new ColimaConfig());
    }

    public Task<StatusResponse> SetConfigAsync(string profile, ColimaConfig config, CancellationToken ct = default)
    {
        Record(new RecordedCall("SetConfigAsync") { Profile = profile });
        return StatusResult("SetConfigAsync");
    }

    public Task<ColimaConfig> GetTemplateAsync(CancellationToken ct = default)
    {
        Record(new RecordedCall("GetTemplateAsync"));
        return Value("GetTemplateAsync", new ColimaConfig());
    }

    public Task<StatusResponse> SetTemplateAsync(ColimaConfig config, CancellationToken ct = default)
    {
        Record(new RecordedCall("SetTemplateAsync"));
        return StatusResult("SetTemplateAsync");
    }

    public Task<StatusResponse> KubernetesStartAsync(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("KubernetesStartAsync") { Profile = profile });
        return StatusResult("KubernetesStartAsync");
    }

    public Task<StatusResponse> KubernetesStopAsync(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("KubernetesStopAsync") { Profile = profile });
        return StatusResult("KubernetesStopAsync");
    }

    public Task<StatusResponse> KubernetesResetAsync(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("KubernetesResetAsync") { Profile = profile });
        return StatusResult("KubernetesResetAsync");
    }

    public Task<KubeExecResponse> KubernetesExecAsync(string profile, string command, CancellationToken ct = default)
    {
        Record(new RecordedCall("KubernetesExecAsync") { Profile = profile, Args = new[] { command } });
        return Value("KubernetesExecAsync", new KubeExecResponse { Output = "fake-output", ExitCode = 0 });
    }

    public Task<StatusResponse> ModelServeAsync(string profile, string model, string runner, int port, CancellationToken ct = default)
    {
        Record(new RecordedCall("ModelServeAsync") { Profile = profile, Args = new[] { model, runner }, Port = port });
        return StatusResult("ModelServeAsync");
    }

    public Task<StatusResponse> ModelStopAsync(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("ModelStopAsync") { Profile = profile });
        return StatusResult("ModelStopAsync");
    }

    public Task<StatusResponse> SwitchRuntimeAsync(string profile, string runtime, CancellationToken ct = default)
    {
        Record(new RecordedCall("SwitchRuntimeAsync") { Profile = profile, Args = new[] { runtime } });
        return StatusResult("SwitchRuntimeAsync");
    }

    public Task<StatusResponse> UpdateRuntimeAsync(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("UpdateRuntimeAsync") { Profile = profile });
        return StatusResult("UpdateRuntimeAsync");
    }

    public Task<StatusResponse> UpdateAsync(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("UpdateAsync") { Profile = profile });
        return StatusResult("UpdateAsync");
    }

    public Task<StatusResponse> PruneAsync(string profile, bool all = false, CancellationToken ct = default)
    {
        Record(new RecordedCall("PruneAsync") { Profile = profile, All = all });
        return StatusResult("PruneAsync");
    }

    public Task<ProcessListResponse> ProcessListAsync(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("ProcessListAsync") { Profile = profile });
        return Value("ProcessListAsync", new ProcessListResponse());
    }

    public Task<StatusResponse> KillProcessAsync(string profile, int pid, int signal = 9, CancellationToken ct = default)
    {
        Record(new RecordedCall("KillProcessAsync") { Profile = profile, Pid = pid, Signal = signal });
        return StatusResult("KillProcessAsync");
    }

    public AsyncServerStreamingCall<ProgressEvent> StartStream(string profile, ColimaConfig? config = null, CancellationToken ct = default)
    {
        Record(new RecordedCall("StartStream") { Profile = profile });
        return ProgressStream();
    }

    public AsyncServerStreamingCall<ProgressEvent> RestartStream(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("RestartStream") { Profile = profile });
        return ProgressStream();
    }

    public AsyncServerStreamingCall<ProgressEvent> ModelSetupStream(string profile, string runner, CancellationToken ct = default)
    {
        Record(new RecordedCall("ModelSetupStream") { Profile = profile, Args = new[] { runner } });
        return ProgressStream();
    }

    public AsyncServerStreamingCall<ProgressEvent> ModelRunStream(string profile, string model, string runner, string prompt = "", CancellationToken ct = default)
    {
        Record(new RecordedCall("ModelRunStream") { Profile = profile, Args = new[] { model, runner, prompt } });
        return ProgressStream();
    }

    public AsyncServerStreamingCall<VMStatsEvent> VMStatsStream(string profile, CancellationToken ct = default)
    {
        Record(new RecordedCall("VMStatsStream") { Profile = profile });
        return MakeStream(new FakeStreamReader<VMStatsEvent>(VMStatsFrames, BlockStreamsAfterFrames, ThrowAtStreamEnd));
    }

    // ─── IDaemonClient: DockerService ─────────────────────────────────────────

    public Task<JsonResponse> ListContainersAsync(DockerTarget target, bool all = true, CancellationToken ct = default)
    {
        Record(Docker("ListContainersAsync", target, all: all));
        return JsonResult("ListContainersAsync");
    }

    public Task<StatusResponse> ContainerActionAsync(string id, string action, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("ContainerActionAsync", target, args: new[] { id, action }));
        return StatusResult("ContainerActionAsync");
    }

    public Task<JsonResponse> CreateContainerAsync(string name, string image, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("CreateContainerAsync", target, args: new[] { name, image }));
        return JsonResult("CreateContainerAsync");
    }

    public Task<StatusResponse> RenameContainerAsync(string id, string newName, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("RenameContainerAsync", target, args: new[] { id, newName }));
        return StatusResult("RenameContainerAsync");
    }

    public Task<JsonResponse> ContainerLogsAsync(string id, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("ContainerLogsAsync", target, args: new[] { id }));
        return JsonResult("ContainerLogsAsync");
    }

    public Task<JsonResponse> InspectContainerAsync(string id, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("InspectContainerAsync", target, args: new[] { id }));
        return JsonResult("InspectContainerAsync");
    }

    public Task<JsonResponse> ContainerTopAsync(string id, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("ContainerTopAsync", target, args: new[] { id }));
        return JsonResult("ContainerTopAsync");
    }

    public Task<JsonResponse> ContainerStatsAsync(string id, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("ContainerStatsAsync", target, args: new[] { id }));
        return JsonResult("ContainerStatsAsync");
    }

    public Task<JsonResponse> ContainerChangesAsync(string id, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("ContainerChangesAsync", target, args: new[] { id }));
        return JsonResult("ContainerChangesAsync");
    }

    public Task<JsonResponse> PruneContainersAsync(DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("PruneContainersAsync", target));
        return JsonResult("PruneContainersAsync");
    }

    public Task<JsonResponse> ListImagesAsync(DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("ListImagesAsync", target));
        return JsonResult("ListImagesAsync");
    }

    public AsyncServerStreamingCall<ProgressEvent> PullImageStream(string name, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("PullImageStream", target, args: new[] { name }));
        return ProgressStream();
    }

    public Task<StatusResponse> RemoveImageAsync(string id, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("RemoveImageAsync", target, args: new[] { id }));
        return StatusResult("RemoveImageAsync");
    }

    public Task<JsonResponse> InspectImageAsync(string name, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("InspectImageAsync", target, args: new[] { name }));
        return JsonResult("InspectImageAsync");
    }

    public Task<JsonResponse> ImageHistoryAsync(string name, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("ImageHistoryAsync", target, args: new[] { name }));
        return JsonResult("ImageHistoryAsync");
    }

    public Task<StatusResponse> TagImageAsync(string name, string repo, string tag, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("TagImageAsync", target, args: new[] { name, repo, tag }));
        return StatusResult("TagImageAsync");
    }

    public AsyncServerStreamingCall<ProgressEvent> PushImageStream(string name, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("PushImageStream", target, args: new[] { name }));
        return ProgressStream();
    }

    public Task<JsonResponse> SearchImagesAsync(string term, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("SearchImagesAsync", target, args: new[] { term }));
        return JsonResult("SearchImagesAsync");
    }

    public Task<JsonResponse> PruneImagesAsync(DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("PruneImagesAsync", target));
        return JsonResult("PruneImagesAsync");
    }

    public Task<JsonResponse> ListVolumesAsync(DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("ListVolumesAsync", target));
        return JsonResult("ListVolumesAsync");
    }

    public Task<JsonResponse> CreateVolumeAsync(string name, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("CreateVolumeAsync", target, args: new[] { name }));
        return JsonResult("CreateVolumeAsync");
    }

    public Task<StatusResponse> RemoveVolumeAsync(string name, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("RemoveVolumeAsync", target, args: new[] { name }));
        return StatusResult("RemoveVolumeAsync");
    }

    public Task<JsonResponse> InspectVolumeAsync(string name, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("InspectVolumeAsync", target, args: new[] { name }));
        return JsonResult("InspectVolumeAsync");
    }

    public Task<JsonResponse> PruneVolumesAsync(DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("PruneVolumesAsync", target));
        return JsonResult("PruneVolumesAsync");
    }

    public Task<JsonResponse> ListNetworksAsync(DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("ListNetworksAsync", target));
        return JsonResult("ListNetworksAsync");
    }

    public Task<JsonResponse> CreateNetworkAsync(string name, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("CreateNetworkAsync", target, args: new[] { name }));
        return JsonResult("CreateNetworkAsync");
    }

    public Task<StatusResponse> RemoveNetworkAsync(string id, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("RemoveNetworkAsync", target, args: new[] { id }));
        return StatusResult("RemoveNetworkAsync");
    }

    public Task<JsonResponse> InspectNetworkAsync(string id, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("InspectNetworkAsync", target, args: new[] { id }));
        return JsonResult("InspectNetworkAsync");
    }

    public Task<StatusResponse> ConnectNetworkAsync(string networkId, string containerId, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("ConnectNetworkAsync", target, args: new[] { networkId, containerId }));
        return StatusResult("ConnectNetworkAsync");
    }

    public Task<StatusResponse> DisconnectNetworkAsync(string networkId, string containerId, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("DisconnectNetworkAsync", target, args: new[] { networkId, containerId }));
        return StatusResult("DisconnectNetworkAsync");
    }

    public Task<JsonResponse> PruneNetworksAsync(DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("PruneNetworksAsync", target));
        return JsonResult("PruneNetworksAsync");
    }

    public AsyncServerStreamingCall<JsonResponse> StreamEventsStream(DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("StreamEventsStream", target));
        return MakeStream(new FakeStreamReader<JsonResponse>(DockerStreamFrames, BlockStreamsAfterFrames, ThrowAtStreamEnd));
    }

    public AsyncServerStreamingCall<JsonResponse> StreamLogsStream(string id, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("StreamLogsStream", target, args: new[] { id }));
        return MakeStream(new FakeStreamReader<JsonResponse>(DockerStreamFrames, BlockStreamsAfterFrames, ThrowAtStreamEnd));
    }

    public AsyncServerStreamingCall<JsonResponse> StreamStatsStream(string id, DockerTarget target, CancellationToken ct = default)
    {
        Record(Docker("StreamStatsStream", target, args: new[] { id }));
        return MakeStream(new FakeStreamReader<JsonResponse>(DockerStreamFrames, BlockStreamsAfterFrames, ThrowAtStreamEnd));
    }

    // ─── Internals ────────────────────────────────────────────────────────────

    private void Record(RecordedCall call)
    {
        lock (_lock) _calls.Add(call);
    }

    private bool ShouldFail(string method) => FailingMethods.Contains(method);

    private static DaemonOperationException Fail(string method) =>
        new(method, "recording-fake induced failure");

    private Task<StatusResponse> StatusResult(string method) =>
        ShouldFail(method)
            ? Task.FromException<StatusResponse>(Fail(method))
            : Task.FromResult(new StatusResponse { Success = true });

    private Task<JsonResponse> JsonResult(string method) =>
        ShouldFail(method)
            ? Task.FromException<JsonResponse>(Fail(method))
            : Task.FromResult(new JsonResponse { Json = "[]" });

    private Task<T> Value<T>(string method, T value) =>
        ShouldFail(method) ? Task.FromException<T>(Fail(method)) : Task.FromResult(value);

    private static RecordedCall Docker(string method, DockerTarget target, string[]? args = null, bool all = false) =>
        new(method)
        {
            Profile = target.Profile,
            Host = target.Host,
            Wsl2 = target.Wsl2,
            Args = args ?? Array.Empty<string>(),
            All = all,
        };

    private AsyncServerStreamingCall<ProgressEvent> ProgressStream() =>
        MakeStream(new FakeStreamReader<ProgressEvent>(ProgressFrames, BlockStreamsAfterFrames, ThrowAtStreamEnd));

    private static AsyncServerStreamingCall<T> MakeStream<T>(IAsyncStreamReader<T> reader) =>
        new(reader, Task.FromResult(new Metadata()), () => Status.DefaultSuccess, () => new Metadata(), () => { });

    /// <summary>
    /// A scriptable <see cref="IAsyncStreamReader{T}"/>: yields the supplied frames, then either ends,
    /// throws (mid/end error injection), or blocks awaiting cancellation (so cancellation is
    /// deterministically testable). Honors the caller's token on every <c>MoveNext</c>.
    /// </summary>
    private sealed class FakeStreamReader<T> : IAsyncStreamReader<T>
    {
        private readonly Queue<T> _frames;
        private readonly bool _blockAtEnd;
        private readonly Exception? _throwAtEnd;
        private T _current = default!;

        public FakeStreamReader(IEnumerable<T> frames, bool blockAtEnd, Exception? throwAtEnd)
        {
            _frames = new Queue<T>(frames);
            _blockAtEnd = blockAtEnd;
            _throwAtEnd = throwAtEnd;
        }

        public T Current => _current;

        public async Task<bool> MoveNext(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_frames.Count > 0)
            {
                _current = _frames.Dequeue();
                return true;
            }

            if (_throwAtEnd is not null)
                throw _throwAtEnd;

            if (_blockAtEnd)
            {
                var released = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                using (cancellationToken.Register(() => released.TrySetResult()))
                    await released.Task.ConfigureAwait(false);
                cancellationToken.ThrowIfCancellationRequested();
            }

            return false;
        }
    }
}
