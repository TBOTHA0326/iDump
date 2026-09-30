using System.Globalization;
using System.Windows;
using System.Windows.Data;
using IDump.ViewModels;

namespace IDump;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        MainViewModel.ClearPreviews();
        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        MainViewModel.ClearPreviews();
        base.OnExit(e);
    }
}

public sealed class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
        value is true ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}

public sealed class NullToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture) =>
        value == null || value is string { Length: 0 } ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
