using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using ColimaDesktop.Windows.Services;
using ColimaDesktop.Windows.Tests.Fakes;
using ColimaDesktop.Windows.ViewModels;
using Xunit;

namespace ColimaDesktop.Windows.Tests;

/// <summary>
/// Property 12 (action-to-RPC dispatch mapping) for the Windows frontend, proven headlessly against
/// the real view-models. Each generated <c>[RelayCommand]</c> is invoked through its command surface
/// (exactly what the WinUI XAML binds to) with a <see cref="RecordingDaemonClient"/> injected via the
/// <c>App.DaemonClient</c> seam, and the recorded call is asserted to be exactly the mapped
/// Frozen_Contract RPC, scoped to the active profile / Docker provider target. This covers the
/// per-view-model command coverage gap for Kubernetes/AI/Runtime/Config/Monitoring, Profiles,
/// Machines, and the Dashboard/Containers/Images/Volumes/Networks resource surfaces.
/// <para/>
/// Feature: cross-platform-live-verification, Property 12.
/// </summary>
[Trait("Feature", "cross-platform-live-verification")]
[Trait("Property", "12")]
public sealed class ViewModelDispatchTests
{
    private const string Profile = TestApp.DefaultProfile; // "proj-x" (already normalized)

    // ─── ColimaService surfaces ───────────────────────────────────────────────

    [Fact]
    public async Task Kubernetes_commands_dispatch_profile_scoped_cluster_rpcs()
    {
        var (client, _) = TestApp.Configure(Profile);
        var vm = new KubernetesViewModel { KubectlCommand = "get pods" };

        await vm.StartKubernetesCommand.Run();
        Assert.Equal(Profile, client.Single("KubernetesStartAsync").Profile);

        await vm.StopKubernetesCommand.Run();
        Assert.Equal(Profile, client.Single("KubernetesStopAsync").Profile);

        await vm.ExecKubectlCommand.Run();
        var exec = client.Single("KubernetesExecAsync");
        Assert.Equal(Profile, exec.Profile);
        Assert.Equal("get pods", exec.Arg(0));
    }

    [Fact]
    public async Task AiWorkloads_commands_dispatch_profile_scoped_model_rpcs()
    {
        var (client, _) = TestApp.Configure(Profile);
        var vm = new AIWorkloadsViewModel
        {
            ModelName = "llama3", Runner = "docker", Prompt = "hello", ServePort = 9000,
        };

        await vm.ServeModelCommand.Run();
        var serve = client.Single("ModelServeAsync");
        Assert.Equal(Profile, serve.Profile);
        Assert.Equal("llama3", serve.Arg(0));
        Assert.Equal("docker", serve.Arg(1));
        Assert.Equal(9000, serve.Port);

        await vm.StopModelCommand.Run();
        Assert.Equal(Profile, client.Single("ModelStopAsync").Profile);

        await vm.SetupModelCommand.Run();
        var setup = client.Single("ModelSetupStream");
        Assert.Equal(Profile, setup.Profile);
        Assert.Equal("docker", setup.Arg(0));

        await vm.RunModelCommand.Run();
        var run = client.Single("ModelRunStream");
        Assert.Equal(Profile, run.Profile);
        Assert.Equal("llama3", run.Arg(0));
    }

    [Fact]
    public async Task Runtime_commands_dispatch_profile_scoped_runtime_rpcs()
    {
        var (client, _) = TestApp.Configure(Profile);
        var vm = new RuntimeViewModel { TargetRuntime = "containerd" };

        await vm.SwitchRuntimeCommand.Run();
        var switchCall = client.Single("SwitchRuntimeAsync");
        Assert.Equal(Profile, switchCall.Profile);
        Assert.Equal("containerd", switchCall.Arg(0));

        await vm.UpdateRuntimeCommand.Run();
        Assert.Equal(Profile, client.Single("UpdateRuntimeAsync").Profile);

        await vm.UpdateColimaCommand.Run();
        Assert.Equal(Profile, client.Single("UpdateAsync").Profile);
    }

    [Fact]
    public async Task Configuration_commands_dispatch_config_and_template_rpcs()
    {
        var (client, _) = TestApp.Configure(Profile);
        var vm = new ConfigurationViewModel();

        await vm.LoadAsync();
        Assert.Equal(Profile, client.Single("GetConfigAsync").Profile);

        await vm.SaveConfigCommand.Run();
        Assert.Equal(Profile, client.Single("SetConfigAsync").Profile);

        await vm.LoadTemplateCommand.Run();
        Assert.True(client.Invoked("GetTemplateAsync"));

        await vm.SaveTemplateCommand.Run();
        Assert.True(client.Invoked("SetTemplateAsync"));
    }

