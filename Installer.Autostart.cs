// Read this file first when changing GUI autostart behavior.
// Purpose: manage the HKCU Run entry and repair portable EXE path drift.
// Scope: Start Menu shortcuts, BASH_ENV, and runtime file installation stay in Installer.cs.

using System;
using System.IO;
using System.Text.RegularExpressions;
using Microsoft.Win32;

static partial class Installer
{
    const string AK = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    const string AN = "AIAgentSecure";
    const string OldAN = "ShellSecure";

    static string CurrentExePath
    {
        get
        {
            string exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
            try { return Path.GetFullPath(exe); }
            catch { return exe; }
        }
    }

    internal static string BuildAutostartCommand(string exePath)
    {
        return "\"" + (exePath ?? "") + "\"";
    }

    internal static string ExtractAutostartExePath(string command)
    {
        if (string.IsNullOrWhiteSpace(command)) return "";
        string value = Environment.ExpandEnvironmentVariables(command.Trim());
        if (value.Length == 0) return "";

        if (value[0] == '"')
        {
            int end = value.IndexOf('"', 1);
            return end > 1 ? value.Substring(1, end - 1) : value.Trim('"');
        }

        int exeEnd = value.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
        if (exeEnd >= 0) return value.Substring(0, exeEnd + 4).Trim();

        int argStart = value.IndexOfAny(new[] { ' ', '\t' });
        return argStart >= 0 ? value.Substring(0, argStart).Trim() : value;
    }

    static string NormalizeAutostartExePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return "";
        string normalized = Environment.ExpandEnvironmentVariables(path.Trim().Trim('"')).Replace('/', '\\');
        try { normalized = Path.GetFullPath(normalized); } catch { }
        return normalized.Replace('/', '\\').TrimEnd('\\');
    }

    internal static bool AutostartCommandTargetsExe(string command, string exePath)
    {
        string registeredExe = NormalizeAutostartExePath(ExtractAutostartExePath(command));
        string currentExe = NormalizeAutostartExePath(exePath);
        return registeredExe.Length > 0
            && currentExe.Length > 0
            && string.Equals(registeredExe, currentExe, StringComparison.OrdinalIgnoreCase);
    }

    internal static bool TryBuildRepairedAutostartCommand(string existingCommand, string exePath, out string repairedCommand)
    {
        repairedCommand = existingCommand;
        if (string.IsNullOrWhiteSpace(existingCommand) || string.IsNullOrWhiteSpace(exePath)) return false;
        if (AutostartCommandTargetsExe(existingCommand, exePath)) return false;
        repairedCommand = BuildAutostartCommand(exePath);
        return true;
    }

    public static void RepairAutostartPathIfNeeded()
    {
        try
        {
            using (var k = Registry.CurrentUser.OpenSubKey(AK, true))
            {
                if (k == null) return;
                string valueName = k.GetValue(AN) != null ? AN : (k.GetValue(OldAN) != null ? OldAN : null);
                if (valueName == null) return;
                string existing = Convert.ToString(k.GetValue(valueName));
                string repaired;
                // AI Agent Secure is portable; a moved EXE must keep an enabled
                // Run entry pointing at the currently running binary.
                if (TryBuildRepairedAutostartCommand(existing, CurrentExePath, out repaired))
                    k.SetValue(AN, repaired);
                else if (valueName == OldAN)
                    k.SetValue(AN, existing);
                if (valueName == OldAN && k.GetValue(OldAN) != null)
                    k.DeleteValue(OldAN);
            }
        }
        catch { }
    }

    public static bool IsAutostartEnabled()
    {
        try
        {
            using (var k = Registry.CurrentUser.OpenSubKey(AK, false))
            {
                if (k == null) return false;
                if (k.GetValue(AN) != null)
                    return AutostartCommandTargetsExe(Convert.ToString(k.GetValue(AN)), CurrentExePath);
                if (k.GetValue(OldAN) != null)
                    return AutostartCommandTargetsExe(Convert.ToString(k.GetValue(OldAN)), CurrentExePath);
                return false;
            }
        }
        catch { return false; }
    }

    public static void SetAutostart(bool on)
    {
        try
        {
            if (on)
            {
                using (var k = Registry.CurrentUser.CreateSubKey(AK))
                {
                    if (k != null)
                    {
                        k.SetValue(AN, BuildAutostartCommand(CurrentExePath));
                        if (k.GetValue(OldAN) != null) k.DeleteValue(OldAN);
                    }
                }
                return;
            }

            using (var k = Registry.CurrentUser.OpenSubKey(AK, true))
            {
                if (k != null && k.GetValue(AN) != null) k.DeleteValue(AN);
                if (k != null && k.GetValue(OldAN) != null) k.DeleteValue(OldAN);
            }
        }
        catch { }
    }
}
