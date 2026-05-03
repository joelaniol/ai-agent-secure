// Read this file first when changing GUI-side Git Bash discovery.
// Purpose: locate Git for Windows bash.exe without accepting WSL/System32 bash.
// Scope: installer state, BASH_ENV, and config mutations stay in Installer.cs.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

static class GitBashDiscovery
{
    internal static bool IsGitBashCandidate(string path)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return false;
            string full = Path.GetFullPath(path).Replace('/', '\\');
            if (!full.EndsWith("\\bash.exe", StringComparison.OrdinalIgnoreCase)) return false;
            if (string.Equals(full, Path.Combine(Environment.SystemDirectory, "bash.exe"), StringComparison.OrdinalIgnoreCase)) return false;
            return full.EndsWith("\\Git\\bin\\bash.exe", StringComparison.OrdinalIgnoreCase)
                || full.EndsWith("\\Git\\usr\\bin\\bash.exe", StringComparison.OrdinalIgnoreCase)
                || HasGitForWindowsLayout(full);
        }
        catch { return false; }
    }

    internal static bool HasGitForWindowsLayout(string fullPath)
    {
        try
        {
            string dir = Path.GetDirectoryName(fullPath);
            if (string.IsNullOrWhiteSpace(dir)) return false;
            string[] roots = {
                Path.GetFullPath(Path.Combine(dir, "..")),
                Path.GetFullPath(Path.Combine(dir, "..", ".."))
            };
            foreach (var root in roots)
                if (File.Exists(Path.Combine(root, "cmd", "git.exe"))) return true;
        }
        catch { return false; }
        return false;
    }

    internal static string[] GetGitBashCandidates(string programFiles, string programFilesX86, string localAppData)
    {
        var candidates = new List<string>();
        foreach (var root in new[] { programFiles, programFilesX86 })
        {
            if (string.IsNullOrWhiteSpace(root)) continue;
            candidates.Add(Path.Combine(root, @"Git\bin\bash.exe"));
            candidates.Add(Path.Combine(root, @"Git\usr\bin\bash.exe"));
        }
        if (!string.IsNullOrWhiteSpace(localAppData))
        {
            candidates.Add(Path.Combine(localAppData, @"Programs\Git\bin\bash.exe"));
            candidates.Add(Path.Combine(localAppData, @"Programs\Git\usr\bin\bash.exe"));
        }
        return candidates.ToArray();
    }

    public static string FindGitBash()
    {
        string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string pf86 = Environment.GetEnvironmentVariable("ProgramFiles(x86)") ?? "";
        string la = Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? "";
        string[] candidates = GetGitBashCandidates(pf, pf86, la);
        foreach (var path in candidates)
            if (IsGitBashCandidate(path)) return path;
        try
        {
            var psi = new ProcessStartInfo("where", "bash.exe")
            { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true };
            var proc = Process.Start(psi);
            string output = proc.StandardOutput.ReadToEnd().Trim();
            proc.WaitForExit();
            foreach (var line in output.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string found = line.Trim();
                if (IsGitBashCandidate(found)) return found;
            }
        }
        catch { }
        return null;
    }
}
