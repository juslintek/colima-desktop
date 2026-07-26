using System;
using System.Threading.Tasks;
using ColimaDesktop.Windows.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace ColimaDesktop.Windows.Views;

internal static class DestructiveConfirmationDialog
{
    /// <summary>
    /// Presents the accessible confirmation for a <see cref="DestructiveAction"/>. This is the entry
    /// point wired into <c>ViewModelBase.DestructiveConfirmationHandler</c> so the confirmation is
    /// driven from the view-model's destructive command (fail-closed at the RPC boundary).
    /// </summary>
    public static Task<bool> ShowAsync(XamlRoot xamlRoot, DestructiveAction action)
    {
        ArgumentNullException.ThrowIfNull(action);
        return ShowAsync(xamlRoot, action.ActionId, action.Title, action.Message, action.ConfirmLabel);
    }

    public static async Task<bool> ShowAsync(
        XamlRoot xamlRoot,
        string actionId,
        string title,
        string message,
        string confirmLabel)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Title = title,
            Content = message,
            PrimaryButtonText = confirmLabel,
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close
        };
        AutomationProperties.SetAutomationId(dialog, $"Confirm{actionId}Dialog");
        AutomationProperties.SetName(dialog, $"Confirm {title}");

        var result = await dialog.ShowAsync();
        var choice = result == ContentDialogResult.Primary
            ? ConfirmationChoice.Confirm
            : ConfirmationChoice.Cancel;
        return DestructiveConfirmation.ShouldExecute(choice);
    }
}