    [Fact]
    public async Task Monitoring_commands_dispatch_profile_scoped_process_rpcs()
    {
        var (client, _) = TestApp.Configure(Profile);
        var vm = new MonitoringViewModel();

        await vm.RefreshProcessesCommand.Run();
        Assert.Equal(Profile, client.Single("ProcessListAsync").Profile);

        await vm.StartStatsStreamCommand.Run();
        Assert.Equal(Profile, client.Single("VMStatsStream").Profile);
    }

    [Fact]
    public async Task Profiles_commands_dispatch_profile_management_rpcs()
    {
        var (client, _) = TestApp.Configure(Profile);
        var vm = new ProfilesViewModel
        {
            NewProfileName = "created", CloneSource = "src", CloneDestination = "dst",
        };

        await vm.LoadAsync();
        Assert.True(client.Invoked("ListProfilesAsync"));

        await vm.CreateProfileCommand.Run();
        Assert.Equal("created", client.Single("CreateProfileAsync").Arg(0));

        await vm.CloneProfileCommand.Run();
        var clone = client.Single("CloneProfileAsync");
        Assert.Equal("src", clone.Arg(0));
        Assert.Equal("dst", clone.Arg(1));
    }

    [Fact]
    public void Profiles_select_sets_active_profile_without_issuing_any_rpc()
    {
        var (client, settings) = TestApp.Configure(Profile);
        var vm = new ProfilesViewModel();

        vm.SelectProfileCommand.Execute("  chosen  ");

        Assert.Equal("chosen", settings.ActiveProfile); // normalized, no surrounding space
        Assert.Equal(0, client.CallCount);               // pure selection: no daemon call
    }

    [Fact]
    public async Task Machines_load_lists_lima_machines()
    {
        var (client, _) = TestApp.Configure(Profile);
        var vm = new MachinesViewModel();

        await vm.RefreshCommand.Run();

        Assert.Equal(1, client.CallCount);
        Assert.Equal("ListMachinesAsync", client.LastCall.Method);
    }

    // ─── Dashboard (VM lifecycle + SSH) ───────────────────────────────────────

    [Fact]
    public async Task Dashboard_lifecycle_commands_dispatch_profile_scoped_rpcs()
    {
        var (client, _) = TestApp.Configure(Profile);
        var vm = new DashboardViewModel();

        await vm.StartCommand.Run();
        Assert.Equal(Profile, client.Single("StartStream").Profile);

        await vm.StopCommand.Run();
        Assert.Equal(Profile, client.Single("StopAsync").Profile);

        await vm.RestartCommand.Run();
        Assert.Equal(Profile, client.Single("RestartStream").Profile);

        await vm.ShowSshConfigCommand.Run();
        Assert.Equal(Profile, client.Single("SSHConfigAsync").Profile);
    }

    // ─── DockerService surfaces (profile + provider scope) ────────────────────

    [Fact]
    public async Task Containers_commands_dispatch_docker_rpcs_with_provider_scope()
    {
        var (client, _) = TestApp.Configure(Profile, ConnectionSettings.BackendMode.LocalWSL2);
        var vm = new ContainersViewModel { NewContainerName = "web", NewContainerImage = "nginx" };

        await vm.StartContainerCommand.Run("c1");
        var start = client.Single("ContainerActionAsync");
        AssertLocalWsl2Scope(start);
        Assert.Equal("c1", start.Arg(0));
        Assert.Equal("start", start.Arg(1));

        await vm.CreateContainerCommand.Run();
        var create = client.Single("CreateContainerAsync");
        AssertLocalWsl2Scope(create);
        Assert.Equal("web", create.Arg(0));
        Assert.Equal("nginx", create.Arg(1));

        await vm.InspectContainerCommand.Run("c1");
        AssertLocalWsl2Scope(client.Single("InspectContainerAsync"));

        await vm.ContainerLogsCommand.Run("c1");
        AssertLocalWsl2Scope(client.Single("ContainerLogsAsync"));
    }

    [Fact]
    public async Task Images_commands_dispatch_docker_rpcs_with_provider_scope()
    {
        var (client, _) = TestApp.Configure(Profile, ConnectionSettings.BackendMode.LocalWSL2);
        var vm = new ImagesViewModel
        {
            PullImageName = "alpine:latest", SearchTerm = "nginx",
            TagName = "img", TagRepo = "repo", TagTag = "v1",
        };

        await vm.PullImageCommand.Run();
        var pull = client.Single("PullImageStream");
        AssertLocalWsl2Scope(pull);
        Assert.Equal("alpine:latest", pull.Arg(0));

        await vm.TagImageCommand.Run();
        var tag = client.Single("TagImageAsync");
        AssertLocalWsl2Scope(tag);
        Assert.Equal("img", tag.Arg(0));
        Assert.Equal("repo", tag.Arg(1));
        Assert.Equal("v1", tag.Arg(2));

        await vm.SearchImagesCommand.Run();
        Assert.Equal("nginx", client.Single("SearchImagesAsync").Arg(0));

        await vm.PushImageCommand.Run("img:v1");
        Assert.Equal("img:v1", client.Single("PushImageStream").Arg(0));
    }

