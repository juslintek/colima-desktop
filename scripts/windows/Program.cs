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

    private static readonly TimeSpan AppStartTimeout    = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan NavigationSettle   = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan ElementFindTimeout = TimeSpan.FromSeconds(8);

    // Known OS error dialog title substrings that indicate the app failed to start.
    // These are checked BEFORE spending ElementFindTimeout on each nav item.
    private static readonly string[] ErrorDialogTitles =
    [
        "could not be started",
        "Application Error",
        "has stopped working",
        "stopped working",
        "not a valid Win32 application",
        "side-by-side configuration is incorrect",
    ];

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

        Application?    app        = null;
        UIA3Automation? automation  = null;

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
                // Emit diagnostics before bailing out
                WriteLaunchDiagnostics(app, appExePath, "No window appeared within timeout");
                WriteFailJson(outputJsonPath, "No window appeared within timeout", app.ProcessId, appExePath);
                return 1;
            }

            // ── CRITICAL: Detect OS error dialog and abort immediately ────────
            // When the WinAppSDK bootstrap fails, Windows shows a dialog titled
            // "ColimaDesktop.Windows.exe - This application could not be started".
            // Traversing it wastes minutes finding zero app elements.
            var windowTitle = SafeGet(() => mainWindow.Title, "");
            if (IsErrorDialog(windowTitle))
            {
                var msg = $"OS error dialog detected: '{windowTitle}'";
                Console.Error.WriteLine($"[explorer] FATAL: {msg}");
                Console.Error.WriteLine("[explorer] The app failed to bootstrap (WinAppSDK runtime issue).");
                Console.Error.WriteLine("[explorer] Ensure the publish used -p:WindowsAppSDKSelfContained=true");

                // Dismiss the dialog so it doesn't linger
                try { mainWindow.Close(); } catch { /* best effort */ }

                // Emit diagnostics before bailing
                WriteLaunchDiagnostics(app, appExePath, msg);
                WriteFailJson(outputJsonPath, msg, app.ProcessId, appExePath);
                return 1;
            }

            // Allow NavigationView.Loaded to fire
            Thread.Sleep(2000);

            // Capture process metadata
            Process? procInfo    = null;
            string   processName = "";
            try { procInfo = Process.GetProcessById(app.ProcessId); processName = procInfo.ProcessName; }
            catch { /* process may have exited */ }

            var autoId = SafeGet(() => mainWindow.AutomationId, "");

            Console.WriteLine($"[explorer] title='{windowTitle}' automationId='{autoId}'");

            var surfaces      = new List<SurfaceResult>();
            var captureErrors = new List<string>();

            for (int i = 0; i < NavigationItems.Length; i++)
            {
                var (navId, label) = NavigationItems[i];
                var surfaceKey = navId.Replace("Nav", "").ToLowerInvariant();

                Console.WriteLine($"[explorer] → Surface {i+1}/13: {label}");

                // Check whether app is still alive before each surface attempt
                try
                {
                    var alive = Process.GetProcessById(app.ProcessId);
                    _ = alive.HasExited; // probe
                }
                catch
                {
                    var err = $"App process (PID {app.ProcessId}) no longer running before '{label}'";
                    Console.Error.WriteLine($"[explorer] FATAL: {err}");
                    captureErrors.Add(err);
                    // Fill remaining surfaces with empty and break
                    for (int j = i; j < NavigationItems.Length; j++)
                    {
                        var (nid, lbl) = NavigationItems[j];
                        surfaces.Add(EmptySurface(nid.Replace("Nav","").ToLowerInvariant(), lbl, err));
                    }
                    break;
                }

                // Re-resolve the main window each iteration to avoid stale UIA element handles.
                // UIA COM objects become invalid after layout changes; always re-fetch before use.
                try
                {
                    var freshWindows = app.GetAllTopLevelWindows(automation);
                    var freshWindow  = freshWindows.FirstOrDefault(w =>
                    {
                        try { return !string.IsNullOrEmpty(w.Title); }
                        catch { return false; }
                    });
                    if (freshWindow != null)
                        mainWindow = freshWindow;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[explorer]   Re-resolve mainWindow failed ({ex.Message}) — using cached reference");
                }

                // Re-detect error dialog (could appear after initial window opens)
                try
                {
                    var currentTitle = SafeGet(() => mainWindow.Title, "");
                    if (IsErrorDialog(currentTitle))
                    {
                        var err = $"OS error dialog appeared during navigation: '{currentTitle}'";
                        Console.Error.WriteLine($"[explorer] FATAL: {err}");
                        captureErrors.Add(err);
                        for (int j = i; j < NavigationItems.Length; j++)
                        {
                            var (nid, lbl) = NavigationItems[j];
                            surfaces.Add(EmptySurface(nid.Replace("Nav","").ToLowerInvariant(), lbl, err));
                        }
                        break;
                    }
                }
                catch { /* window may have closed */ }

                try
                {
                    // Dashboard (index 0) is the initial selected page — capture it directly
                    // without attempting navigation.  Navigating to an already-selected item
                    // in WinUI3 NavigationView can reset content; skip and just record state.
                    if (i == 0)
                    {
                        Console.WriteLine($"[explorer]   Dashboard: capturing initial selected page (no navigation)");
                        Thread.Sleep(500); // ensure content is stable

                        var elements0 = new List<ElementRecord>();
                        TraverseElement(mainWindow, elements0, 0, label);

                        string? screenshotPath0 = null;
                        if (screenshotDir != null)
                        {
                            screenshotPath0 = Path.Combine(screenshotDir, $"{(i + 1):D4}-{surfaceKey}.png");
                            TakeScreenshot(mainWindow, screenshotPath0);
                        }

                        Console.WriteLine($"[explorer]   {label}: {elements0.Count} elements");
                        surfaces.Add(new SurfaceResult
                        {
                            Surface        = surfaceKey,
                            SurfaceLabel   = label,
                            ElementCount   = elements0.Count,
                            Elements       = elements0,
                            Errors         = [],
                            ScreenshotPath = screenshotPath0,
                        });
                        continue;
                    }

                    // Find nav item by AutomationId (x:Name in XAML) using the fresh window ref
                    var navItem = WaitForElement(mainWindow, cf, navId, label, ElementFindTimeout);
                    if (navItem == null)
                    {
                        var err = $"Nav item not found: '{label}' (id={navId})";
                        Console.WriteLine($"[explorer] WARN: {err}");
                        captureErrors.Add(err);
                        surfaces.Add(EmptySurface(surfaceKey, label, err));
                        continue;
                    }

                    // Navigate using proven strategy:
                    //   Visible items  → Click() directly (proven 10/13 in pass 5)
                    //   Offscreen items → ScrollIntoView → re-resolve → Click()
                    //                    → SelectionItem/LegacyIA fallback only if still unclickable
                    string? navErr = NavigateToItem(navItem, label, mainWindow, app, automation, cf);
                    if (navErr != null)
                    {
                        Console.WriteLine($"[explorer] WARN: {navErr}");
                        captureErrors.Add(navErr);
                        surfaces.Add(EmptySurface(surfaceKey, label, navErr));
                        continue;
                    }
                    Thread.Sleep((int)NavigationSettle.TotalMilliseconds);

                    // Re-resolve window after navigation settle to get fresh UIA state
                    try
                    {
                        var postNavWindows = app.GetAllTopLevelWindows(automation);
                        var postNavWindow  = postNavWindows.FirstOrDefault(w =>
                        {
                            try { return !string.IsNullOrEmpty(w.Title); }
                            catch { return false; }
                        });
                        if (postNavWindow != null)
                            mainWindow = postNavWindow;
                    }
                    catch { /* keep current ref */ }

                    // Traverse full window tree using fresh window reference
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

            // Enforce: ALL 13 surfaces must have at least 1 element, and zero capture errors.
            var missingSurfaces = surfaces.Where(s => s.ElementCount == 0).Select(s => s.SurfaceLabel).ToList();
            bool allSurfacesNonzero = missingSurfaces.Count == 0;
            bool zeroCaptureErrors  = captureErrors.Count == 0;

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
                    LaunchMode = "unpackaged WinUI3 (WindowsPackageType=None, WindowsAppSDKSelfContained=true)",
                },
                ExplorationMethod = "FlaUI 4.0.0 / UIA3 (UIAutomationClient COM)",
                Window = new WindowMetadata
                {
                    ProcessId    = app.ProcessId,
                    ProcessName  = processName,
                    WindowTitle  = windowTitle,
                    AutomationId = autoId,
                    BoundingBox  = SafeGetRect(mainWindow),
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

            if (!allSurfacesNonzero)
            {
                Console.Error.WriteLine($"[explorer] FAIL: {missingSurfaces.Count} surface(s) have zero elements: {string.Join(", ", missingSurfaces)}");
                return 1;
            }

            if (!zeroCaptureErrors)
            {
                Console.Error.WriteLine($"[explorer] FAIL: {captureErrors.Count} capture error(s):");
                foreach (var e in captureErrors)
                    Console.Error.WriteLine($"[explorer]   - {e}");
                return 1;
            }

            Console.WriteLine("[explorer] SUCCESS — all 13 surfaces nonzero, 0 capture errors");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[explorer] FATAL: {ex}");
            if (app != null)
                WriteLaunchDiagnostics(app, appExePath, ex.Message);
            WriteFailJson(outputJsonPath, ex.Message, app?.ProcessId ?? -1, appExePath);
            return 1;
        }
        finally
        {
            try { app?.Close(); } catch { /* best-effort */ }
            automation?.Dispose();
        }
    }

    // ─── OS error dialog detection ─────────────────────────────────────────

    private static bool IsErrorDialog(string title) =>
        ErrorDialogTitles.Any(s => title.Contains(s, StringComparison.OrdinalIgnoreCase));

    // ─── Launch diagnostics ────────────────────────────────────────────────

    /// <summary>
    /// Emits process exit code, stderr, and a best-effort note about the WinAppSDK
    /// bootstrap DLL when the app fails to start.
    /// </summary>
    private static void WriteLaunchDiagnostics(Application app, string appExePath, string reason)
    {
        Console.Error.WriteLine($"[explorer] --- LAUNCH DIAGNOSTICS ---");
        Console.Error.WriteLine($"[explorer] Reason: {reason}");
        Console.Error.WriteLine($"[explorer] PID: {app.ProcessId}");

        // Check whether bootstrap DLL is present in the app directory
        var appDir      = Path.GetDirectoryName(appExePath) ?? "";
        var bootstrapDll = Path.Combine(appDir, "Microsoft.WindowsAppRuntime.Bootstrap.dll");
        if (File.Exists(bootstrapDll))
            Console.Error.WriteLine($"[explorer] Bootstrap DLL: PRESENT ({bootstrapDll})");
        else
            Console.Error.WriteLine($"[explorer] Bootstrap DLL: MISSING — " +
                "build did not use -p:WindowsAppSDKSelfContained=true");

        // List key WinAppSDK DLLs
        var sdkDlls = new[] { "WinRT.Runtime.dll", "Microsoft.UI.Xaml.dll",
                               "Microsoft.Windows.ApplicationModel.DynamicDependency.dll" };
        foreach (var dll in sdkDlls)
        {
            var path = Path.Combine(appDir, dll);
            Console.Error.WriteLine($"[explorer] {dll}: {(File.Exists(path) ? "PRESENT" : "MISSING")}");
        }

        // Process exit status
        try
        {
            var p = Process.GetProcessById(app.ProcessId);
            if (p.HasExited)
                Console.Error.WriteLine($"[explorer] Process exit code: {p.ExitCode}");
            else
                Console.Error.WriteLine("[explorer] Process still running (OS error dialog may be blocking)");
        }
        catch
        {
            Console.Error.WriteLine("[explorer] Process already exited (could not query exit code)");
        }

        Console.Error.WriteLine($"[explorer] --- END DIAGNOSTICS ---");
    }

    // ─── Failure JSON ──────────────────────────────────────────────────────

    private static void WriteFailJson(string outputJsonPath, string reason, int pid, string appExePath)
    {
        try
        {
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
                    Name       = "Colima Desktop",
                    ExePath    = appExePath,
                    LaunchMode = "FAILED",
                },
                ExplorationMethod = "FlaUI 4.0.0 / UIA3 (UIAutomationClient COM)",
                Window = new WindowMetadata
                {
                    ProcessId    = pid,
                    ProcessName  = "",
                    WindowTitle  = "",
                    AutomationId = "",
                    BoundingBox  = null,
                },
                SurfacesExplored  = 0,
                TotalElements     = 0,
                CaptureErrors     = [$"Launch failed: {reason}"],
                Surfaces          = [],
            };

            var json = JsonSerializer.Serialize(capture, new JsonSerializerOptions { WriteIndented = true });
            var dir  = Path.GetDirectoryName(outputJsonPath);
            if (dir != null) Directory.CreateDirectory(dir);
            File.WriteAllText(outputJsonPath, json);
            Console.WriteLine($"[explorer] Failure JSON written: {outputJsonPath}");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[explorer] Could not write failure JSON: {ex.Message}");
        }
    }

    // ─── Navigation helpers ────────────────────────────────────────────────

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

    /// <summary>
    /// Navigate to a WinUI 3 NavigationViewItem.
    ///
    /// Proven strategy (restored from pass 5 / run 29642368125 which achieved 10/13):
    ///
    ///   VISIBLE item (IsOffscreen=false AND nonzero rect):
    ///     1. Click() — direct mouse click; proven reliable for all on-screen items.
    ///
    ///   OFFSCREEN item (IsOffscreen=true OR zero bounding rect):
    ///     1. ScrollItemPattern.ScrollIntoView() — bring into the NavigationView pane.
    ///     2. Re-resolve mainWindow + nav item from live UIA tree (stale handles after scroll).
    ///     3. Click() — now that the item is on-screen, click it.
    ///     4. If still NoClickablePointException → SelectionItemPattern.Select() fallback.
    ///     5. LegacyIAccessiblePattern.DoDefaultAction() fallback.
    ///
    /// NOTE: SelectionItemPattern.Select() is NOT tried first for visible items because
    /// WinUI 3 NavigationView does not raise the SelectionChanged event via UIA's
    /// SelectionItemPattern — it requires an actual click or pointer input to trigger
    /// frame navigation.  Using Select() first was the root cause of the pass-5b
    /// regression (run 29642873532: 1/13 captured).
    ///
    /// Returns null on success, or an error string on failure.
    /// </summary>
    private static string? NavigateToItem(
        AutomationElement navItem,
        string label,
        Window mainWindow,
        Application app,
        UIA3Automation automation,
        FlaUI.Core.Conditions.ConditionFactory cf)
    {
        // Capture the automation ID string eagerly before any scroll/layout change
        // makes the COM object stale (reading properties on stale refs throws).
        var navAutomationId = SafeGet(() => navItem.AutomationId ?? "", "");

        bool isOffscreen = SafeGet(() => navItem.IsOffscreen, false);
        var  rect        = SafeGetRect(navItem);
        bool zeroRect    = rect == null || (rect.Width == 0 && rect.Height == 0);

        if (!isOffscreen && !zeroRect)
        {
            // ── VISIBLE ITEM: Click directly ──────────────────────────────
            try
            {
                navItem.Click();
                Console.WriteLine($"[explorer]   Click() succeeded for '{label}'");
                return null;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[explorer]   Click() failed for visible '{label}': {ex.GetType().Name}: {ex.Message}");
                // Fall through to offscreen handling in case rect was stale
            }
        }

        // ── OFFSCREEN ITEM (or click failed): ScrollIntoView → re-resolve → Click ──
        Console.WriteLine($"[explorer]   '{label}' offscreen or click failed (offscreen={isOffscreen}, rect={rect?.Width}×{rect?.Height}) — ScrollIntoView");

        try
        {
            var scrollItem = navItem.Patterns.ScrollItem;
            if (scrollItem.IsSupported)
            {
                scrollItem.Pattern.ScrollIntoView();
                Thread.Sleep(600); // wait for NavigationView pane scroll animation
                Console.WriteLine($"[explorer]   ScrollIntoView succeeded for '{label}'");
            }
            else
            {
                Console.WriteLine($"[explorer]   ScrollItemPattern not supported for '{label}'");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[explorer]   ScrollIntoView failed for '{label}': {ex.Message}");
            // Not fatal — item may still be clickable after partial scroll
        }

        // Re-resolve window and nav item to get fresh UIA handles after layout change
        Window? freshWindow = null;
        try
        {
            var freshWindows = app.GetAllTopLevelWindows(automation);
            freshWindow = freshWindows.FirstOrDefault(w =>
            {
                try { return !string.IsNullOrEmpty(w.Title); }
                catch { return false; }
            });
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[explorer]   Re-resolve window failed for '{label}': {ex.Message}");
        }

        // Re-resolve nav item from fresh window handle using the captured automation ID
        AutomationElement? freshNavItem = null;
        if (freshWindow != null)
        {
            try
            {
                if (!string.IsNullOrEmpty(navAutomationId))
                    freshNavItem = freshWindow.FindFirstDescendant(cf.ByAutomationId(navAutomationId));
                freshNavItem ??= freshWindow.FindFirstDescendant(cf.ByName(label));
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[explorer]   Re-resolve nav item failed for '{label}': {ex.Message}");
            }
        }

        var itemToClick = freshNavItem ?? navItem;

        // Attempt Click on the (possibly freshly resolved) item
        try
        {
            itemToClick.Click();
            Console.WriteLine($"[explorer]   Click() after ScrollIntoView succeeded for '{label}'");
            return null;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[explorer]   Click() after ScrollIntoView failed for '{label}': {ex.GetType().Name}: {ex.Message}");
        }

        // ── FALLBACK 1: SelectionItemPattern.Select() ─────────────────────
        try
        {
            var selectionItem = itemToClick.Patterns.SelectionItem;
            if (selectionItem.IsSupported)
            {
                selectionItem.Pattern.Select();
                Console.WriteLine($"[explorer]   SelectionItemPattern.Select() fallback succeeded for '{label}'");
                return null;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[explorer]   SelectionItemPattern.Select() fallback failed for '{label}': {ex.Message}");
        }

        // ── FALLBACK 2: LegacyIAccessiblePattern.DoDefaultAction() ────────
        try
        {
            var legacyIa = itemToClick.Patterns.LegacyIAccessible;
            if (legacyIa.IsSupported)
            {
                legacyIa.Pattern.DoDefaultAction();
                Console.WriteLine($"[explorer]   LegacyIAccessiblePattern.DoDefaultAction() fallback succeeded for '{label}'");
                return null;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[explorer]   LegacyIAccessiblePattern.DoDefaultAction() fallback failed for '{label}': {ex.Message}");
        }

        return $"All navigation strategies failed for '{label}'";
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
