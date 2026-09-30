using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Media;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using IDump.Models;
using IDump.Services;
using Wpf.Ui.Controls;

namespace IDump.ViewModels;

public enum PhoneStatus { Searching, Connecting, Locked, Loading, Ready, Failed }

public sealed partial class CategoryRow(Category category, string title, SymbolRegular symbol, Brush brush) : ObservableObject
{
    public Category Category { get; } = category;
    public string Title { get; } = title;
    public SymbolRegular Symbol { get; } = symbol;
    public Brush Brush { get; } = brush;

    [ObservableProperty] private string _countText = "";
    [ObservableProperty] private string _sizeText = "";
}

public sealed record BreakdownRow(string Title, Brush Brush, string Text);

public sealed partial class MainViewModel : ObservableObject
{
    private readonly PhoneService _phone = new();
    private List<MediaItem> _allItems = [];
    private bool _transferRunning;

    public MainViewModel()
    {
        ThumbnailLoader.Instance = new ThumbnailLoader(_phone);
        _tileSize = Settings.Load().TileSize;
        Categories =
        [
            new(Category.All, "All Items", SymbolRegular.Grid24, Application.Current.TryFindResource("AccentFillColorDefaultBrush") as Brush ?? Palette.Photo),
            new(Category.Photos, "Photos", SymbolRegular.Image24, Palette.Photo),
            new(Category.Screenshots, "Screenshots", SymbolRegular.Screenshot24, Palette.Screenshot),
            new(Category.Videos, "Videos", SymbolRegular.Video24, Palette.Video),
        ];
        _selectedCategory = Categories[0];
        _sizeFilter = SizeFilter.All[0];
        _sort = SortOption.All[0];
    }

    public PhoneService Phone => _phone;
    public List<CategoryRow> Categories { get; }
    public SizeFilter[] SizeFilters => SizeFilter.All;
    public SortOption[] SortOptions => SortOption.All;

