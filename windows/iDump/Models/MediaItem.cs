using System.IO;
using System.Windows.Media;
using CommunityToolkit.Mvvm.ComponentModel;
using IDump.Services;
using Wpf.Ui.Controls;

namespace IDump.Models;

public enum MediaKind { Photo, Screenshot, Video }

/// <summary>A single file as it exists on the phone.</summary>
public sealed record DeviceFile(string Path, string Name, string Folder, long Size, DateTime? Date);

/// <summary>
/// One thing shown in the grid. A Live Photo is a single item made of the
/// still image plus its short companion movie.
/// </summary>
public sealed partial class MediaItem : ObservableObject
{
    public MediaItem(DeviceFile main, IReadOnlyList<DeviceFile> companions, MediaKind kind)
    {
        Main = main;
        Files = [main, .. companions];
        Kind = kind;
        Size = Files.Sum(f => f.Size);
    }

    public DeviceFile Main { get; }
    public IReadOnlyList<DeviceFile> Files { get; }
    public MediaKind Kind { get; }
    public long Size { get; }

    public string Name => Main.Name;
    public string Folder => Main.Folder;
    public DateTime? Date => Main.Date;
    public bool IsLivePhoto => Files.Count > 1;
    public bool IsVideo => Kind == MediaKind.Video;
    public bool IsLarge => Size >= 100_000_000;
    public string SizeText => Format.Bytes(Size);
    public string DateText => Date?.ToString("d MMM yyyy, HH:mm") ?? "Unknown";
    public string KindText => IsLivePhoto ? "Live Photo" : Kind switch
    {
        MediaKind.Screenshot => "Screenshot",
        MediaKind.Video => "Video",
        _ => "Photo",
    };
    public SymbolRegular KindSymbol => Kind switch
    {
        MediaKind.Screenshot => SymbolRegular.Screenshot24,
        MediaKind.Video => SymbolRegular.Video24,
        _ => SymbolRegular.Image24,
    };
    public Brush KindBrush => Palette.For(Kind);
    public string Tooltip => $"{Name} · {SizeText}";

    private ImageSource? _thumbnail;
    private bool _thumbnailRequested;

    /// <summary>Loaded lazily the first time the grid shows this item.</summary>
    public ImageSource? Thumbnail
    {
        get
        {
            if (!_thumbnailRequested)
            {
                _thumbnailRequested = true;
                ThumbnailLoader.Instance?.Request(this);
            }
            return _thumbnail;
        }
        set => SetProperty(ref _thumbnail, value);
    }

    // MARK: Building items from the device file list

    private static readonly HashSet<string> VideoExtensions = [".mov", ".mp4", ".m4v", ".3gp"];
    private static readonly HashSet<string> ImageExtensions = [".heic", ".heif", ".jpg", ".jpeg", ".png", ".gif", ".dng", ".tif", ".tiff", ".webp", ".bmp"];

    public static List<MediaItem> Build(IEnumerable<DeviceFile> files)
    {
        var stills = new List<DeviceFile>();
        var movies = new List<DeviceFile>();
        foreach (var file in files)
        {
            var ext = System.IO.Path.GetExtension(file.Name).ToLowerInvariant();
            if (VideoExtensions.Contains(ext)) movies.Add(file);
            else if (ImageExtensions.Contains(ext)) stills.Add(file);
        }

        // A Live Photo movie shares its folder and base filename with the still.
        var stillByKey = new Dictionary<string, DeviceFile>();
        foreach (var still in stills) stillByKey[Key(still)] = still;

        var companions = new Dictionary<DeviceFile, List<DeviceFile>>();
        var standalone = new List<DeviceFile>();
        foreach (var movie in movies)
        {
            if (stillByKey.TryGetValue(Key(movie), out var owner))
            {
                if (!companions.TryGetValue(owner, out var list)) companions[owner] = list = [];
                list.Add(movie);
            }
            else
            {
                standalone.Add(movie);
            }
        }

        var items = new List<MediaItem>(stills.Count + standalone.Count);
        foreach (var still in stills)
        {
            var kind = IsScreenshot(still) ? MediaKind.Screenshot : MediaKind.Photo;
            items.Add(new MediaItem(still, companions.GetValueOrDefault(still) ?? [], kind));
        }
        foreach (var movie in standalone)
            items.Add(new MediaItem(movie, [], MediaKind.Video));
        return items;
    }

    private static string Key(DeviceFile file) =>
        $"{file.Folder}/{System.IO.Path.GetFileNameWithoutExtension(file.Name)}".ToUpperInvariant();

    // iPhone screenshots are PNGs; the camera never writes PNGs.
    private static bool IsScreenshot(DeviceFile file) =>
        System.IO.Path.GetExtension(file.Name).Equals(".png", StringComparison.OrdinalIgnoreCase);
}

// MARK: - Filtering & sorting

public enum Category { All, Photos, Screenshots, Videos }

public static class CategoryExtensions
{
    public static bool Includes(this Category category, MediaKind kind) => category switch
    {
        Category.Photos => kind == MediaKind.Photo,
        Category.Screenshots => kind == MediaKind.Screenshot,
        Category.Videos => kind == MediaKind.Video,
        _ => true,
    };
}

public sealed record SizeFilter(string Title, long MinimumBytes)
{
    public static readonly SizeFilter[] All =
    [
        new("Any size", 0),
        new("Larger than 1 MB", 1_000_000),
        new("Larger than 10 MB", 10_000_000),
        new("Larger than 50 MB", 50_000_000),
        new("Larger than 100 MB", 100_000_000),
        new("Larger than 500 MB", 500_000_000),
        new("Larger than 1 GB", 1_000_000_000),
    ];

    public override string ToString() => Title;
}

public sealed record SortOption(string Title, Func<IEnumerable<MediaItem>, IEnumerable<MediaItem>> Apply)
{
    public static readonly SortOption[] All =
    [
        new("Largest first", items => items.OrderByDescending(i => i.Size)),
        new("Smallest first", items => items.OrderBy(i => i.Size)),
        new("Newest first", items => items.OrderByDescending(i => i.Date ?? DateTime.MinValue)),
        new("Oldest first", items => items.OrderBy(i => i.Date ?? DateTime.MinValue)),
        new("Name", items => items.OrderBy(i => i.Name, StringComparer.OrdinalIgnoreCase)),
    ];

    public override string ToString() => Title;
}

// MARK: - Formatting & colours

public static class Format
{
    public static string Bytes(long bytes)
    {
        string[] units = ["bytes", "KB", "MB", "GB", "TB"];
        double value = bytes;
        var unit = 0;
        while (value >= 1000 && unit < units.Length - 1) { value /= 1000; unit++; }
        if (unit == 0) return $"{bytes:N0} {units[0]}";
        return value >= 100 || unit == 1 ? $"{value:N0} {units[unit]}" : $"{value:N1} {units[unit]}";
    }

    public static string Count(int count, string noun) => $"{count:N0} {noun}{(count == 1 ? "" : "s")}";
}

public static class Palette
{
    public static readonly Brush Photo = Frozen(Color.FromRgb(0x0A, 0x84, 0xFF));
    public static readonly Brush Screenshot = Frozen(Color.FromRgb(0xBF, 0x5A, 0xF2));
    public static readonly Brush Video = Frozen(Color.FromRgb(0xFF, 0x9F, 0x0A));

    public static Brush For(MediaKind kind) => kind switch
    {
        MediaKind.Screenshot => Screenshot,
        MediaKind.Video => Video,
        _ => Photo,
    };

    private static Brush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
