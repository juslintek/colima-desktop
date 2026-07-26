using System;
using Colimaui;

namespace ColimaDesktop.Windows.Services;

/// <summary>Creates request payloads from one captured profile/provider target.</summary>
public static class DaemonRequestFactory
{
    public static ProfileRequest Profile(string profile) => new()
    {
        Profile = ConnectionSettings.NormalizeProfile(profile)
    };

    public static PruneRequest Prune(string profile, bool all = false) => new()
    {
        Profile = ConnectionSettings.NormalizeProfile(profile),
        All = all
    };

    public static DockerScope DockerScope(DockerTarget target, bool all = false) => new()
    {
        Profile = target.Profile,
        Host = target.Host,
        Wsl2 = target.Wsl2,
        All = all
    };

    public static IdRequest Id(string id, DockerTarget target) => new()
    {
        Id = Required(id, nameof(id)),
        Profile = target.Profile,
        Host = target.Host,
        Wsl2 = target.Wsl2
    };

    public static NameRequest Name(string name, DockerTarget target) => new()
    {
        Name = Required(name, nameof(name)),
        Profile = target.Profile,
        Host = target.Host,
        Wsl2 = target.Wsl2
    };

    public static ContainerActionRequest ContainerAction(string id, string action, DockerTarget target) => new()
    {
        Id = Required(id, nameof(id)),
        Action = Required(action, nameof(action)),
        Profile = target.Profile,
        Host = target.Host,
        Wsl2 = target.Wsl2
    };

    public static CreateContainerRequest CreateContainer(string name, string image, DockerTarget target) => new()
    {
        Name = Required(name, nameof(name)),
        Image = Required(image, nameof(image)),
        Profile = target.Profile,
        Host = target.Host,
        Wsl2 = target.Wsl2
    };

    public static RenameRequest RenameContainer(string id, string newName, DockerTarget target) => new()
    {
        Id = Required(id, nameof(id)),
        NewName = Required(newName, nameof(newName)),
        Profile = target.Profile,
        Host = target.Host,
        Wsl2 = target.Wsl2
    };

    public static TagRequest TagImage(string name, string repo, string tag, DockerTarget target) => new()
    {
        Name = Required(name, nameof(name)),
        Repo = Required(repo, nameof(repo)),
        Tag = Required(tag, nameof(tag)),
        Profile = target.Profile,
        Host = target.Host,
        Wsl2 = target.Wsl2
    };

    public static SearchRequest SearchImages(string term, DockerTarget target) => new()
    {
        Term = Required(term, nameof(term)),
        Profile = target.Profile,
        Host = target.Host,
        Wsl2 = target.Wsl2
    };

    public static NetworkContainerRequest NetworkContainer(string networkId, string containerId, DockerTarget target) => new()
    {
        NetworkId = Required(networkId, nameof(networkId)),
        ContainerId = Required(containerId, nameof(containerId)),
        Profile = target.Profile,
        Host = target.Host,
        Wsl2 = target.Wsl2
    };

    public static string Required(string? value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException("A non-empty value is required.", parameterName);
        return value.Trim();
    }

}
