using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using Xunit;

namespace ColimaDesktop.Windows.Tests;

/// <summary>
/// Property 17 (accessibility-identifier totality + uniqueness) for the Windows frontend, verified
/// structurally against the real XAML source. The WinUI XamlCompiler cannot run on the macOS host,
/// so this parses each page as XML (well-formedness), and asserts every INTERACTIVE control carries
/// a stable, non-empty AutomationProperties.AutomationId (or x:Name, which WinUI promotes to the
/// AutomationId) and that those identifiers are unique within a surface — so UIA automation can
/// target every control deterministically. Also asserts error banners are accessible assertive
/// live regions (Requirement 5.6 error surfacing).
/// Feature: cross-platform-live-verification, Property 17.
/// </summary>
[Trait("Feature", "cross-platform-live-verification")]
[Trait("Property", "17")]
public sealed class AutomationIdInventoryTests
{
    private const string Presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";
    private const string Xaml = "http://schemas.microsoft.com/winfx/2006/xaml";

    private static readonly XName AutomationId = "AutomationProperties.AutomationId";
    private static readonly XName AutomationName = "AutomationProperties.Name";
    private static readonly XName LiveSetting = "AutomationProperties.LiveSetting";
    private static readonly XName XName_ = XName.Get("Name", Xaml);

    // Controls a user can focus/invoke/edit — the ones UIA automation must target by a stable id.
    private static readonly HashSet<string> Interactive = new()
    {
        "Button", "HyperlinkButton", "ToggleButton", "RepeatButton", "DropDownButton",
        "TextBox", "PasswordBox", "NumberBox", "AutoSuggestBox", "RichEditBox",
        "ComboBox", "ToggleSwitch", "CheckBox", "RadioButton", "Slider",
        "NavigationViewItem", "MenuFlyoutItem", "AppBarButton", "ToggleMenuFlyoutItem",
    };

    private static string WindowsRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "MainWindow.xaml")) &&
                Directory.Exists(Path.Combine(dir.FullName, "Views")))
                return dir.FullName;
            dir = dir.Parent;
        }
        throw new DirectoryNotFoundException(
            "Could not locate the windows/ source root (MainWindow.xaml + Views/) above " +
            AppContext.BaseDirectory);
    }

    private static IEnumerable<string> XamlFiles()
    {
        var root = WindowsRoot();
        yield return Path.Combine(root, "MainWindow.xaml");
        foreach (var f in Directory.EnumerateFiles(Path.Combine(root, "Views"), "*.xaml").OrderBy(x => x))
            yield return f;
    }

    private static string Local(XElement e) => e.Name.LocalName;

    [Fact]
    public void EveryInteractiveControlHasAStableUniqueAutomationId()
    {
        var totalInteractive = 0;
        var filesScanned = 0;

        foreach (var path in XamlFiles())
        {
            filesScanned++;
            // XDocument.Load throws on malformed XML → this also proves each page is well-formed.
            var doc = XDocument.Load(path);
            var page = Path.GetFileName(path);

            var idsOnThisSurface = new List<string>();
            foreach (var el in doc.Descendants().Where(e => Interactive.Contains(Local(e))))
            {
                totalInteractive++;
                var id = (string?)el.Attribute(AutomationId);
                var xname = (string?)el.Attribute(XName_);

                Assert.True(
                    !string.IsNullOrWhiteSpace(id) || !string.IsNullOrWhiteSpace(xname),
                    $"{page}: <{Local(el)}> has no AutomationProperties.AutomationId or x:Name");

                if (!string.IsNullOrWhiteSpace(id))
                    idsOnThisSurface.Add(id!);
            }

            var duplicates = idsOnThisSurface
                .GroupBy(x => x).Where(g => g.Count() > 1).Select(g => g.Key).ToList();
            Assert.True(duplicates.Count == 0,
                $"{page}: duplicate AutomationProperties.AutomationId values: {string.Join(", ", duplicates)}");
        }

        Assert.True(filesScanned >= 14, $"Expected to scan all 14 Windows XAML surfaces, scanned {filesScanned}");
        // Guards against a vacuous pass (e.g. a namespace/parse change that silently matches nothing).
        Assert.True(totalInteractive >= 100,
            $"Expected 100+ interactive controls across the Windows surfaces, found {totalInteractive}");
    }

    [Fact]
    public void ErrorBannersAreAccessibleAssertiveLiveRegions()
    {
        // Requirement 5.6: backend errors surface in an accessible way. Every error InfoBar
        // (Severity="Error") must carry an accessibility name and be an assertive live region so a
        // screen reader announces the error with context when it opens.
        var errorBanners = 0;
        foreach (var path in XamlFiles())
        {
            var doc = XDocument.Load(path);
            var page = Path.GetFileName(path);
            foreach (var bar in doc.Descendants().Where(e => Local(e) == "InfoBar"))
            {
                if ((string?)bar.Attribute("Severity") != "Error")
                    continue;
                errorBanners++;
                Assert.False(string.IsNullOrWhiteSpace((string?)bar.Attribute(AutomationName)),
                    $"{page}: error InfoBar is missing AutomationProperties.Name");
                Assert.Equal("Assertive", (string?)bar.Attribute(LiveSetting));
            }
        }

        // Every content page (13; MainWindow is the shell) exposes an error banner.
        Assert.True(errorBanners >= 13, $"Expected 13+ error banners across the pages, found {errorBanners}");
    }
}
