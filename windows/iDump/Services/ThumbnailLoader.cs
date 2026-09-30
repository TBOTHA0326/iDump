using System.Collections.Concurrent;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IDump.Models;

namespace IDump.Services;

/// <summary>
/// Fetches thumbnails from the phone, newest request first, so whatever is on
/// screen right now loads before things that were scrolled past.
/// </summary>
public sealed class ThumbnailLoader
{
    public static ThumbnailLoader? Instance { get; set; }

    private readonly PhoneService _phone;
    private readonly ConcurrentStack<MediaItem> _pending = new();
    private int _running;

    public ThumbnailLoader(PhoneService phone) => _phone = phone;

    public void Request(MediaItem item)
    {
        _pending.Push(item);
        if (Interlocked.CompareExchange(ref _running, 1, 0) == 0)
            _ = PumpAsync();
    }

    public void Clear() => _pending.Clear();

    private async Task PumpAsync()
    {
        try
        {
            while (_pending.TryPop(out var item))
            {
                var data = await _phone.GetThumbnailAsync(item.Main.Path);
                if (data == null) continue;
                var image = ImageDecoding.Decode(data, 320);
                if (image != null)
                    Application.Current?.Dispatcher.BeginInvoke(() => item.Thumbnail = image);
            }
        }
        finally
        {
            Interlocked.Exchange(ref _running, 0);
            if (!_pending.IsEmpty && Interlocked.CompareExchange(ref _running, 1, 0) == 0)
                _ = PumpAsync();
        }
    }
}

public static class ImageDecoding
{
    /// <summary>Decodes image bytes, applying EXIF orientation so portrait shots aren't sideways.</summary>
    public static BitmapSource? Decode(byte[] data, int maxPixel)
    {
        try
        {
            using var stream = new MemoryStream(data);
            return Decode(stream, maxPixel);
        }
        catch
        {
            return null;
        }
    }

    public static BitmapSource? DecodeFile(string path, int maxPixel)
    {
        try
        {
            using var stream = File.OpenRead(path);
            return Decode(stream, maxPixel);
        }
        catch
        {
            return null;
        }
    }

    private static BitmapSource Decode(Stream stream, int maxPixel)
    {
        var frame = BitmapFrame.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
        var orientation = ReadOrientation(frame);

        stream.Position = 0;
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.StreamSource = stream;
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        if (frame.PixelWidth >= frame.PixelHeight) bitmap.DecodePixelWidth = Math.Min(maxPixel, frame.PixelWidth);
        else bitmap.DecodePixelHeight = Math.Min(maxPixel, frame.PixelHeight);
        bitmap.EndInit();
        bitmap.Freeze();

        BitmapSource result = bitmap;
        var transform = orientation switch
        {
            3 => new RotateTransform(180),
            6 => new RotateTransform(90),
            8 => new RotateTransform(270),
            _ => null,
        };
        if (transform != null)
        {
            result = new TransformedBitmap(bitmap, transform);
            result.Freeze();
        }
        return result;
    }

    private static int ReadOrientation(BitmapFrame frame)
    {
        try
        {
            if (frame.Metadata is BitmapMetadata metadata)
            {
                foreach (var query in new[] { "/app1/ifd/{ushort=274}", "System.Photo.Orientation" })
                {
                    if (metadata.ContainsQuery(query) && metadata.GetQuery(query) is ushort value)
                        return value;
                }
            }
        }
        catch
        {
            // No readable metadata; assume upright.
        }
        return 1;
    }
}
