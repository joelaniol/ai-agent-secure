// Read this file first when changing GUI log watching or blocked-operation toasts.
// Purpose: watch blocked.log, keep toast delivery independent from protocol refresh, and classify toast titles.
// Scope: protocol page rendering lives in MainPanel.Log.cs; log file parsing lives in ShellSecureConfig.cs.

using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Threading;

partial class MainPanel
{
    void SetupWatcher()
    {
        _lastLogSize = _cfg.GetLogSize();
        _lastToastLogSize = _lastLogSize;
        _lastToastLogPath = _cfg.LogPath ?? "";
        _lastLog = _cfg.GetLogCount();

        TryStartFsWatcher();

        // Fallback poll catches cases where FSW does not fire
        // (log rotation, directory created only after installation, etc.).
        _watcher = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _watcher.Tick += delegate { TryStartFsWatcher(); CheckLog(); };
        _watcher.Start();
    }

    void TryStartFsWatcher()
    {
        string wantedPath = _cfg.LogPath ?? "";
        if (_fsWatcher != null
            && !string.Equals(_watchedLogPath, wantedPath, StringComparison.OrdinalIgnoreCase))
        {
            DisposeFsWatcher();
        }
        if (_fsWatcher != null) return;
        try
        {
            string logDir = Path.GetDirectoryName(wantedPath);
            string logFile = Path.GetFileName(wantedPath);
            if (string.IsNullOrWhiteSpace(logDir) || string.IsNullOrWhiteSpace(logFile)) return;
            if (!Directory.Exists(logDir)) return;
            _fsWatcher = new FileSystemWatcher(logDir, logFile);
            _fsWatcher.NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size
                                      | NotifyFilters.CreationTime | NotifyFilters.FileName;
            FileSystemEventHandler onChange = delegate { Dispatcher.BeginInvoke((Action)CheckLog); };
            _fsWatcher.Changed += onChange;
            _fsWatcher.Created += onChange;
            _fsWatcher.Renamed += delegate { Dispatcher.BeginInvoke((Action)CheckLog); };
            _fsWatcher.EnableRaisingEvents = true;
            _watchedLogPath = wantedPath;
        }
        catch
        {
            DisposeFsWatcher();
        }
    }

    void DisposeFsWatcher()
    {
        if (_fsWatcher != null)
        {
            try { _fsWatcher.EnableRaisingEvents = false; _fsWatcher.Dispose(); } catch { }
            _fsWatcher = null;
        }
        _watchedLogPath = "";
    }

    void CheckLog()
    {
        long size;
        try { size = _cfg.GetLogSize(); } catch { return; }
        string logPath = _cfg.LogPath ?? "";
        if (!string.Equals(_lastToastLogPath, logPath, StringComparison.OrdinalIgnoreCase))
        {
            _lastToastLogPath = logPath;
            _lastToastLogSize = size;
            _lastLogSize = size;
            _lastLog = _cfg.GetLogCount();
            TryStartFsWatcher();
            RefreshLog();
            RefreshStats();
            return;
        }

        if (size == _lastToastLogSize) return;
        long startOffset = _lastToastLogSize;
        bool rescanCurrentFile = false;
        if (size < _lastToastLogSize)
        {
            startOffset = 0;
            rescanCurrentFile = true;
        }

        long readEnd;
        var newEntries = _cfg.GetLogEntriesAdded(startOffset, out readEnd);
        // Advance to what the read actually consumed, not the size sampled
        // before it, so entries appended mid-read are not re-toasted next tick.
        _lastToastLogSize = readEnd;
        _lastLogSize = readEnd;

        if (newEntries.Count > 0)
        {
            _lastLog = rescanCurrentFile ? _cfg.GetLogCount() : _lastLog + newEntries.Count;
            var blockedEntriesNewestFirst = new List<string>();
            for (int i = newEntries.Count - 1; i >= 0; i--)
            {
                if (IsBlockedLogEntry(newEntries[i]))
                    blockedEntriesNewestFirst.Add(newEntries[i]);
            }
            if (blockedEntriesNewestFirst.Count > 0)
                ShowBlockedToast(blockedEntriesNewestFirst);
            RefreshLog();
            RefreshStats();
        }
        else if (rescanCurrentFile)
        {
            _lastLog = _cfg.GetLogCount();
            RefreshLog();
            RefreshStats();
        }
    }

    static bool IsBlockedLogEntry(string line)
    {
        return line != null
            && (line.IndexOf("BLOCKED |", StringComparison.OrdinalIgnoreCase) >= 0
                || line.IndexOf("BLOCKIERT |", StringComparison.OrdinalIgnoreCase) >= 0);
    }

