using System;
using System.Threading.Tasks;
using Grpc.Net.Client;
using Colimaui; // generated namespace from colima_ui.proto (package colimaui)

namespace ColimaDesktop.Windows.Services;

/// <summary>
/// gRPC client for the colima-desktop daemon. On Windows the daemon is reached over
/// TCP (remote colima/Lima host via SSH tunnel) or a local WSL2/Docker-backed daemon.
/// </summary>
public sealed class DaemonClient : IDisposable
{
    private readonly GrpcChannel _channel;
    public ColimaService.ColimaServiceClient Colima { get; }
    public DockerService.DockerServiceClient Docker { get; }

    public DaemonClient(string address = "http://127.0.0.1:50051")
    {
        _channel = GrpcChannel.ForAddress(address);
        Colima = new ColimaService.ColimaServiceClient(_channel);
        Docker = new DockerService.DockerServiceClient(_channel);
    }

    public async Task<VMStatus> StatusAsync(string profile) =>
        await Colima.StatusAsync(new StatusRequest { Profile = profile });

    public async Task<ProfileList> ProfilesAsync() =>
        await Colima.ListProfilesAsync(new Empty());

    public async Task<JsonResponse> ContainersAsync(string profile, bool wsl2) =>
        await Docker.ListContainersAsync(new DockerScope { Profile = profile, All = true, Wsl2 = wsl2 });

    public void Dispose() => _channel.Dispose();
}
