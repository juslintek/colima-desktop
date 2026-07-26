using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;

namespace ColimaDesktop.Windows.Services;

/// <summary>
/// Detects, installs, and tracks colima prerequisites on Windows.
/// On Windows the colima stack runs inside WSL2, so the required components are:
///   - WSL2 (Windows feature + kernel update)
///   - Docker Desktop for Windows (or a WSL2 Docker distribution)
///   - colima-daemon binary (the Go daemon that bridges gRPC ↔ colima)
/// Daemon installation and updates are delegated to the trusted application package source.
/// </summary>
public sealed partial class DependencyManager : ObservableObject
{
    /// <summary>Represents a single tracked dependency with its install state.</summary>
    public sealed partial class Dependency : ObservableObject
    {
        public string Name { get; }
        public string Description { get; }

        [ObservableProperty] private bool _isInstalled;
        [ObservableProperty] private string _installedVersion = string.Empty;
        [ObservableProperty] private string _latestVersion = string.Empty;
        [ObservableProperty] private bool _isChecking;
        [ObservableProperty] private bool _isInstalling;
        [ObservableProperty] private string _statusMessage = string.Empty;

        public bool UpdateAvailable =>
            !string.IsNullOrEmpty(InstalledVersion) &&
            !string.IsNullOrEmpty(LatestVersion) &&
            InstalledVersion != LatestVersion;

        public Dependency(string name, string description)
        {
            Name = name;
            Description = description;
        }
    }

    [ObservableProperty] private bool _isReady;
    [ObservableProperty] private bool _isChecking;
    [ObservableProperty] private string _overallStatus = "Not checked";

    public IReadOnlyList<Dependency> Dependencies { get; } = new List<Dependency>
    {
        new("WSL2", "Windows Subsystem for Linux 2 — required to run colima inside Windows"),
        new("Docker", "Docker Engine inside WSL2 (or Docker Desktop for Windows)"),
        new("colima-daemon", "Colima Desktop Go daemon — bridges the UI to colima over gRPC"),
    };

    // Convenience typed accessors
    private Dependency Wsl2Dep => (Dependency)Dependencies[0];
    private Dependency DockerDep => (Dependency)Dependencies[1];
    private Dependency DaemonDep => (Dependency)Dependencies[2];

    // ─── Detection ───────────────────────────────────────────────────────────

    /// <summary>Runs all detection checks in parallel and updates <see cref="IsReady"/>.</summary>
    public async Task CheckAllAsync(CancellationToken ct = default)
    {
        IsChecking = true;
        OverallStatus = "Checking dependencies…";
        try
        {
            await Task.WhenAll(
                CheckWsl2Async(ct),
                CheckDockerAsync(ct),
                CheckDaemonAsync(ct)
            );
            UpdateOverall();
        }
        finally
        {
            IsChecking = false;
        }
    }

    private async Task CheckWsl2Async(CancellationToken ct)
    {
        Wsl2Dep.IsChecking = true;
        Wsl2Dep.StatusMessage = "Detecting…";
        try
        {
            var result = await RunProcessAsync("wsl.exe", "--status", ct);
            Wsl2Dep.IsInstalled = result.ExitCode == 0;
            if (Wsl2Dep.IsInstalled)
            {
                // Try to extract WSL version from output
                Wsl2Dep.InstalledVersion = ParseWslVersion(result.Output);
                Wsl2Dep.StatusMessage = "Installed";
            }
            else
            {
                Wsl2Dep.InstalledVersion = string.Empty;
                Wsl2Dep.StatusMessage = "Not installed";
            }
        }
        catch (OperationCanceledException)
        {
            Wsl2Dep.StatusMessage = "Detection cancelled";
            throw;
        }
        catch (Exception ex)
        {
            Wsl2Dep.IsInstalled = false;
            Wsl2Dep.StatusMessage = $"Detection failed: {ex.Message}";
        }
        finally
        {
            Wsl2Dep.IsChecking = false;
        }
    }

