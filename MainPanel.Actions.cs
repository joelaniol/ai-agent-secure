// Read this file first when changing button actions or config persistence from the GUI.
// Purpose: mutate protection settings and coordinate install/update/uninstall actions.
// Scope: page layout lives in MainPanel.* page files; installer internals live in Installer.cs.

using System;
using System.Linq;
using System.Windows;
using WinForms = System.Windows.Forms;

partial class MainPanel
{
    void DoToggle()
    {
        if (!_cfg.IsInstalled) return;
        _cfg.Enabled = !_cfg.Enabled;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoToggleAutostart()
    {
        Installer.SetAutostart(!Installer.IsAutostartEnabled());
        RefreshSettings();
    }

    void DoToggleDelete()
    {
        if (!EnsureInstalledForEditing(Loc.T("action.toggle_delete"))) return;
        _cfg.DeleteProtect = !_cfg.DeleteProtect;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoToggleGit()
    {
        if (!EnsureInstalledForEditing(Loc.T("action.toggle_git"))) return;
        _cfg.GitProtect = !_cfg.GitProtect;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoToggleGitFlood()
    {
        if (!EnsureInstalledForEditing(Loc.T("action.toggle_git_flood"))) return;
        _cfg.GitFloodProtect = !_cfg.GitFloodProtect;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoToggleGitLeak()
    {
        if (!EnsureInstalledForEditing(Loc.T("action.toggle_git_leak"))) return;
        _cfg.GitLeakProtect = !_cfg.GitLeakProtect;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoCommitGitLeakTimeout(int value)
    {
        if (!EnsureInstalledForEditing(Loc.T("action.change_leak_timeout"))) return;
        if (value == _cfg.GitLeakTimeout) return;
        _cfg.GitLeakTimeout = value;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoCommitGitFloodThreshold(int value)
    {
        if (!EnsureInstalledForEditing(Loc.T("action.change_flood_threshold"))) return;
        if (value == _cfg.GitFloodThreshold) return;
        _cfg.GitFloodThreshold = value;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoCommitGitFloodWindow(int value)
    {
        if (!EnsureInstalledForEditing(Loc.T("action.change_flood_window"))) return;
        if (value == _cfg.GitFloodWindow) return;
        _cfg.GitFloodWindow = value;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoTogglePsEncoding()
    {
        if (!EnsureInstalledForEditing(Loc.T("action.toggle_ps_utf8"))) return;
        _cfg.PsEncodingProtect = !_cfg.PsEncodingProtect;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoToggleHttpApi()
    {
        if (!EnsureInstalledForEditing(Loc.T("action.toggle_http_api"))) return;
        _cfg.HttpApiProtect = !_cfg.HttpApiProtect;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoSetLanguage(string lang)
    {
        if (!EnsureInstalledForEditing(Loc.T("action.change_language"))) return;
        string normalized = string.Equals(lang, "de", StringComparison.OrdinalIgnoreCase) ? "de" : "en";
        if (string.Equals(_cfg.Language, normalized, StringComparison.OrdinalIgnoreCase)) return;
        _cfg.Language = normalized;
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoAddDir()
    {
        if (!EnsureInstalledForEditing(Loc.T("action.add_folder"))) return;
        var dlg = new WinForms.FolderBrowserDialog();
        dlg.Description = Loc.T("dialog.folder_picker");
        if (dlg.ShowDialog() == WinForms.DialogResult.OK)
        {
            string p = dlg.SelectedPath.Replace("\\", "/");
            if (!_cfg.ProtectedDirs.Any(d => NormalizePathKey(d) == NormalizePathKey(p)))
            {
                _cfg.ProtectedDirs.Add(p);
                if (!SaveConfig()) return;
            }
            RefreshAll();
        }
    }

    void DoRemoveDir(string dir)
    {
        if (MessageBox.Show(Loc.F("dialog.remove_dir.message", dir),
            Loc.T("dialog.remove_dir.title"), MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        _cfg.ProtectedDirs.Remove(dir);
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoAddWhitelist()
    {
        if (!EnsureInstalledForEditing(Loc.T("dialog.add_exception.title"))) return;
        var dlg = new InputDialog(Loc.T("dialog.add_exception.title"), Loc.T("dialog.add_exception.prompt"));
        dlg.Owner = this;
        if (dlg.ShowDialog() == true && dlg.Result.Trim().Length > 0)
        {
            string n = dlg.Result.Trim();
            if (!_cfg.SafeTargets.Any(t => NormalizeNameKey(t) == NormalizeNameKey(n)))
            {
                _cfg.SafeTargets.Add(n);
                if (!SaveConfig()) return;
            }
            RefreshAll();
        }
    }

    void DoRemoveWhitelist(string n)
    {
        if (!EnsureInstalledForEditing(Loc.T("action.remove_exception"))) return;
        _cfg.SafeTargets.Remove(n);
        if (!SaveConfig()) return;
        RefreshAll();
    }

    void DoClearLog()
    {
        if (!EnsureInstalledForEditing(Loc.T("action.clear_log"))) return;
        if (MessageBox.Show(Loc.T("dialog.clear_log.message"), Loc.T("dialog.clear_log.title"), MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        _cfg.ClearLog(); _lastLog = 0; _lastLogSize = 0; RefreshLog(); RefreshStats();
    }

    void DoInstall()
    {
        if (Installer.FindGitBash() == null)
        {
            MessageBox.Show(Loc.T("dialog.git_bash_missing.message"),
                Loc.T("dialog.git_bash_missing.title"), MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        ShowResult(Loc.T("common.install"), Installer.DoInstall()); RefreshAll();
    }

    void DoUpdate() { ShowResult(Loc.T("common.update"), Installer.DoUpdate()); RefreshAll(); }

    void DoUninstall()
    {
        if (MessageBox.Show(Loc.T("dialog.uninstall.message"), Loc.T("dialog.uninstall.title"),
            MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        ShowResult(Loc.T("dialog.uninstall.title"), Installer.DoUninstall()); RefreshAll();
    }

    void ShowResult(string t, string m) { new ResultDialog(t, m) { Owner = this }.ShowDialog(); }

    void DoAbout()
    {
        ShowPage(4);
    }

    void RefreshAll()
    {
        string oldLang = Loc.Lang;
        ReloadConfig(true);
        if (_lastUiLang != null && !string.Equals(oldLang, Loc.Lang, StringComparison.OrdinalIgnoreCase))
        {
            _titleBarCache = null;
            Content = BuildShell();
            RefreshTrayMenu();
            _lastUiLang = Loc.Lang;
        }
        RefreshStats();
        RefreshSidebarActions();
        UpdateTrayIcon();
        ShowPage(_activePage);
    }

    ProtectionState GetProtectionState()
    {
        if (!_cfg.IsInstalled) return ProtectionState.NotInstalled;
        if (!_cfg.Enabled) return ProtectionState.Disabled;
        if (Installer.HasFullRuntime()) return ProtectionState.FullyProtected;
        if (Installer.HasInteractiveRuntime()) return ProtectionState.InteractiveOnly;
        return ProtectionState.NeedsRepair;
    }

    bool ReloadConfig(bool showError)
    {
        bool ok = _cfg.Load();
        // Loc must follow the persisted language on every reload so the
        // GUI re-localises immediately after a "Save" without restart.
        Loc.Init(_cfg.Language);
        _lastLog = _cfg.GetLogCount();
        _lastLogSize = _cfg.GetLogSize();
        if (!ok && showError && !string.IsNullOrWhiteSpace(_cfg.LastError))
            MessageBox.Show(_cfg.LastError, AppInfo.ProductName, MessageBoxButton.OK, MessageBoxImage.Warning);
        return ok;
    }

    bool SaveConfig()
    {
        if (_cfg.Save()) return true;
        MessageBox.Show(_cfg.LastError ?? Loc.T("dialog.save_failed"),
            AppInfo.ProductName, MessageBoxButton.OK, MessageBoxImage.Warning);
        return false;
    }

    bool EnsureInstalledForEditing(string action)
    {
        if (_cfg.IsInstalled) return true;
        MessageBox.Show(Loc.F("dialog.install_required.message", action),
            Loc.T("dialog.install_required.title"), MessageBoxButton.OK, MessageBoxImage.Information);
        return false;
    }

    static string NormalizePathKey(string path)
    {
        return (path ?? "").Trim().Replace("\\", "/").TrimEnd('/').ToLowerInvariant();
    }

    static string NormalizeNameKey(string name)
    {
        return (name ?? "").Trim().ToLowerInvariant();
    }
}
