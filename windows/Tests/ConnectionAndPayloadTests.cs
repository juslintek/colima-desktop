using ColimaDesktop.Windows.Services;
using Xunit;

namespace ColimaDesktop.Windows.Tests;

public sealed class ConnectionAndPayloadTests
{
    [Fact]
    public void LocalWsl2SnapshotCarriesNormalizedProfileAndWsl2()
    {
        var settings = new ConnectionSettings
        {
            Mode = ConnectionSettings.BackendMode.LocalWSL2,
            ActiveProfile = "  project-a  ",
            SshTarget = "ignored@example"
        };

        var target = settings.CaptureDockerTarget();

        Assert.Equal("project-a", target.Profile);
        Assert.True(target.Wsl2);
        Assert.Empty(target.Host);
    }

    [Fact]
    public void RemoteSnapshotCarriesProfileAndSshTargetWithoutWsl2()
    {
        var settings = new ConnectionSettings
        {
            Mode = ConnectionSettings.BackendMode.RemoteSSH,
            ActiveProfile = "remote-profile",
            SshTarget = "  user@remote  "
        };

        var target = settings.CaptureDockerTarget();

        Assert.Equal("remote-profile", target.Profile);
        Assert.Equal("user@remote", target.Host);
        Assert.False(target.Wsl2);
    }

    [Fact]
    public void BlankProfileNormalizesToDefault()
    {
        Assert.Equal("default", ConnectionSettings.NormalizeProfile("  "));
    }

    [Fact]
    public void DockerScopeCopiesEveryProviderField()
    {
        var request = DaemonRequestFactory.DockerScope(
            new DockerTarget("profile", "user@host", false), all: true);

        Assert.Equal("profile", request.Profile);
        Assert.Equal("user@host", request.Host);
        Assert.False(request.Wsl2);
        Assert.True(request.All);
    }

    [Fact]
    public void ColimaMaintenanceRequestsCarryNormalizedProfile()
    {
        var update = DaemonRequestFactory.Profile("  project-a  ");
        var prune = DaemonRequestFactory.Prune("  project-a  ", all: true);

        Assert.Equal("project-a", update.Profile);
        Assert.Equal("project-a", prune.Profile);
        Assert.True(prune.All);
    }

    [Fact]
    public void IdAndNameRequestsCopyProviderFields()
    {
        var target = new DockerTarget("profile", string.Empty, true);

        var id = DaemonRequestFactory.Id("abc", target);
        var name = DaemonRequestFactory.Name("nginx:latest", target);

        Assert.Equal(("abc", "profile", true), (id.Id, id.Profile, id.Wsl2));
        Assert.Equal(("nginx:latest", "profile", true), (name.Name, name.Profile, name.Wsl2));
    }

    [Fact]
    public void ContainerMutationCopiesHostAndWsl2Selection()
    {
        var remote = DaemonRequestFactory.ContainerAction(
            "container", "stop", new DockerTarget("p", "user@host", false));
        var local = DaemonRequestFactory.CreateContainer(
            "web", "nginx", new DockerTarget("p", string.Empty, true));

        Assert.Equal("user@host", remote.Host);
        Assert.False(remote.Wsl2);
        Assert.Equal("p", local.Profile);
        Assert.True(local.Wsl2);
    }

    [Fact]
    public void ExtendedProviderRequestsCopyHostAndWsl2Selection()
    {
        var remote = new DockerTarget("remote-profile", "user@host", false);
        var wsl2 = new DockerTarget("wsl-profile", string.Empty, true);

        var rename = DaemonRequestFactory.RenameContainer("container", "renamed", remote);
        var tag = DaemonRequestFactory.TagImage("image", "repo", "tag", wsl2);
        var search = DaemonRequestFactory.SearchImages("alpine", remote);
        var connect = DaemonRequestFactory.NetworkContainer("network", "container", wsl2);

        Assert.Equal(("remote-profile", "user@host", false), (rename.Profile, rename.Host, rename.Wsl2));
        Assert.Equal(("wsl-profile", string.Empty, true), (tag.Profile, tag.Host, tag.Wsl2));
        Assert.Equal(("remote-profile", "user@host", false), (search.Profile, search.Host, search.Wsl2));
        Assert.Equal(("wsl-profile", string.Empty, true), (connect.Profile, connect.Host, connect.Wsl2));
    }

    [Theory]
    [InlineData("http://127.0.0.1:50051", "http://127.0.0.1:50051")]
    [InlineData("http://localhost:50051/ignored", "http://localhost:50051")]
    public void DaemonEndpointAcceptsOnlyNormalizedLoopback(string input, string expected)
    {
        Assert.Equal(expected, DaemonEndpoint.RequireLoopback(input));
    }

    [Theory]
    [InlineData("http://0.0.0.0:50051")]
    [InlineData("http://192.168.1.2:50051")]
    [InlineData("https://127.0.0.1:50051")]
    [InlineData("not-an-address")]
    public void DaemonEndpointRejectsNonLoopbackOrInvalidAddresses(string input)
    {
        Assert.Throws<ArgumentException>(() => DaemonEndpoint.RequireLoopback(input));
    }
}