    private async Task CheckDockerAsync(CancellationToken ct)
    {
        DockerDep.IsChecking = true;
        DockerDep.StatusMessage = "Detecting…";
        try
        {
            // Try docker.exe (Docker Desktop) first, then wsl docker
            var result = await RunProcessAsync("docker.exe", "--version", ct);
            if (result.ExitCode == 0)
            {
                DockerDep.IsInstalled = true;
                DockerDep.InstalledVersion = ParseDockerVersion(result.Output);
                DockerDep.StatusMessage = "Installed";
            }
            else
            {
                // Fall back: check via WSL
                var wslResult = await RunProcessAsync("wsl.exe", "--exec docker --version", ct);
                DockerDep.IsInstalled = wslResult.ExitCode == 0;
                DockerDep.InstalledVersion = DockerDep.IsInstalled ? ParseDockerVersion(wslResult.Output) : string.Empty;
                DockerDep.StatusMessage = DockerDep.IsInstalled ? "Installed (WSL)" : "Not installed";
            }
        }
        catch (OperationCanceledException)
        {
            DockerDep.StatusMessage = "Detection cancelled";
            throw;
        }
        catch (Exception ex)
        {
            DockerDep.IsInstalled = false;
            DockerDep.StatusMessage = $"Detection failed: {ex.Message}";
        }
        finally
        {
            DockerDep.IsChecking = false;
        }
    }

    private async Task CheckDaemonAsync(CancellationToken ct)
    {
        await Task.Yield();
        ct.ThrowIfCancellationRequested();
        DaemonDep.IsChecking = true;
        DaemonDep.StatusMessage = "Detecting…";
        try
        {
            // Only trust the daemon shipped beside the application. PATH lookup can resolve an
            // unrelated executable and must never be used for automatic startup.
            bool exists = TryGetValidatedDaemonPath(out var localPath);
            DaemonDep.IsInstalled = exists;
            if (exists)
            {
                var version = FileVersionInfo.GetVersionInfo(localPath).FileVersion;
                DaemonDep.InstalledVersion = string.IsNullOrWhiteSpace(version) ? "bundled" : version;
                DaemonDep.StatusMessage = $"Installed at {localPath}";
            }
            else
            {
                DaemonDep.InstalledVersion = string.Empty;
                DaemonDep.StatusMessage = "Not installed";
            }
        }
        catch (Exception ex)
        {
            DaemonDep.IsInstalled = false;
            DaemonDep.StatusMessage = $"Detection failed: {ex.Message}";
        }
        finally
        {
            DaemonDep.IsChecking = false;
        }
    }

    // ─── Installation ─────────────────────────────────────────────────────────

    /// <summary>Installs WSL2 via winget / DISM and prompts for restart if needed.</summary>
    public async Task InstallWsl2Async(IProgress<string>? progress = null, CancellationToken ct = default)
    {
        Wsl2Dep.IsInstalling = true;
        Wsl2Dep.StatusMessage = "Installing WSL2…";
        progress?.Report("Installing WSL2 via winget…");
        try
        {
            // winget install --id Microsoft.WSL -e --source winget
            var result = await RunProcessAsync(
                "winget.exe",
                "install --id Microsoft.WSL -e --source winget --accept-package-agreements --accept-source-agreements",
                ct);
            if (result.ExitCode == 0)
            {
                Wsl2Dep.IsInstalled = true;
                Wsl2Dep.StatusMessage = "Installed — restart may be required";
                progress?.Report("WSL2 installed. A system restart may be required.");
            }
            else
            {
                Wsl2Dep.StatusMessage = $"Install failed: {result.Error}";
                progress?.Report($"WSL2 install failed: {result.Error}");
            }
        }
        finally
        {
            Wsl2Dep.IsInstalling = false;
        }
    }

