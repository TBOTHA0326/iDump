using System.IO;
using IDump.Models;
using MediaDevices;

namespace IDump.Services;

/// <summary>
/// Talks to the iPhone over USB through Windows Portable Devices (the same
/// channel File Explorer's "Apple iPhone" entry uses). Every device call runs
/// on the thread pool, one at a time, because WPD doesn't like concurrent use.
/// </summary>
public sealed class PhoneService : IDisposable
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private MediaDevice? _device;

    public string? DeviceName { get; private set; }
    public bool IsConnected => _device != null;

    private async Task<T> RunAsync<T>(Func<MediaDevice?, T> work, CancellationToken token = default)
    {
        await _gate.WaitAsync(token);
        try
        {
            return await Task.Run(() => work(_device), token);
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>Connects to the first Apple device found. Returns false if none is plugged in.</summary>
    public Task<bool> TryConnectAsync() => RunAsync(_ =>
    {
        var devices = (MediaDeviceManager.Instance.GetDevices() ?? []).ToList();
        var phone = devices.FirstOrDefault(IsApple);
        if (phone == null) return false;

        phone.Connect();
        _device = phone;
        DeviceName = string.IsNullOrWhiteSpace(phone.FriendlyName) ? phone.Description : phone.FriendlyName;
        if (string.IsNullOrWhiteSpace(DeviceName)) DeviceName = "iPhone";
        return true;
    });

    /// <summary>True while the connected phone is still plugged in.</summary>
    public Task<bool> IsStillPresentAsync() => RunAsync(device =>
    {
        if (device == null) return false;
        try
        {
            return (MediaDeviceManager.Instance.GetDevices() ?? []).Any(d => d.DeviceId == device.DeviceId);
        }
        catch
        {
            return false;
        }
    });

    public Task DisconnectAsync() => RunAsync(device =>
    {
        try { device?.Disconnect(); } catch { /* already gone */ }
        try { device?.Dispose(); } catch { /* already gone */ }
        _device = null;
        DeviceName = null;
        return true;
    });

    private static bool IsApple(MediaDevice device)
    {
        static bool Has(string? value, string text) =>
            value?.Contains(text, StringComparison.OrdinalIgnoreCase) == true;

        return Has(device.Manufacturer, "Apple") || Has(device.Description, "iPhone")
            || Has(device.FriendlyName, "iPhone") || Has(device.Description, "iPad");
    }

    /// <summary>
    /// Lists every file in the phone's photo folders. Older iOS puts them under
    /// Internal Storage\DCIM\100APPLE; newer iOS lists month folders like
    /// Internal Storage\202510_a directly. Returns null when the phone is locked
    /// or hasn't trusted this PC yet (it then exposes no folders).
    /// </summary>
    public Task<List<DeviceFile>?> ListFilesAsync(IProgress<int> progress) => RunAsync(device =>
    {
        if (device == null) return null;

        var root = device.GetRootDirectory();
        var folders = new List<MediaDirectoryInfo>();
        foreach (var storage in root.EnumerateDirectories())
        {
            var children = storage.EnumerateDirectories().ToList();
            var dcim = children.FirstOrDefault(d => d.Name.Equals("DCIM", StringComparison.OrdinalIgnoreCase));
            folders.AddRange(dcim != null ? dcim.EnumerateDirectories() : children);
        }
        if (folders.Count == 0) return null;

        var files = new List<DeviceFile>();
        foreach (var folder in folders)
        {
            foreach (var file in folder.EnumerateFiles())
            {
                var date = file.DateAuthored ?? file.CreationTime ?? file.LastWriteTime;
                files.Add(new DeviceFile(file.FullName, file.Name, folder.Name, (long)file.Length, date));
                if (files.Count % 100 == 0) progress.Report(files.Count);
            }
        }
        progress.Report(files.Count);
        return files;
    });

    public Task<byte[]?> GetThumbnailAsync(string path, CancellationToken token = default) => RunAsync(device =>
    {
        if (device == null) return null;
        try
        {
            using var stream = new MemoryStream();
            device.DownloadThumbnail(path, stream);
            return stream.Length > 0 ? stream.ToArray() : null;
        }
        catch
        {
            return null;
        }
    }, token);

    /// <summary>Copies a file off the phone to <paramref name="target"/>, reporting bytes written.</summary>
    public Task DownloadAsync(string path, string target, IProgress<long>? progress = null) => RunAsync(device =>
    {
        if (device == null) throw new IOException("The iPhone was disconnected.");
        using var output = new ProgressStream(File.Create(target), progress);
        device.DownloadFile(path, output);
        return true;
    });

    public Task DeleteAsync(string path) => RunAsync(device =>
    {
        if (device == null) throw new IOException("The iPhone was disconnected.");
        device.DeleteFile(path);
        return true;
    });

    public void Dispose()
    {
        try { _device?.Disconnect(); } catch { }
        try { _device?.Dispose(); } catch { }
    }

    /// <summary>A write-only stream wrapper that reports how many bytes have been written.</summary>
    private sealed class ProgressStream(Stream inner, IProgress<long>? progress) : Stream
    {
        private long _written;
        private long _lastReported;

        public override void Write(byte[] buffer, int offset, int count)
        {
            inner.Write(buffer, offset, count);
            _written += count;
            if (_written - _lastReported >= 512 * 1024)
            {
                _lastReported = _written;
                progress?.Report(_written);
            }
        }

        public override void Flush() => inner.Flush();
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                progress?.Report(_written);
                inner.Dispose();
            }
            base.Dispose(disposing);
        }

        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => _written;
        public override long Position { get => _written; set => throw new NotSupportedException(); }
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
    }
}
