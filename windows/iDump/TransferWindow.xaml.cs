using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Media;
using IDump.ViewModels;
using Microsoft.Win32;
using Wpf.Ui.Controls;

namespace IDump;

public partial class TransferWindow : FluentWindow
{
    private readonly TransferViewModel _transfer;
    private readonly MainViewModel _main;

    public TransferWindow(TransferViewModel transfer, MainViewModel main)
    {
        _transfer = transfer;
        _main = main;
        DataContext = transfer;
        InitializeComponent();
    }

    private void Choose_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "Choose a folder on your hard drive for the photos and videos",
            InitialDirectory = _transfer.Destination ?? "",
        };
        if (dialog.ShowDialog(this) == true) _transfer.Destination = dialog.FolderName;
    }

    private async void Start_Click(object sender, RoutedEventArgs e)
    {
        await _main.RunTransferAsync(_transfer);
        if (!_transfer.Succeeded)
        {
            ResultIcon.Symbol = SymbolRegular.Warning24;
            ResultIcon.Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0x9F, 0x0A));
        }
    }

    private void Stop_Click(object sender, RoutedEventArgs e) => _transfer.Stop();

    private void Cancel_Click(object sender, RoutedEventArgs e) => Close();

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        if (_transfer.Destination != null)
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{_transfer.Destination}\"") { UseShellExecute = true });
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        // Don't let the window vanish mid-transfer; the user can press Stop instead.
        if (_transfer.IsRunning) e.Cancel = true;
        base.OnClosing(e);
    }
}