    // MARK: Status

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsReady), nameof(ShowPlaceholder), nameof(PlaceholderTitle), nameof(PlaceholderMessage),
        nameof(PlaceholderSymbol), nameof(ShowSpinner), nameof(DeviceStatusText), nameof(DeviceStatusBrush), nameof(Subtitle))]
    private PhoneStatus _status = PhoneStatus.Searching;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(PlaceholderMessage), nameof(DeviceStatusText))]
    private int _loadedCount;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(DeviceTitle))]
    private string? _deviceName;

    [ObservableProperty] private string? _errorMessage;

    public bool IsReady => Status == PhoneStatus.Ready;
    public bool ShowPlaceholder => !IsReady || VisibleItems.Count == 0;
    public bool ShowSpinner => Status is PhoneStatus.Connecting or PhoneStatus.Loading;
    public string DeviceTitle => DeviceName ?? "No iPhone";

    public string PlaceholderTitle => Status switch
    {
        PhoneStatus.Searching => "Connect your iPhone",
        PhoneStatus.Connecting => $"Connecting to {DeviceName ?? "iPhone"}…",
        PhoneStatus.Locked => "Unlock your iPhone",
        PhoneStatus.Loading => "Reading your library…",
        PhoneStatus.Failed => "Couldn't connect",
        _ => "Nothing here",
    };

    public string PlaceholderMessage => Status switch
    {
        PhoneStatus.Searching => "Plug your iPhone into this PC with a cable, unlock it, and tap Trust if it asks.",
        PhoneStatus.Connecting => "Hang tight.",
        PhoneStatus.Locked => "Unlock your iPhone and tap Trust (or Allow) so Windows can see your photos.",
        PhoneStatus.Loading => $"{LoadedCount:N0} files found so far",
        PhoneStatus.Failed => $"{ErrorMessage}\nTry unplugging and reconnecting your iPhone.",
        _ => !string.IsNullOrEmpty(SearchText) ? $"No results for \"{SearchText}\"."
            : SizeFilter.MinimumBytes > 0 ? $"Nothing {SizeFilter.Title.ToLowerInvariant()} here."
            : $"No {SelectedCategory.Title.ToLowerInvariant()} on this iPhone.",
    };

    public SymbolRegular PlaceholderSymbol => Status switch
    {
        PhoneStatus.Searching => SymbolRegular.PlugConnected24,
        PhoneStatus.Locked => SymbolRegular.LockClosed24,
        PhoneStatus.Failed => SymbolRegular.ErrorCircle24,
        PhoneStatus.Ready => SymbolRegular.Search24,
        _ => SymbolRegular.Phone24,
    };

    public string DeviceStatusText => Status switch
    {
        PhoneStatus.Searching => "Not connected",
        PhoneStatus.Connecting => "Connecting…",
        PhoneStatus.Locked => "Locked. Unlock to continue",
        PhoneStatus.Loading => $"Reading library… {LoadedCount:N0}",
        PhoneStatus.Ready => "Connected via USB",
        _ => "Connection problem",
    };

    public Brush DeviceStatusBrush => Status switch
    {
        PhoneStatus.Ready => Brushes.LimeGreen,
        PhoneStatus.Searching or PhoneStatus.Failed => Brushes.Gray,
        _ => Brushes.Orange,
    };

    // MARK: Totals for the device card

    [ObservableProperty] private string _photoBytesText = "";
    [ObservableProperty] private string _screenshotBytesText = "";
    [ObservableProperty] private string _videoBytesText = "";
    [ObservableProperty] private string _totalBytesText = "";
    [ObservableProperty] private GridLength _photoShare = new(0, GridUnitType.Star);
    [ObservableProperty] private GridLength _screenshotShare = new(0, GridUnitType.Star);
    [ObservableProperty] private GridLength _videoShare = new(0, GridUnitType.Star);
    [ObservableProperty] private bool _hasTotals;

    // MARK: Filters

    [ObservableProperty] private CategoryRow _selectedCategory;
    [ObservableProperty] private SizeFilter _sizeFilter;
    [ObservableProperty] private SortOption _sort;
    [ObservableProperty] private string _searchText = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ItemSize))]
    private double _tileSize;

    public Size ItemSize => new(TileSize + 12, TileSize + 12);

    partial void OnSelectedCategoryChanged(CategoryRow value) => ApplyFilters();
    partial void OnSizeFilterChanged(SizeFilter value) => ApplyFilters();
    partial void OnSortChanged(SortOption value) => ApplyFilters();
    partial void OnSearchTextChanged(string value) => ApplyFilters();

    partial void OnTileSizeChanged(double value)
    {
        var settings = Settings.Load();
        settings.TileSize = value;
        settings.Save();
    }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ShowPlaceholder), nameof(Subtitle))]
    private List<MediaItem> _visibleItems = [];

    public string Title => SelectedCategory.Title;

    public string Subtitle => IsReady
        ? $"{Format.Count(VisibleItems.Count, "item")} · {Format.Bytes(VisibleItems.Sum(i => i.Size))}"
        : DeviceName ?? "";

    private void ApplyFilters()
    {
        var query = SearchText.Trim();
        var filtered = _allItems.Where(i =>
            SelectedCategory.Category.Includes(i.Kind)
            && i.Size >= SizeFilter.MinimumBytes
            && (query.Length == 0 || i.Name.Contains(query, StringComparison.OrdinalIgnoreCase)));
        VisibleItems = Sort.Apply(filtered).ToList();
        OnPropertyChanged(nameof(Title));
        OnPropertyChanged(nameof(PlaceholderMessage));
    }

    // MARK: Selection & inspector

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasSelection), nameof(SelectionText), nameof(SelectionBytesText), nameof(SingleItem),
        nameof(IsSingle), nameof(IsMulti), nameof(IsNone), nameof(MultiBreakdown))]
    private IReadOnlyList<MediaItem> _selectedItems = [];

    public bool HasSelection => SelectedItems.Count > 0;
    public string SelectionText => $"{Format.Count(SelectedItems.Count, "item")} selected";
    public string SelectionBytesText => Format.Bytes(SelectedItems.Sum(i => i.Size));
    public MediaItem? SingleItem => SelectedItems.Count == 1 ? SelectedItems[0] : null;
    public bool IsSingle => SelectedItems.Count == 1;
    public bool IsMulti => SelectedItems.Count > 1;
    public bool IsNone => SelectedItems.Count == 0;

    public List<BreakdownRow> MultiBreakdown =>
        SelectedItems.GroupBy(i => i.Kind).OrderBy(g => g.Key)
            .Select(g => new BreakdownRow(g.Key switch { MediaKind.Screenshot => "Screenshots", MediaKind.Video => "Videos", _ => "Photos" },
                          Palette.For(g.Key),
                          $"{g.Count():N0} · {Format.Bytes(g.Sum(i => i.Size))}"))
            .ToList();

    [ObservableProperty] private ImageSource? _previewImage;
    [ObservableProperty] private bool _previewLoading;
    [ObservableProperty] private string? _previewNote;
    private CancellationTokenSource? _previewCts;

    partial void OnSelectedItemsChanged(IReadOnlyList<MediaItem> value)
    {
        _previewCts?.Cancel();
        PreviewImage = null;
        PreviewNote = null;
        if (value.Count != 1) return;

        var item = value[0];
        PreviewImage = item.Thumbnail;
        if (item.IsVideo) return;

        // Pull the full photo for a sharp preview, after a short pause so arrowing
        // through the grid doesn't download every file.
        var cts = _previewCts = new CancellationTokenSource();
        _ = LoadFullPreviewAsync(item, cts.Token);
    }

    private async Task LoadFullPreviewAsync(MediaItem item, CancellationToken token)
    {
        try
        {
            await Task.Delay(350, token);
            PreviewLoading = true;
            var path = await PreviewCopyAsync(item.Main);
            token.ThrowIfCancellationRequested();
            var image = await Task.Run(() => ImageDecoding.DecodeFile(path, 1400), token);
            token.ThrowIfCancellationRequested();
            if (image != null) PreviewImage = image;
            else if (Path.GetExtension(item.Name).Equals(".heic", StringComparison.OrdinalIgnoreCase))
                PreviewNote = "Install \"HEIF Image Extensions\" from the Microsoft Store for full-size HEIC previews.";
        }
        catch (OperationCanceledException) { }
        catch { /* keep showing the thumbnail */ }
        finally
        {
            if (!token.IsCancellationRequested) PreviewLoading = false;
        }
    }

    private static readonly string PreviewFolder = Path.Combine(Path.GetTempPath(), "iDump Previews");

    private async Task<string> PreviewCopyAsync(DeviceFile file)
    {
        Directory.CreateDirectory(PreviewFolder);
        var path = Path.Combine(PreviewFolder, $"{Math.Abs(file.Path.GetHashCode())}-{file.Name}");
        if (File.Exists(path) && new FileInfo(path).Length == file.Size) return path;
        await _phone.DownloadAsync(file.Path, path);
        return path;
    }

    [RelayCommand]
    private async Task OpenOriginalAsync()
    {
        if (SingleItem is not { } item) return;
        try
        {
            PreviewLoading = true;
            var path = await PreviewCopyAsync(item.Main);
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            PreviewNote = ex.Message;
        }
        finally
        {
            PreviewLoading = false;
        }
    }

    public static void ClearPreviews()
    {
        try { Directory.Delete(PreviewFolder, true); } catch { }
    }

    // MARK: Device lifecycle

    /// <summary>Polls for the phone every couple of seconds and keeps the UI in sync.</summary>
    public async Task MonitorAsync()
    {
        while (true)
        {
            if (!_transferRunning)
            {
                try
                {
                    await TickAsync();
                }
                catch (Exception ex)
                {
                    ErrorMessage = ex.Message;
                    Status = PhoneStatus.Failed;
                    await ResetAsync(keepStatus: true);
                }
            }
            await Task.Delay(2000);
        }
    }

    private async Task TickAsync()
    {
        if (!_phone.IsConnected)
        {
            if (Status != PhoneStatus.Failed) Status = PhoneStatus.Searching;
            if (!await _phone.TryConnectAsync()) return;
            DeviceName = _phone.DeviceName;
            Status = PhoneStatus.Connecting;
        }
        else if (!await _phone.IsStillPresentAsync())
        {
            await ResetAsync();
            return;
        }

        if (Status is PhoneStatus.Connecting or PhoneStatus.Locked or PhoneStatus.Failed)
            await LoadAsync();
    }

    private async Task LoadAsync()
    {
        // A locked phone exposes no storage; stay on "Unlock" instead of flickering to "Loading".
        if (Status != PhoneStatus.Locked) Status = PhoneStatus.Loading;
        LoadedCount = 0;
        var files = await _phone.ListFilesAsync(new Progress<int>(count =>
        {
            LoadedCount = count;
            Status = PhoneStatus.Loading;
        }));
        if (files == null)
        {
            Status = PhoneStatus.Locked;
            return;
        }
        SetItems(MediaItem.Build(files));
        Status = PhoneStatus.Ready;
        ApplyFilters();
    }

    private async Task ResetAsync(bool keepStatus = false)
    {
        ThumbnailLoader.Instance?.Clear();
        await _phone.DisconnectAsync();
        DeviceName = null;
        SetItems([]);
        ApplyFilters();
        if (!keepStatus) Status = PhoneStatus.Searching;
    }

    private void SetItems(List<MediaItem> items)
    {
        _allItems = items;
        foreach (var row in Categories)
        {
            var subset = items.Where(i => row.Category.Includes(i.Kind)).ToList();
            row.CountText = Format.Count(subset.Count, "item");
            row.SizeText = Format.Bytes(subset.Sum(i => i.Size));
        }

        long Bytes(MediaKind kind) => items.Where(i => i.Kind == kind).Sum(i => i.Size);
        var photos = Bytes(MediaKind.Photo);
        var screenshots = Bytes(MediaKind.Screenshot);
        var videos = Bytes(MediaKind.Video);
        PhotoBytesText = Format.Bytes(photos);
        ScreenshotBytesText = Format.Bytes(screenshots);
        VideoBytesText = Format.Bytes(videos);
        TotalBytesText = Format.Bytes(photos + screenshots + videos);
        PhotoShare = new GridLength(photos, GridUnitType.Star);
        ScreenshotShare = new GridLength(screenshots, GridUnitType.Star);
        VideoShare = new GridLength(videos, GridUnitType.Star);
        HasTotals = items.Count > 0;
    }

    /// <summary>Called by the transfer window. Pauses polling while it runs, then refreshes.</summary>
    public async Task RunTransferAsync(TransferViewModel transfer)
    {
        _transferRunning = true;
        try
        {
            await transfer.RunAsync();
            // Re-read the phone so deleted items disappear from the grid.
            if (transfer.IsMove && _phone.IsConnected) await LoadAsync();
        }
        finally
        {
            _transferRunning = false;
        }
    }
}