    /// <summary>
    /// Installs Docker Desktop for Windows via winget.
    /// Falls back to instructions for manual install if winget fails.
    /// </summary>
    public async Task InstallDockerAsync(IProgress<string>? progress = null, CancellationToken ct = default)
    {
        DockerDep.IsInstalling = true;
        DockerDep.StatusMessage = "Installing Docker Desktop…";
        progress?.Report("Installing Docker Desktop via winget…");
        try
        {
            var result = await RunProcessAsync(
                "winget.exe",
                "install --id Docker.DockerDesktop -e --source winget --accept-package-agreements --accept-source-agreements",
                ct);
            if (result.ExitCode == 0)
            {
                DockerDep.IsInstalled = true;
                DockerDep.StatusMessage = "Installed";
                progress?.Report("Docker Desktop installed.");
            }
            else
            {
                DockerDep.StatusMessage = $"Install failed (exit {result.ExitCode}). Install manually from https://docs.docker.com/desktop/install/windows-install/";
                progress?.Report(DockerDep.StatusMessage);
            }
        }
        finally
        {
            DockerDep.IsInstalling = false;
        }
    }

    /// <summary>
    /// Automatic daemon downloads are intentionally disabled. The application only starts a
    /// daemon that was installed beside the app by a trusted package/install process.
    /// </summary>
    public async Task InstallDaemonAsync(IProgress<string>? progress = null, CancellationToken ct = default)
    {
        DaemonDep.IsInstalling = true;
        DaemonDep.StatusMessage = "Automatic download disabled";
        progress?.Report("Automatic daemon downloads are disabled for safety.");
        try
        {
            await Task.Yield();
            ct.ThrowIfCancellationRequested();
            DaemonDep.StatusMessage =
                "Install a trusted colima-desktop package containing colima-daemon.exe beside the app, then check again.";
            progress?.Report(DaemonDep.StatusMessage);
        }
        finally
        {
            DaemonDep.IsInstalling = false;
        }
    }

    /// <summary>Explains where trusted package updates are managed.</summary>
    public async Task CheckForUpdatesAsync(CancellationToken ct = default)
    {
        await Task.Yield();
        ct.ThrowIfCancellationRequested();
        OverallStatus = "Update checks are handled by the trusted application package source.";
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private void UpdateOverall()
    {
        bool allInstalled = Wsl2Dep.IsInstalled && DockerDep.IsInstalled && DaemonDep.IsInstalled;
        IsReady = allInstalled;
        OverallStatus = allInstalled
            ? "All dependencies are installed"
            : "Some dependencies are missing — use the Onboarding screen to install them";
    }

    public bool TryGetValidatedDaemonPath(out string path)
    {
        var baseDirectory = Path.GetFullPath(AppContext.BaseDirectory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;
        var candidate = Path.GetFullPath(Path.Combine(baseDirectory, "colima-daemon.exe"));
        if (!candidate.StartsWith(baseDirectory, StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(candidate) ||
            (File.GetAttributes(candidate) & FileAttributes.ReparsePoint) != 0)
        {
            path = string.Empty;
            return false;
        }

        path = candidate;
        return true;
    }

    private record ProcessResult(int ExitCode, string Output, string Error);

    private static async Task<ProcessResult> RunProcessAsync(string executable, string arguments, CancellationToken ct)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(15));

        var psi = new ProcessStartInfo(executable, arguments)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        process.Start();

        var outputTask = process.StandardOutput.ReadToEndAsync(cts.Token);
        var errorTask = process.StandardError.ReadToEndAsync(cts.Token);
        await process.WaitForExitAsync(cts.Token);

        return new ProcessResult(process.ExitCode, await outputTask, await errorTask);
    }

    private static string ParseWslVersion(string output)
    {
        // "WSL version: 2.0.9.0" or "Version de WSL : …"
        foreach (var line in output.Split('\n'))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("WSL version:", StringComparison.OrdinalIgnoreCase) ||
                trimmed.StartsWith("WSL-Version:", StringComparison.OrdinalIgnoreCase))
            {
                return trimmed.Split(':')[^1].Trim();
            }
        }
        return "2";
    }

    private static string ParseDockerVersion(string output)
    {
        // "Docker version 26.1.3, build b72abbb"
        var idx = output.IndexOf("version", StringComparison.OrdinalIgnoreCase);
        if (idx >= 0)
        {
            var rest = output[(idx + 7)..].TrimStart();
            var end = rest.IndexOf(',');
            return end >= 0 ? rest[..end].Trim() : rest.Trim();
        }
        return output.Trim();
    }
}
