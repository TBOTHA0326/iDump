using System.IO;
using System.Text.Json;

namespace IDump.Services;

/// <summary>Tiny JSON settings file in %AppData%\iDump.</summary>
public sealed class Settings
{
    public string? DestinationPath { get; set; }
    public double TileSize { get; set; } = 150;

    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "iDump", "settings.json");

    public static Settings Load()
    {
        try
        {
            return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings();
        }
        catch
        {
            return new Settings();
        }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this));
        }
        catch
        {
            // Not being able to remember a folder isn't worth crashing over.
        }
    }
}
