// Read this file first when changing GUI config parsing or log reads.
// Purpose: load/save ~/.shell-secure/config.conf and expose lightweight log helpers.
// Scope: installer/bootstrap work lives in Installer.cs; runtime guard logic lives in lib/protection.sh.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

class ShellSecureConfig
{
    public bool Enabled = true;
    // Kategorie-Toggles. Defaulten auf true, damit aeltere Configs ohne
    // diese Keys genau so verhalten wie vorher (voller Schutz).
    public bool DeleteProtect = true;
    public bool GitProtect = true;
    // Git-Flood-Schutz: limitiert Netzwerk-git-Calls (push/pull/fetch/clone/
    // ls-remote) auf max Threshold pro Window-Sekunden. Schuetzt vor
    // durchdrehenden Agents, die Auth-Prompts spammen.
    public bool GitFloodProtect = true;
    public int GitFloodThreshold = 4;
    public int GitFloodWindow = 60;
    // PowerShell-UTF-8-Schutz: blockt PS-Writes ohne -Encoding utf8.
    // Schuetzt vor dem haeufigen Agent-Bug, in dem "Set-Content" oder ">"
    // ohne explizite Encoding-Angabe Quellcode mit UTF-16-BOM korrumpiert.
    public bool PsEncodingProtect = true;
    // Sprache fuer Block-Messages und GUI-Texte (en/de). Default = en, alles
    // andere ausser exakt "de" wird auf "en" zurueckgesetzt.
    public string Language = "en";
    public List<string> ProtectedDirs = new List<string>();
    public List<string> SafeTargets = new List<string>();
    public string ConfigPath, InstallDir, LogPath;
    public string LogConfigValue = "$HOME/.shell-secure/blocked.log";
    public string LastError;

    static string _home;
    public static string Home
    {
        get
        {
            if (_home == null)
                _home = Environment.GetEnvironmentVariable("USERPROFILE")
                    ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return _home;
        }
    }

    public ShellSecureConfig()
    {
        InstallDir = Path.Combine(Home, ".shell-secure");
        ConfigPath = Path.Combine(InstallDir, "config.conf");
        LogPath = ExpandConfigPath(LogConfigValue);
    }

    public bool IsInstalled
    {
        get { return File.Exists(Path.Combine(InstallDir, "protection.sh")) && File.Exists(ConfigPath); }
    }