    void ShowBlockedToast(List<string> recentBlockedEntries)
    {
        int count = recentBlockedEntries == null ? 0 : recentBlockedEntries.Count;
        if (count <= 0) return;

        if (_toast == null)
        {
            _toast = new ToastWindow();
            _toast.Clicked += delegate
            {
                Show();
                if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
                Activate();
                ShowPage(3);
            };
        }

        var recent = new List<string>();
        for (int i = 0; i < recentBlockedEntries.Count && i < 5; i++)
            recent.Add(recentBlockedEntries[i]);
        bool hasGit = false, hasDelete = false, hasGitFlood = false, hasGitLeak = false, hasGitCorruption = false, hasWriteCorruption = false, hasHttpApi = false, hasPsUtf8 = false, hasEmptyFile = false;
        string firstCmd = "", firstReason = "";
        foreach (var line in recent)
        {
            int bi = line.IndexOf("BLOCKED |");
            if (bi < 0) continue;
            string rest = line.Substring(bi + "BLOCKED |".Length).Trim();
            // Split into at most 4 fields (cmd | target | reason | ...). Pipes
            // inside values do not leak into the reason field.
            var parts = rest.Split(new[] { '|' }, 4);
            if (parts.Length == 0) continue;
            string cmd = parts[0].Trim();
            string field2 = parts.Length >= 2 ? parts[1].Trim() : "";
            string reason = parts.Length >= 4
                ? parts[3].Trim()
                : parts[parts.Length - 1].Trim();

            if (string.Equals(field2, "git-flood", StringComparison.OrdinalIgnoreCase))
                hasGitFlood = true;
            else if (string.Equals(field2, "git-leak", StringComparison.OrdinalIgnoreCase))
                hasGitLeak = true;
            else if (string.Equals(field2, "git-corruption", StringComparison.OrdinalIgnoreCase))
                hasGitCorruption = true;
            else if (string.Equals(field2, "write-corruption", StringComparison.OrdinalIgnoreCase))
                hasWriteCorruption = true;
            else if (string.Equals(field2, "http-api", StringComparison.OrdinalIgnoreCase))
                hasHttpApi = true;
            else if (string.Equals(field2, "ps-encoding", StringComparison.OrdinalIgnoreCase))
                hasPsUtf8 = true;
            else if (field2.StartsWith("empty-file", StringComparison.OrdinalIgnoreCase))
                hasEmptyFile = true;
            else if (cmd.StartsWith("git ", StringComparison.OrdinalIgnoreCase)
                || cmd.Equals("git", StringComparison.OrdinalIgnoreCase)
                || cmd.StartsWith("Git", StringComparison.OrdinalIgnoreCase))
                hasGit = true;
            else
                hasDelete = true;

            if (firstCmd.Length == 0)
            {
                firstCmd = cmd;
                firstReason = reason;
            }
        }

        int distinctLayers = (hasGit ? 1 : 0) + (hasDelete ? 1 : 0)
            + (hasGitFlood ? 1 : 0) + (hasGitLeak ? 1 : 0) + (hasGitCorruption ? 1 : 0)
            + (hasWriteCorruption ? 1 : 0) + (hasHttpApi ? 1 : 0) + (hasPsUtf8 ? 1 : 0)
            + (hasEmptyFile ? 1 : 0);
        string title;
        if (distinctLayers > 1) title = Loc.T("toast.multi");
        else if (hasGitFlood) title = Loc.T("toast.git_flood");
        else if (hasGitLeak) title = Loc.T("toast.git_leak");
        else if (hasGitCorruption) title = Loc.T("toast.git_corruption");
        else if (hasEmptyFile) title = Loc.T("toast.empty_file");
        else if (hasWriteCorruption) title = Loc.T("toast.write_corruption");
        else if (hasHttpApi) title = Loc.T("toast.http_api");
        else if (hasPsUtf8) title = Loc.T("toast.ps_utf8");
        else if (hasGit) title = Loc.T("toast.git");
        else title = Loc.T("toast.delete");
        if (count > 1) title += " (" + count + ")";

        string msg;
        if (count == 1 && firstCmd.Length > 0)
        {
            string cmdShort = firstCmd.Length > 70 ? firstCmd.Substring(0, 67) + "..." : firstCmd;
            msg = cmdShort;
            if (firstReason.Length > 0) msg += "\n" + firstReason;
            msg += "\n\n" + Loc.T("toast.details");
        }
        else
        {
            msg = (count == 1 ? Loc.T("toast.one_prevented") : Loc.F("toast.many_prevented", count))
                  + "\n" + Loc.T("toast.details");
        }

        _toast.ShowToast(title, msg, 10000);
    }
}
