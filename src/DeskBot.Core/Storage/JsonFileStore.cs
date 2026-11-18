using System.Text.Json;
using System.Text.Json.Serialization;

namespace DeskBot.Core.Storage;

/// <summary>Atomic JSON хадгалалт. Эвдэрсэн файлыг .corrupt болгож нөөцлөөд default руу буцна.</summary>
public static class JsonFileStore
{
    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
        PropertyNameCaseInsensitive = true,
    };

    public static T LoadOrDefault<T>(string path, Func<T> fallback)
    {
        try
        {
            if (!File.Exists(path)) return fallback();
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<T>(json, Options) ?? fallback();
        }
        catch (Exception ex) when (ex is JsonException or NotSupportedException)
        {
            try { File.Copy(path, $"{path}.corrupt-{DateTime.Now:yyyyMMddHHmmss}", overwrite: true); } catch { /* best effort */ }
            return fallback();
        }
    }

    public static void SaveAtomic<T>(string path, T value)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(value, Options));
        File.Move(tmp, path, overwrite: true);
    }
}
