using System;

namespace ColimaDesktop.Windows.Services;

public static class DaemonEndpoint
{
    public static string RequireLoopback(string address)
    {
        if (!Uri.TryCreate(address?.Trim(), UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttp || uri.Port is <= 0 or > 65535 ||
            !(uri.Host.Equals("127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
              uri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase)))
        {
            throw new ArgumentException(
                "The daemon endpoint must be an HTTP loopback address such as http://127.0.0.1:50051.",
                nameof(address));
        }

        return uri.GetLeftPart(UriPartial.Authority);
    }

    public static string ListenArgument(string address)
    {
        var normalized = RequireLoopback(address);
        var uri = new Uri(normalized);
        return $"tcp:127.0.0.1:{uri.Port}";
    }
}
