using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class AIWorkloadsPage : Page
{
    public AIWorkloadsViewModel ViewModel { get; } = new();

    public AIWorkloadsPage()
    {
        InitializeComponent();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        // Sync Runner ComboBox (SelectedValue x:Bind TwoWay not supported in WinUI 3)
        SetComboByTag(RunnerCombo, ViewModel.Runner);
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

    private void RunnerCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (RunnerCombo.SelectedItem is ComboBoxItem item)
            ViewModel.Runner = item.Tag?.ToString() ?? "docker";
    }
}
