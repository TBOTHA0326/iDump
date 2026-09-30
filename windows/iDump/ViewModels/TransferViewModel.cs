using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using IDump.Models;
using IDump.Services;

namespace IDump.ViewModels;

public enum TransferMode { Copy, Move }
public enum TransferPhase { Setup, Copying, Deleting, Finished }

public sealed record TransferFailure(string Name, string Reason);

/// <summary>
/// Copies items to a folder, checks each copy's size against the original, and
/// (in move mode) deletes from the iPhone only the items whose copies verified.
/// </summary>
public sealed partial class TransferViewModel : ObservableObject
{
    private readonly PhoneService _phone;
    private bool _stopRequested;

    public TransferViewModel(PhoneService phone, TransferMode mode, IReadOnlyList<MediaItem> items)
    {
        _phone = phone;
        Mode = mode;
        Items = items;
        TotalBytes = items.Sum(i => i.Size);
        var saved = Settings.Load().DestinationPath;
        if (!string.IsNullOrEmpty(saved) && Directory.Exists(saved)) Destination = saved;
    }

    public TransferMode Mode { get; }
    public IReadOnlyList<MediaItem> Items { get; }
    public long TotalBytes { get; }
    public bool IsMove => Mode == TransferMode.Move;

    public string Heading => $"{(IsMove ? "Move" : "Copy")} {Format.Count(Items.Count, "item")}";
    public string TotalText => Format.Bytes(TotalBytes);
    public string StartButtonText => IsMove ? "Move & delete from iPhone" : "Copy";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasDestination), nameof(SpaceText), nameof(HasEnoughSpace), nameof(CanStart), nameof(DestinationName))]
    private string? _destination;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsSetup), nameof(IsRunning), nameof(IsFinished), nameof(IsDeleting), nameof(RunningTitle))]
    private TransferPhase _phase = TransferPhase.Setup;

    [ObservableProperty] private string _currentName = "";
    [ObservableProperty] private double _percent;
    [ObservableProperty] private string _progressText = "";
    [ObservableProperty] private string _countText = "";
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(FooterText))]
    private bool _stopping;

    public string FooterText => Stopping ? "Stopping after the current file…" : "Keep your iPhone unlocked and connected.";

    // Results
    [ObservableProperty] private string _resultTitle = "";
    [ObservableProperty] private string _resultDetail = "";
    [ObservableProperty] private bool _succeeded;
    public List<TransferFailure> Failures { get; } = [];
    public bool HasFailures => Failures.Count > 0;
    public string FailuresHeader => $"{Format.Count(Failures.Count, "item")} failed and {(IsMove ? "were left on your iPhone" : "weren't copied")}";

    public bool IsSetup => Phase == TransferPhase.Setup;
    public bool IsRunning => Phase is TransferPhase.Copying or TransferPhase.Deleting;
    public bool IsDeleting => Phase == TransferPhase.Deleting;
    public bool IsFinished => Phase == TransferPhase.Finished;
    public bool HasDestination => Destination != null;
    public bool CanStart => HasDestination && HasEnoughSpace;

    public string RunningTitle => Phase == TransferPhase.Deleting
        ? "Removing from iPhone…"
        : $"{(IsMove ? "Moving" : "Copying")} to {DestinationName}…";

    public string DestinationName
    {
        get
        {
            if (Destination == null) return "No folder chosen";
            var name = Path.GetFileName(Destination.TrimEnd('\\'));
            return string.IsNullOrEmpty(name) ? Destination : name;
        }
    }

    private long? AvailableSpace
    {
        get
        {
            if (Destination == null) return null;
            try { return new DriveInfo(Path.GetPathRoot(Destination)!).AvailableFreeSpace; }
            catch { return null; }
        }
    }

    public bool HasEnoughSpace => AvailableSpace is not { } space || space > TotalBytes;

    public string SpaceText => AvailableSpace is not { } space
        ? ""
        : HasEnoughSpace
            ? $"✓  {Format.Bytes(space)} available on this drive"
            : $"✕  Not enough space: {Format.Bytes(space)} available, {Format.Bytes(TotalBytes)} needed";

    partial void OnDestinationChanged(string? value)
    {
        var settings = Settings.Load();
        settings.DestinationPath = value;
        settings.Save();
    }

    public void Stop()
    {
        _stopRequested = true;
        Stopping = true;
    }

    public async Task RunAsync()
    {
        if (Destination == null) return;
        Phase = TransferPhase.Copying;

        var verified = new List<MediaItem>();
        long processedBytes = 0;
        var processed = 0;

        foreach (var item in Items)
        {
            if (_stopRequested) break;
            CurrentName = item.Name;
            CountText = $"{processed + 1} of {Items.Count}";
            try
            {
                foreach (var file in item.Files)
                {
                    var baseBytes = processedBytes + item.Files.TakeWhile(f => f != file).Sum(f => f.Size);
                    await CopyAsync(file, item, baseBytes);
                }
                verified.Add(item);
            }
            catch (Exception ex)
            {
                Failures.Add(new TransferFailure(item.Name, ex.Message));
            }
            processedBytes += item.Size;
            processed++;
            UpdateProgress(processedBytes);
        }

        long freed = 0;
        var deleted = 0;
        string? deleteError = null;
        // Stopping means "don't touch my phone": nothing gets deleted.
        if (IsMove && !_stopRequested && verified.Count > 0)
        {
            Phase = TransferPhase.Deleting;
            foreach (var item in verified)
            {
                try
                {
                    foreach (var file in item.Files) await _phone.DeleteAsync(file.Path);
                    deleted++;
                    freed += item.Size;
                }
                catch (Exception ex)
                {
                    deleteError = ex.Message;
                    break;
                }
            }
        }

        Succeeded = Failures.Count == 0 && deleteError == null && !_stopRequested;
        ResultTitle = IsMove && deleted > 0
            ? $"Moved {Format.Count(deleted, "item")}"
            : $"Copied {Format.Count(verified.Count, "item")}";
        var details = new List<string>();
        if (freed > 0) details.Add($"Freed {Format.Bytes(freed)} on your iPhone.");
        if (_stopRequested) details.Add("Stopped. Nothing was deleted from your iPhone.");
        if (deleteError != null) details.Add($"Your iPhone refused to delete some items: {deleteError}");
        ResultDetail = string.Join("\n", details);
        OnPropertyChanged(nameof(HasFailures));
        OnPropertyChanged(nameof(FailuresHeader));
        Phase = TransferPhase.Finished;
    }

    private async Task CopyAsync(DeviceFile file, MediaItem item, long baseBytes)
    {
        var folder = Path.Combine(Destination!, item.Kind switch
        {
            MediaKind.Screenshot => "Screenshots",
            MediaKind.Video => "Videos",
            _ => "Photos",
        });
        Directory.CreateDirectory(folder);

        var target = Path.Combine(folder, file.Name);
        if (File.Exists(target))
        {
            // Already copied on an earlier run: accept it as verified.
            if (new FileInfo(target).Length == file.Size) return;
            target = UniquePath(target);
        }

        var progress = new Progress<long>(written => UpdateProgress(baseBytes + written));
        try
        {
            await _phone.DownloadAsync(file.Path, target, progress);
        }
        catch
        {
            TryDelete(target);
            throw;
        }

        var actual = new FileInfo(target).Length;
        if (actual != file.Size)
        {
            TryDelete(target);
            throw new IOException($"Copy didn't match the original ({Format.Bytes(actual)} of {Format.Bytes(file.Size)}).");
        }
        if (file.Date is { } date)
        {
            try
            {
                File.SetCreationTime(target, date);
                File.SetLastWriteTime(target, date);
            }
            catch
            {
                // Dates are nice to have, not essential.
            }
        }
    }

    private void UpdateProgress(long doneBytes)
    {
        Percent = TotalBytes > 0 ? Math.Min(100, doneBytes * 100.0 / TotalBytes) : 0;
        ProgressText = $"{Format.Bytes(doneBytes)} of {Format.Bytes(TotalBytes)}";
    }

    private static string UniquePath(string path)
    {
        var folder = Path.GetDirectoryName(path)!;
        var name = Path.GetFileNameWithoutExtension(path);
        var ext = Path.GetExtension(path);
        for (var i = 2; ; i++)
        {
            var candidate = Path.Combine(folder, $"{name} {i}{ext}");
            if (!File.Exists(candidate)) return candidate;
        }
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch { }
    }
}