    public bool Load()
    {
        ProtectedDirs.Clear();
        SafeTargets.Clear();
        Enabled = true;
        DeleteProtect = true;
        GitProtect = true;
        GitFloodProtect = true;
        GitFloodThreshold = 4;
        GitFloodWindow = 60;
        PsEncodingProtect = true;
        Language = "en";
        LogConfigValue = "$HOME/.shell-secure/blocked.log";
        LogPath = ExpandConfigPath(LogConfigValue);
        LastError = null;
        if (!File.Exists(ConfigPath)) return true;
        try
        {
            string text = File.ReadAllText(ConfigPath, Encoding.UTF8);
            var m = Regex.Match(text, @"SHELL_SECURE_ENABLED\s*=\s*(\w+)");
            if (m.Success) Enabled = m.Groups[1].Value == "true";
            var md = Regex.Match(text, @"SHELL_SECURE_DELETE_PROTECT\s*=\s*(\w+)");
            if (md.Success) DeleteProtect = md.Groups[1].Value == "true";
            var mg = Regex.Match(text, @"SHELL_SECURE_GIT_PROTECT\s*=\s*(\w+)");
            if (mg.Success) GitProtect = mg.Groups[1].Value == "true";
            var mfp = Regex.Match(text, @"SHELL_SECURE_GIT_FLOOD_PROTECT\s*=\s*(\w+)");
            if (mfp.Success) GitFloodProtect = mfp.Groups[1].Value == "true";
            var mft = Regex.Match(text, @"SHELL_SECURE_GIT_FLOOD_THRESHOLD\s*=\s*(\d+)");
            if (mft.Success)
            {
                int v;
                if (int.TryParse(mft.Groups[1].Value, out v) && v >= 1) GitFloodThreshold = v;
            }
            var mfw = Regex.Match(text, @"SHELL_SECURE_GIT_FLOOD_WINDOW\s*=\s*(\d+)");
            if (mfw.Success)
            {
                int v;
                if (int.TryParse(mfw.Groups[1].Value, out v) && v >= 1) GitFloodWindow = v;
            }
            var mpe = Regex.Match(text, @"SHELL_SECURE_PS_ENCODING_PROTECT\s*=\s*(\w+)");
            if (mpe.Success) PsEncodingProtect = mpe.Groups[1].Value == "true";
            var mln = Regex.Match(text, @"SHELL_SECURE_LANGUAGE\s*=\s*""?([a-zA-Z-]+)""?");
            if (mln.Success)
            {
                string raw = mln.Groups[1].Value;
                Language = string.Equals(raw, "de", StringComparison.OrdinalIgnoreCase) ? "de" : "en";
            }
            var ml = Regex.Match(text, "SHELL_SECURE_LOG\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
            if (ml.Success)
            {
                LogConfigValue = UnescapeConfigValue(ml.Groups[1].Value);
                LogPath = ExpandConfigPath(LogConfigValue);
            }
            ProtectedDirs = ParseArray(text, "SHELL_SECURE_PROTECTED_DIRS");
            SafeTargets = ParseArray(text, "SHELL_SECURE_SAFE_TARGETS");
            return true;
        }
        catch (Exception ex)
        {
            LastError = Loc.F("config.load_failed", ex.Message);
            return false;
        }
    }

    static List<string> ParseArray(string text, string name)
    {
        var list = new List<string>();
        var m = Regex.Match(text, name + @"\s*=\s*\((.*?)\)", RegexOptions.Singleline);
        if (!m.Success) return list;
        foreach (Match e in Regex.Matches(m.Groups[1].Value, "\"((?:[^\"\\\\]|\\\\.)*)\""))
            list.Add(UnescapeConfigValue(e.Groups[1].Value));
        return list;
    }

    static string UnescapeConfigValue(string value)
    {
        const string marker = "\u0001";
        return value.Replace("\\\\", marker)
            .Replace("\\\"", "\"")
            .Replace("\\$", "$")
            .Replace("\\`", "`")
            .Replace(marker, "\\");
    }

    static string EscapeConfigValue(string value)
    {
        return (value ?? "")
            .Replace("\\", "\\\\")
            .Replace("\"", "\\\"")
            .Replace("$", "\\$")
            .Replace("`", "\\`");
    }

    static string ExpandConfigPath(string value)
    {
        string path = value ?? "";
        if (path == "$HOME" || path.StartsWith("$HOME/") || path.StartsWith("$HOME\\"))
            path = Home + path.Substring("$HOME".Length);
        else if (path == "${HOME}" || path.StartsWith("${HOME}/") || path.StartsWith("${HOME}\\"))
            path = Home + path.Substring("${HOME}".Length);
        else if (path == "~" || path.StartsWith("~/") || path.StartsWith("~\\"))
            path = Home + path.Substring(1);
        return path.Replace('/', Path.DirectorySeparatorChar);
    }

    public bool Save()
    {
        LastError = null;
        if (!IsInstalled)
        {
            LastError = Loc.T("config.not_installed");
            return false;
        }
        var sb = new StringBuilder();
        try
        {
            sb.AppendLine("# AI Agent Secure Configuration (Shell-Secure core)");
            sb.AppendLine("SHELL_SECURE_ENABLED=" + (Enabled ? "true" : "false"));
            sb.AppendLine("SHELL_SECURE_DELETE_PROTECT=" + (DeleteProtect ? "true" : "false"));
            sb.AppendLine("SHELL_SECURE_GIT_PROTECT=" + (GitProtect ? "true" : "false"));
            sb.AppendLine("SHELL_SECURE_GIT_FLOOD_PROTECT=" + (GitFloodProtect ? "true" : "false"));
            sb.AppendLine("SHELL_SECURE_GIT_FLOOD_THRESHOLD=" + GitFloodThreshold);
            sb.AppendLine("SHELL_SECURE_GIT_FLOOD_WINDOW=" + GitFloodWindow);
            sb.AppendLine("SHELL_SECURE_PS_ENCODING_PROTECT=" + (PsEncodingProtect ? "true" : "false"));
            sb.AppendLine("SHELL_SECURE_LANGUAGE=" + (Language == "de" ? "de" : "en"));
            sb.AppendLine();
            sb.AppendLine("SHELL_SECURE_LOG=\"" + EscapeConfigValue(LogConfigValue) + "\"");
            sb.AppendLine();
            sb.AppendLine("SHELL_SECURE_PROTECTED_DIRS=(");
            foreach (var d in ProtectedDirs) sb.AppendLine("    \"" + EscapeConfigValue(d) + "\"");
            sb.AppendLine(")");
            sb.AppendLine();
            sb.AppendLine("SHELL_SECURE_SAFE_TARGETS=(");
            foreach (var t in SafeTargets) sb.AppendLine("    \"" + EscapeConfigValue(t) + "\"");
            sb.AppendLine(")");
            File.WriteAllText(ConfigPath, sb.ToString().Replace("\r\n", "\n"), new UTF8Encoding(false));
            return true;
        }
        catch (Exception ex)
        {
            LastError = Loc.F("config.save_failed", ex.Message);
            return false;
        }
    }

    // Gibt die letzten `count` Zeilen zurueck, neueste zuerst.
    public List<string> GetLogLines(int count)
    {
        if (!File.Exists(LogPath)) return new List<string>();
        try
        {
            var tail = new Queue<string>();
            foreach (var line in File.ReadLines(LogPath, Encoding.UTF8))
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                tail.Enqueue(line);
                if (tail.Count > count) tail.Dequeue();
            }
            var result = tail.ToList();
            result.Reverse();
            return result;
        }
        catch { return new List<string>(); }
    }

    public int GetLogCount()
    {
        if (!File.Exists(LogPath)) return 0;
        try
        {
            int count = 0;
            foreach (var line in File.ReadLines(LogPath, Encoding.UTF8))
                if (!string.IsNullOrWhiteSpace(line)) count++;
            return count;
        }
        catch { return 0; }
    }

    public long GetLogSize()
    {
        try { return File.Exists(LogPath) ? new FileInfo(LogPath).Length : 0; }
        catch { return 0; }
    }

    public int CountLogLinesAdded(long startOffset)
    {
        if (!File.Exists(LogPath)) return 0;
        try
        {
            var info = new FileInfo(LogPath);
            if (startOffset < 0 || startOffset > info.Length) return GetLogCount();
            if (startOffset == info.Length) return 0;

            int count = 0;
            using (var stream = new FileStream(LogPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                stream.Seek(startOffset, SeekOrigin.Begin);
                using (var reader = new StreamReader(stream, Encoding.UTF8, true))
                {
                    string line;
                    while ((line = reader.ReadLine()) != null)
                        if (!string.IsNullOrWhiteSpace(line)) count++;
                }
            }
            return count;
        }
        catch { return 0; }
    }

    public void ClearLog()
    {
        try { if (File.Exists(LogPath)) File.WriteAllText(LogPath, ""); } catch { }
    }
}
