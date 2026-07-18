// UIAutomation explorer for Colima Desktop Windows (WinUI 3)
// Uses FlaUI.UIA3 to traverse the live automation tree.
// Outputs exploration/windows/ground-truth.json in the unified schema.
//
// Usage: explore-uia.exe <app-exe-path> <output-json-path> [screenshot-dir]
//   app-exe-path      Absolute path to ColimaDesktop.Windows.exe
//   output-json-path  Where to write ground-truth.json
//   screenshot-dir    Optional dir for per-surface PNG screenshots
//
// Exits 0 on success (element_count > 0), 1 on failure.

using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Capturing;
using FlaUI.Core.Definitions;
using FlaUI.UIA3;

namespace ColimaDesktop.Explorer;

internal static class Program
{
    // Navigation items: (AutomationId x:Name, display label)
    // AutomationId in WinUI3: x:Name becomes AutomationId on the element.
    private static readonly (string AutomationId, string Label)[] NavigationItems =
    [
        ("NavDashboard",     "Dashboard"),
        ("NavContainers",    "Containers"),
        ("NavImages",        "Images"),
        ("NavVolumes",       "Volumes"),
        ("NavNetworks",      "Networks"),
        ("NavMachines",      "Machines"),
        ("NavKubernetes",    "Kubernetes"),
        ("NavConfiguration", "Configuration"),
        ("NavRuntime",       "Runtime"),
        ("NavAIWorkloads",   "AI Workloads"),
        ("NavProfiles",      "Profiles"),
        ("NavMonitoring",    "Monitoring"),
        ("NavSettings",      "Settings & Deps"),
    ];

    private static readonly TimeSpan AppStartTimeout   = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan NavigationSettle  = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan ElementFindTimeout = TimeSpan.FromSeconds(8);

