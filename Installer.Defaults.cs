// Read this file first when changing fresh GUI install default configuration.
// Purpose: seed default protected areas for new GUI installations.
// Scope: installer orchestration, BASH_ENV handling, and runtime updates stay in Installer.cs.

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

static partial class Installer
{
    internal static bool WindowsCDriveAvailable()
    {
        try { return Directory.Exists(@"C:\"); }
        catch { return false; }
    }

    static string NormalizeConfigAreaKey(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return "";
        path = path.Trim().Replace('\\', '/');
        if (Regex.IsMatch(path, @"^[A-Za-z]:"))
            path = "/" + char.ToLowerInvariant(path[0]) + path.Substring(2);
        path = path.TrimEnd('/');
        return path.Length == 0 ? "/" : path.ToLowerInvariant();
    }

    static string EscapeDefaultConfigValue(string value)
    {
        return (value ?? "")
            .Replace("\\", "\\\\")
            .Replace("\"", "\\\"")
            .Replace("$", "\\$")
            .Replace("`", "\\`");
    }

    static string UnescapeDefaultConfigValue(string value)
    {
        if (string.IsNullOrEmpty(value)) return "";
        var result = new StringBuilder();
        bool escaped = false;
        foreach (char c in value)
        {
            if (escaped)
            {
                result.Append(c);
                escaped = false;
                continue;
            }
            if (c == '\\')
            {
                escaped = true;
                continue;
            }
            result.Append(c);
        }
        if (escaped) result.Append('\\');
        return result.ToString();
    }

    internal static string SeedFreshInstallDefaultAreas(string configText)
    {
        return SeedFreshInstallDefaultAreas(configText, WindowsCDriveAvailable() ? new[] { "C:/" } : new string[0]);
    }

    internal static string SeedFreshInstallDefaultAreas(string configText, IEnumerable<string> defaultAreas)
    {
        string text = configText ?? "";
        if (defaultAreas == null) return text;

        var match = Regex.Match(
            text,
            @"(?ms)(?<head>^SHELL_SECURE_PROTECTED_DIRS\s*=\s*\(\s*\r?\n)(?<body>.*?)(?<tail>^[ \t]*\)\s*$)");
        if (!match.Success) return text;

        var existingKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match valueMatch in Regex.Matches(match.Groups["body"].Value, "\"((?:[^\"\\\\]|\\\\.)*)\""))
        {
            string key = NormalizeConfigAreaKey(UnescapeDefaultConfigValue(valueMatch.Groups[1].Value));
            if (key.Length > 0) existingKeys.Add(key);
        }

        var additions = new List<string>();
        foreach (string area in defaultAreas)
        {
            if (string.IsNullOrWhiteSpace(area)) continue;
            string key = NormalizeConfigAreaKey(area);
            if (key.Length == 0 || existingKeys.Contains(key)) continue;
            existingKeys.Add(key);
            additions.Add("    \"" + EscapeDefaultConfigValue(area.Trim()) + "\"");
        }
        if (additions.Count == 0) return text;

        string body = match.Groups["body"].Value;
        if (body.Length > 0 && !body.EndsWith("\n", StringComparison.Ordinal) && !body.EndsWith("\r", StringComparison.Ordinal))
            body += "\n";

        string replacement = match.Groups["head"].Value + body + string.Join("\n", additions) + "\n" + match.Groups["tail"].Value;
        return text.Substring(0, match.Index) + replacement + text.Substring(match.Index + match.Length);
    }
}
