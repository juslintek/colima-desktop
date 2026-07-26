using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class RuntimePage : Page
{
    public RuntimeViewModel ViewModel { get; } = new();

    public RuntimePage()
    {
        InitializeComponent();
        ViewModel.DestructiveConfirmationHandler = action =>
            DestructiveConfirmationDialog.ShowAsync(XamlRoot, action);
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        // Sync TargetRuntime ComboBox (SelectedValue x:Bind TwoWay not supported in WinUI 3)
        SetComboByTag(TargetRuntimeCombo, ViewModel.TargetRuntime);
    }

    private static void SetComboByTag(ComboBox combo, string value)
    {
        foreach (var item in combo.Items)
        {
            if (item is ComboBoxItem cbi && cbi.Tag?.ToString() == value)
            {
                combo.SelectedItem = cbi;
                return;
            }
        }
        if (combo.Items.Count > 0) combo.SelectedIndex = 0;
    }

    private void TargetRuntimeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (TargetRuntimeCombo.SelectedItem is ComboBoxItem item)
            ViewModel.TargetRuntime = item.Tag?.ToString() ?? "docker";
    }

    // PruneCommand presents the accessible confirmation itself (message varies by the `all` flag).
    private void Prune_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e) =>
        ViewModel.PruneCommand.Execute(false);

    private void PruneAll_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e) =>
        ViewModel.PruneCommand.Execute(true);
}