    [Fact]
    public async Task Volumes_commands_dispatch_docker_rpcs_with_provider_scope()
    {
        var (client, _) = TestApp.Configure(Profile, ConnectionSettings.BackendMode.LocalWSL2);
        var vm = new VolumesViewModel { NewVolumeName = "data" };

        await vm.CreateVolumeCommand.Run();
        var create = client.Single("CreateVolumeAsync");
        AssertLocalWsl2Scope(create);
        Assert.Equal("data", create.Arg(0));

        await vm.InspectVolumeCommand.Run("data");
        AssertLocalWsl2Scope(client.Single("InspectVolumeAsync"));
    }

    [Fact]
    public async Task Networks_commands_dispatch_docker_rpcs_with_provider_scope()
    {
        var (client, _) = TestApp.Configure(Profile, ConnectionSettings.BackendMode.LocalWSL2);
        var vm = new NetworksViewModel
        {
            NewNetworkName = "bridge-x", ConnectNetworkId = "net1", ConnectContainerId = "c1",
        };

        await vm.CreateNetworkCommand.Run();
        var create = client.Single("CreateNetworkAsync");
        AssertLocalWsl2Scope(create);
        Assert.Equal("bridge-x", create.Arg(0));

        await vm.ConnectNetworkCommand.Run();
        var connect = client.Single("ConnectNetworkAsync");
        AssertLocalWsl2Scope(connect);
        Assert.Equal("net1", connect.Arg(0));
        Assert.Equal("c1", connect.Arg(1));

        await vm.DisconnectNetworkCommand.Run();
        AssertLocalWsl2Scope(client.Single("DisconnectNetworkAsync"));
    }

    // ─── Provider routing: remote SSH carries host, never wsl2 ────────────────

    [Fact]
    public async Task Docker_commands_carry_remote_ssh_host_when_mode_is_remote()
    {
        var (client, _) = TestApp.Configure(Profile, ConnectionSettings.BackendMode.RemoteSSH, "user@remote");
        var vm = new VolumesViewModel { NewVolumeName = "data" };

        await vm.CreateVolumeCommand.Run();

        var create = client.Single("CreateVolumeAsync");
        Assert.Equal(Profile, create.Profile);
        Assert.Equal("user@remote", create.Host);
        Assert.False(create.Wsl2);
    }

    // ─── Property 12 (randomized): profile + provider scope totality ──────────

    [Fact]
    public async Task EveryDispatchIsScopedToTheActiveProfileAndProvider_AcrossRandomInputs()
    {
        // Property (Property 12): for ANY active profile name and ANY backend mode, dispatching a
        // command records an RPC scoped to exactly that profile — a ColimaService call carries the
        // profile, and a DockerService call carries the profile plus the mode's provider fields
        // (wsl2 for local, ssh host for remote) — never a default/global target.
        var rng = new Random(1212);
        for (var i = 0; i < 150; i++)
        {
            var profile = RandomProfile(rng);            // non-blank, already-trimmed
            var remote = rng.Next(2) == 0;
            var mode = remote ? ConnectionSettings.BackendMode.RemoteSSH
                              : ConnectionSettings.BackendMode.LocalWSL2;
            var ssh = $"user@host-{rng.Next(1000)}";

            var (client, _) = TestApp.Configure(profile, mode, ssh);

            // ColimaService: profile-scoped cluster start.
            await new KubernetesViewModel().StartKubernetesCommand.Run();
            Assert.Equal(profile, client.Single("KubernetesStartAsync").Profile);

            // DockerService: profile + provider-scoped create.
            await new VolumesViewModel { NewVolumeName = $"v{i}" }.CreateVolumeCommand.Run();
            var create = client.Single("CreateVolumeAsync");
            Assert.Equal(profile, create.Profile);
            if (remote)
            {
                Assert.Equal(ssh, create.Host);
                Assert.False(create.Wsl2);
            }
            else
            {
                Assert.Equal(string.Empty, create.Host);
                Assert.True(create.Wsl2);
            }
        }
    }

    private static void AssertLocalWsl2Scope(RecordedCall call)
    {
        Assert.Equal(Profile, call.Profile);
        Assert.True(call.Wsl2);
        Assert.Equal(string.Empty, call.Host);
    }

    private static string RandomProfile(Random rng)
    {
        const string alphabet = "abcdefghijklmnopqrstuvwxyz0123456789-";
        var length = rng.Next(1, 16);
        var chars = new char[length];
        for (var i = 0; i < length; i++)
            chars[i] = alphabet[rng.Next(alphabet.Length)];
        var candidate = new string(chars);
        // Keep it non-blank and free of leading/trailing separators so NormalizeProfile is identity
        // and the raw-vs-normalized profile paths converge on the same expected value.
        return candidate.Trim('-').Length == 0 ? $"p{rng.Next(10000)}" : candidate.Trim('-');
    }
}
