using System.Windows;
using System.Windows.Input;
using IDump.Models;
using IDump.ViewModels;
using Wpf.Ui.Appearance;
using Wpf.Ui.Controls;

namespace IDump;

public partial class MainWindow : FluentWindow
{
    private readonly MainViewModel _vm;

    public MainWindow()
    {
        ApplicationThemeManager.ApplySystemTheme();
        _vm = new MainViewModel();
        DataContext = _vm;
        InitializeComponent();
        SystemThemeWatcher.Watch(this);

        Loaded += async (_, _) => await _vm.MonitorAsync();
        Closed += (_, _) => _vm.Phone.Dispose();
    }

    private void MediaGrid_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e) =>
        _vm.SelectedItems = MediaGrid.SelectedItems.Cast<MediaItem>().ToList();

    private void MediaGrid_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (_vm.OpenOriginalCommand.CanExecute(null)) _vm.OpenOriginalCommand.Execute(null);
    }

    private void SelectAll_Click(object sender, RoutedEventArgs e)
    {
        if (MediaGrid.Items.Count > 0 && MediaGrid.SelectedItems.Count == MediaGrid.Items.Count)
            MediaGrid.UnselectAll();
        else
            MediaGrid.SelectAll();
        MediaGrid.Focus();
    }

    private void Deselect_Click(object sender, RoutedEventArgs e) => MediaGrid.UnselectAll();

    private void ToggleInspector_Click(object sender, RoutedEventArgs e) =>
        Inspector.Visibility = Inspector.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;

    private void Copy_Click(object sender, RoutedEventArgs e) => OpenTransfer(TransferMode.Copy);

    private void Move_Click(object sender, RoutedEventArgs e) => OpenTransfer(TransferMode.Move);

    private void OpenTransfer(TransferMode mode)
    {
        if (_vm.SelectedItems.Count == 0) return;
        var transfer = new TransferViewModel(_vm.Phone, mode, _vm.SelectedItems.ToList());
        new TransferWindow(transfer, _vm) { Owner = this }.ShowDialog();
    }
}
