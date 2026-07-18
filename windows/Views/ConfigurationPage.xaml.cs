using ColimaDesktop.Windows.ViewModels;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace ColimaDesktop.Windows.Views;

public sealed partial class ConfigurationPage : Page
{
    public ConfigurationViewModel ViewModel { get; } = new();

    public ConfigurationPage()
    {
        InitializeComponent();
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        await ViewModel.LoadAsync();
        // Sync ComboBox selections after load (SelectedValue x:Bind TwoWay not supported in WinUI 3)
        SyncCombosFromViewModel();
    }

    private void SyncCombosFromViewModel()
    {
        SetComboByTag(RuntimeCombo, ViewModel.Runtime);
        SetComboByTag(VmTypeCombo, ViewModel.VmType);
        SetComboByTag(ArchCombo, ViewModel.Arch);
        SetComboByTag(MountTypeCombo, ViewModel.MountType);
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

    private void RuntimeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (RuntimeCombo.SelectedItem is ComboBoxItem item)
            ViewModel.Runtime = item.Tag?.ToString() ?? string.Empty;
    }

    private void VmTypeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (VmTypeCombo.SelectedItem is ComboBoxItem item)
            ViewModel.VmType = item.Tag?.ToString() ?? string.Empty;
    }

    private void ArchCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ArchCombo.SelectedItem is ComboBoxItem item)
            ViewModel.Arch = item.Tag?.ToString() ?? string.Empty;
    }

    private void MountTypeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (MountTypeCombo.SelectedItem is ComboBoxItem item)
            ViewModel.MountType = item.Tag?.ToString() ?? string.Empty;
    }
}