    internal static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine("Usage: explore-uia <app-exe> <output-json> [screenshot-dir]");
            return 1;
        }

        var appExePath     = args[0];
        var outputJsonPath = args[1];
        var screenshotDir  = args.Length >= 3 ? args[2] : null;

        if (!File.Exists(appExePath))
        {
            Console.Error.WriteLine($"App exe not found: {appExePath}");
            return 1;
        }

        if (screenshotDir != null)
            Directory.CreateDirectory(screenshotDir);

        Console.WriteLine($"[explorer] Launching: {appExePath}");

        Application?   app       = null;
        UIA3Automation? automation = null;

        try
        {
            automation = new UIA3Automation();
            var cf     = automation.ConditionFactory;

            // Launch the app
            var psi = new ProcessStartInfo(appExePath)
            {
                UseShellExecute  = true,  // required for WinUI3 unpackaged bootstrap
                WorkingDirectory = Path.GetDirectoryName(appExePath)!,
            };
            app = Application.Launch(psi);

            Console.WriteLine($"[explorer] PID={app.ProcessId} — waiting for main window...");

            // Poll for the main window
            Window? mainWindow = null;
            var deadline = DateTime.UtcNow + AppStartTimeout;
            while (DateTime.UtcNow < deadline)
            {
                try
                {
                    var windows = app.GetAllTopLevelWindows(automation);
                    mainWindow = windows.FirstOrDefault(w =>
                    {
                        try { return !string.IsNullOrEmpty(w.Title); }
                        catch { return false; }
                    });
                    if (mainWindow != null)
                    {
                        Console.WriteLine($"[explorer] Window found: '{mainWindow.Title}'");
                        break;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[explorer] Waiting... {ex.Message}");
                }
                Thread.Sleep(500);
            }

            if (mainWindow == null)
            {
                Console.Error.WriteLine("[explorer] ERROR: Main window did not appear within timeout.");
                return 1;
            }

            // Allow NavigationView.Loaded to fire
            Thread.Sleep(2000);

            // Capture process metadata
            var procInfo    = Process.GetProcessById(app.ProcessId);
            var processName = procInfo.ProcessName;
            var windowTitle = SafeGet(() => mainWindow.Title, "");
            var autoId      = SafeGet(() => mainWindow.AutomationId, "");

            Console.WriteLine($"[explorer] title='{windowTitle}' automationId='{autoId}'");

            var surfaces     = new List<SurfaceResult>();
            var captureErrors = new List<string>();

            for (int i = 0; i < NavigationItems.Length; i++)
            {
                var (navId, label) = NavigationItems[i];
                var surfaceKey = navId.Replace("Nav", "").ToLowerInvariant();

                Console.WriteLine($"[explorer] → Navigating to: {label}");

                try
                {
                    // Find nav item by AutomationId (x:Name in XAML)
                    var navItem = WaitForElement(mainWindow, cf, navId, label, ElementFindTimeout);
                    if (navItem == null)
                    {
                        var err = $"Nav item not found: '{label}' (id={navId})";
                        Console.WriteLine($"[explorer] WARN: {err}");
                        captureErrors.Add(err);
                        surfaces.Add(EmptySurface(surfaceKey, label, err));
                        continue;
                    }

                    // Invoke navigation
                    navItem.Click();
                    Thread.Sleep((int)NavigationSettle.TotalMilliseconds);

                    // Traverse full window tree
                    var elements = new List<ElementRecord>();
                    TraverseElement(mainWindow, elements, 0, label);

                    // Screenshot
                    string? screenshotPath = null;
                    if (screenshotDir != null)
                    {
                        screenshotPath = Path.Combine(screenshotDir, $"{(i + 1):D4}-{surfaceKey}.png");
                        TakeScreenshot(mainWindow, screenshotPath);
                    }

                    Console.WriteLine($"[explorer]   {label}: {elements.Count} elements");

                    surfaces.Add(new SurfaceResult
                    {
                        Surface        = surfaceKey,
                        SurfaceLabel   = label,
                        ElementCount   = elements.Count,
                        Elements       = elements,
                        Errors         = [],
                        ScreenshotPath = screenshotPath,
                    });
                }
                catch (Exception ex)
                {
                    var err = $"Surface '{label}': {ex.GetType().Name}: {ex.Message}";
                    Console.WriteLine($"[explorer] ERROR: {err}");
                    captureErrors.Add(err);
                    surfaces.Add(EmptySurface(surfaceKey, label, err));
                }
            }

            var totalElements = surfaces.Sum(s => s.ElementCount);

            var capture = new GroundTruthCapture
            {
                Platform          = "Windows",
                Timestamp         = DateTime.UtcNow.ToString("O"),
                Host = new HostInfo
                {
                    OsVersion = Environment.OSVersion.VersionString,
                    Arch      = Environment.Is64BitOperatingSystem ? "x64" : "x86",
                },
                App = new AppInfo
                {
                    Name       = windowTitle.Length > 0 ? windowTitle : "Colima Desktop",
                    ExePath    = appExePath,
                    LaunchMode = "unpackaged WinUI3 (WindowsPackageType=None)",
                },
                ExplorationMethod = "FlaUI 4.0.0 / UIA3 (UIAutomationClient COM)",
                Window = new WindowMetadata
                {
                    ProcessId   = app.ProcessId,
                    ProcessName = processName,
                    WindowTitle = windowTitle,
                    AutomationId = autoId,
                    BoundingBox = SafeGetRect(mainWindow),
                },
                SurfacesExplored  = surfaces.Count(s => s.ElementCount > 0),
                TotalElements     = totalElements,
                CaptureErrors     = captureErrors,
                Surfaces          = surfaces,
            };

            var jsonOptions = new JsonSerializerOptions
            {
                WriteIndented = true,
                DefaultIgnoreCondition = JsonIgnoreCondition.Never,
            };
            var json = JsonSerializer.Serialize(capture, jsonOptions);

            var outputDir = Path.GetDirectoryName(outputJsonPath);
            if (outputDir != null)
                Directory.CreateDirectory(outputDir);
            File.WriteAllText(outputJsonPath, json);

            Console.WriteLine($"[explorer] Written: {outputJsonPath}  ({totalElements} elements)");

            if (totalElements == 0)
            {
                Console.Error.WriteLine("[explorer] FAIL: zero elements captured.");
                return 1;
            }

            Console.WriteLine("[explorer] SUCCESS");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[explorer] FATAL: {ex}");
            return 1;
        }
        finally
        {
            try { app?.Close(); } catch { /* best-effort */ }
            automation?.Dispose();
        }
    }

    // ─── Helpers ───────────────────────────────────────────────────────────

    private static AutomationElement? WaitForElement(
        Window window,
        FlaUI.Core.Conditions.ConditionFactory cf,
        string automationId,
        string name,
        TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                // Try AutomationId first (x:Name → AutomationId in WinUI3)
                var el = window.FindFirstDescendant(cf.ByAutomationId(automationId));
                if (el != null) return el;

                // Fallback: Name match
                el = window.FindFirstDescendant(cf.ByName(name));
                if (el != null) return el;
            }
            catch { /* retry */ }
            Thread.Sleep(300);
        }
        return null;
    }

    private static void TraverseElement(
        AutomationElement element,
        List<ElementRecord> records,
        int depth,
        string surface,
        int maxDepth = 25)
    {
        if (depth > maxDepth) return;

        try
        {
            var record = new ElementRecord
            {
                Index             = records.Count,
                ControlType       = SafeGet(() => element.ControlType.ToString(), "Unknown"),
                Name              = SafeGet(() => element.Name ?? "", ""),
                AutomationId      = SafeGet(() => element.AutomationId ?? "", ""),
                ClassName         = SafeGet(() => element.ClassName ?? "", ""),
                IsEnabled         = SafeGet(() => element.IsEnabled, true),
                IsOffscreen       = SafeGet(() => element.IsOffscreen, false),
                BoundingBox       = SafeGetRect(element),
                SupportedPatterns = GetPatternNames(element),
                Value             = GetValue(element),
                Surface           = surface,
                Depth             = depth,
            };
            records.Add(record);
        }
        catch (Exception ex)
        {
            records.Add(new ElementRecord
            {
                Index             = records.Count,
                ControlType       = "TraversalError",
                Name              = ex.Message,
                AutomationId      = "",
                ClassName         = "",
                IsEnabled         = false,
                IsOffscreen       = false,
                BoundingBox       = null,
                SupportedPatterns = [],
                Value             = null,
                Surface           = surface,
                Depth             = depth,
            });
        }

        // Recurse into children
        AutomationElement[] children;
        try
        {
            children = element.FindAllChildren();
        }
        catch
        {
            return;
        }

        foreach (var child in children)
            TraverseElement(child, records, depth + 1, surface, maxDepth);
    }

    private static List<string> GetPatternNames(AutomationElement element)
    {
        var result = new List<string>();
        try
        {
            var patterns = element.GetSupportedPatterns();
            foreach (var p in patterns)
            {
                var name = p?.ToString();
                if (name != null) result.Add(name);
            }
        }
        catch { /* ignore */ }
        return result;
    }

    private static string? GetValue(AutomationElement element)
    {
        try
        {
            var vp = element.Patterns.Value;
            if (vp.IsSupported)
                return vp.Pattern.Value.Value;
        }
        catch { /* no value pattern */ }
        return null;
    }

    private static BoundingRect? SafeGetRect(AutomationElement element)
    {
        try
        {
            var r = element.BoundingRectangle;
            return new BoundingRect { X = (int)r.X, Y = (int)r.Y, Width = (int)r.Width, Height = (int)r.Height };
        }
        catch { return null; }
    }

    private static void TakeScreenshot(Window window, string outputPath)
    {
        try
        {
            using var img = Capture.Element(window);
            img.ToFile(outputPath);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[explorer] Screenshot failed: {ex.Message}");
        }
    }

    private static SurfaceResult EmptySurface(string key, string label, string error) =>
        new SurfaceResult
        {
            Surface        = key,
            SurfaceLabel   = label,
            ElementCount   = 0,
            Elements       = [],
            Errors         = [error],
            ScreenshotPath = null,
        };

    private static T SafeGet<T>(Func<T> fn, T fallback)
    {
        try { return fn(); }
        catch { return fallback; }
    }

    // ─── JSON schema ────────────────────────────────────────────────────────

    private record GroundTruthCapture
    {
        [JsonPropertyName("platform")]           public required string Platform          { get; init; }
        [JsonPropertyName("timestamp")]          public required string Timestamp         { get; init; }
        [JsonPropertyName("host")]               public required HostInfo Host            { get; init; }
        [JsonPropertyName("app")]                public required AppInfo App              { get; init; }
        [JsonPropertyName("exploration_method")] public required string ExplorationMethod { get; init; }
        [JsonPropertyName("window")]             public required WindowMetadata Window    { get; init; }
        [JsonPropertyName("surfaces_explored")]  public required int SurfacesExplored    { get; init; }
        [JsonPropertyName("total_elements")]     public required int TotalElements        { get; init; }
        [JsonPropertyName("capture_errors")]     public required List<string> CaptureErrors { get; init; }
        [JsonPropertyName("surfaces")]           public required List<SurfaceResult> Surfaces { get; init; }
    }

    private record HostInfo
    {
        [JsonPropertyName("os_version")] public required string OsVersion { get; init; }
        [JsonPropertyName("arch")]       public required string Arch       { get; init; }
    }

    private record AppInfo
    {
        [JsonPropertyName("name")]        public required string Name       { get; init; }
        [JsonPropertyName("exe_path")]    public required string ExePath    { get; init; }
        [JsonPropertyName("launch_mode")] public required string LaunchMode { get; init; }
    }

    private record WindowMetadata
    {
        [JsonPropertyName("process_id")]    public required int    ProcessId    { get; init; }
        [JsonPropertyName("process_name")]  public required string ProcessName  { get; init; }
        [JsonPropertyName("window_title")]  public required string WindowTitle  { get; init; }
        [JsonPropertyName("automation_id")] public required string AutomationId { get; init; }
        [JsonPropertyName("bounding_box")]  public BoundingRect? BoundingBox    { get; init; }
    }

    private record BoundingRect
    {
        [JsonPropertyName("x")]      public int X      { get; init; }
        [JsonPropertyName("y")]      public int Y      { get; init; }
        [JsonPropertyName("width")]  public int Width  { get; init; }
        [JsonPropertyName("height")] public int Height { get; init; }
    }

    private record SurfaceResult
    {
        [JsonPropertyName("surface")]          public required string Surface        { get; init; }
        [JsonPropertyName("surface_label")]    public required string SurfaceLabel   { get; init; }
        [JsonPropertyName("element_count")]    public required int    ElementCount   { get; init; }
        [JsonPropertyName("elements")]         public required List<ElementRecord> Elements { get; init; }
        [JsonPropertyName("errors")]           public required List<string> Errors   { get; init; }
        [JsonPropertyName("screenshot_path")]  public string? ScreenshotPath         { get; init; }
    }

    private record ElementRecord
    {
        [JsonPropertyName("index")]              public int    Index             { get; init; }
        [JsonPropertyName("control_type")]       public required string ControlType      { get; init; }
        [JsonPropertyName("name")]               public required string Name              { get; init; }
        [JsonPropertyName("automation_id")]      public required string AutomationId      { get; init; }
        [JsonPropertyName("class_name")]         public required string ClassName         { get; init; }
        [JsonPropertyName("is_enabled")]         public bool   IsEnabled          { get; init; }
        [JsonPropertyName("is_offscreen")]       public bool   IsOffscreen        { get; init; }
        [JsonPropertyName("bounding_box")]       public BoundingRect? BoundingBox { get; init; }
        [JsonPropertyName("supported_patterns")] public required List<string> SupportedPatterns { get; init; }
        [JsonPropertyName("value")]              public string? Value             { get; init; }
        [JsonPropertyName("surface")]            public required string Surface   { get; init; }
        [JsonPropertyName("depth")]              public int    Depth              { get; init; }
    }
}
