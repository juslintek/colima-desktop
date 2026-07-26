using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

namespace ColimaDesktop.Windows.Services;

/// <summary>Owns bounded health checks and an optional trusted local daemon child process.</summary>
public sealed class DaemonConnectionManager : IDisposable
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private Process? _localDaemon;

    public async Task<DaemonHealthResult> ConnectAsync(
        IDaemonClient client,
        ConnectionSettings settings,
        DependencyManager dependencies,
        bool allowTrustedLocalStart,
        CancellationToken ct = default)
    {
        await _gate.WaitAsync(ct);
        try
        {
            settings.IsConnected = false;
            settings.ConnectionStatus = "Connecting to daemon…";

            try
            {
                client.Reconnect(settings.DaemonAddress);
            }
            catch (Exception ex)
            {
                var invalid = new DaemonHealthResult(false, ex.Message);
                Apply(settings, invalid);
                return invalid;
            }

            var result = await client.CheckHealthAsync(TimeSpan.FromSeconds(3), ct);
            if (result.IsConnected || !allowTrustedLocalStart ||
                settings.Mode != ConnectionSettings.BackendMode.LocalWSL2)
            {
                Apply(settings, result);
                return result;
            }

            if (!dependencies.TryGetValidatedDaemonPath(out var daemonPath))
            {
                result = new DaemonHealthResult(false,
                    $"{result.Message}. No trusted bundled daemon is available to start.");
                Apply(settings, result);
                return result;
            }

            try
            {
                StartTrustedLocalDaemon(daemonPath, settings.DaemonAddress);
            }
            catch (Exception ex)
            {
                result = new DaemonHealthResult(false, $"Could not start the trusted local daemon: {ex.Message}");
                Apply(settings, result);
                return result;
            }
            for (var attempt = 0; attempt < 8; attempt++)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(250), ct);
                result = await client.CheckHealthAsync(TimeSpan.FromSeconds(1), ct);
                if (result.IsConnected)
                {
                    Apply(settings, result);
                    return result;
                }

                if (_localDaemon?.HasExited == true)
                    break;
            }

            result = new DaemonHealthResult(false,
                $"The trusted local daemon did not become healthy at {client.CurrentAddress}.");
            Apply(settings, result);
            return result;
        }
        catch (OperationCanceledException)
        {
            Apply(settings, new DaemonHealthResult(false, "Connection attempt cancelled."));
            throw;
        }
        finally
        {
            _gate.Release();
        }
    }

    private void StartTrustedLocalDaemon(string path, string address)
    {
        if (_localDaemon is { HasExited: false })
            return;

        _localDaemon?.Dispose();
        var startInfo = new ProcessStartInfo(path)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = AppContext.BaseDirectory
        };
        startInfo.ArgumentList.Add("--listen");
        startInfo.ArgumentList.Add(DaemonEndpoint.ListenArgument(address));
        _localDaemon = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Windows did not start the trusted local daemon process.");
    }

    private static void Apply(ConnectionSettings settings, DaemonHealthResult result)
    {
        settings.IsConnected = result.IsConnected;
        settings.ConnectionStatus = result.Message;
    }

    public void Dispose()
    {
        try
        {
            if (_localDaemon is { HasExited: false })
                _localDaemon.Kill(entireProcessTree: true);
        }
        catch (InvalidOperationException)
        {
            // Process exited between the state check and cleanup.
        }
        _localDaemon?.Dispose();
        _gate.Dispose();
    }
}
