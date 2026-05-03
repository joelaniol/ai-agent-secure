// Read this file first when changing GUI install, update, uninstall, BASH_ENV, or autostart behavior.
// Purpose: Windows-side installer/status helpers for the GUI.
// Scope: runtime protection remains in lib/protection.sh; source embedding is verified by build-gui.ps1.

using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

// Start menu shortcut with AppUserModelID. Without this shortcut Windows 10/11
// often suppresses NotifyIcon.ShowBalloonTip notifications (Focus Assist /
// missing AUMID registration).
static class ShortcutHelper
{
    static string OldShortcutPath
    {
        get
        {
            string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
            return Path.Combine(programs, "Shell-Secure.lnk");
        }
    }

    public static string ShortcutPath
    {
        get
        {
            string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
            return Path.Combine(programs, "AI Agent Secure.lnk");
        }
    }

    public static void CreateStartMenuShortcut(string appId)
    {
        string exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
        string path = ShortcutPath;
        Directory.CreateDirectory(Path.GetDirectoryName(path));

        var link = (IShellLinkW)new CShellLink();
        link.SetPath(exe);
        link.SetWorkingDirectory(Path.GetDirectoryName(exe));
        link.SetIconLocation(exe, 0);
        link.SetDescription(AppInfo.ProductName);

        var store = (IPropertyStore)link;
        var pv = new PROPVARIANT();
        pv.vt = (ushort)VarEnum.VT_LPWSTR;
        pv.pszVal = Marshal.StringToCoTaskMemUni(appId);
        try
        {
            var key = PKEY_AppUserModel_ID;
            store.SetValue(ref key, ref pv);
            store.Commit();
        }
        finally
        {
            if (pv.pszVal != IntPtr.Zero) Marshal.FreeCoTaskMem(pv.pszVal);
        }

        ((IPersistFile)link).Save(path, true);
        try { if (!string.Equals(OldShortcutPath, path, StringComparison.OrdinalIgnoreCase) && File.Exists(OldShortcutPath)) File.Delete(OldShortcutPath); } catch { }
    }

    public static void RemoveStartMenuShortcut()
    {
        try { if (File.Exists(ShortcutPath)) File.Delete(ShortcutPath); } catch { }
        try { if (File.Exists(OldShortcutPath)) File.Delete(OldShortcutPath); } catch { }
    }

    public static bool HasStartMenuShortcut()
    {
        try { return File.Exists(ShortcutPath) || File.Exists(OldShortcutPath); } catch { return false; }
    }

    static PROPERTYKEY PKEY_AppUserModel_ID = new PROPERTYKEY
    {
        fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
        pid = 5
    };

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    class CShellLink { }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
     Guid("000214F9-0000-0000-C000-000000000046")]
    interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cch);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out ushort pwHotkey);
        void SetHotkey(ushort wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cch, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
     Guid("0000010b-0000-0000-C000-000000000046")]
    interface IPersistFile
    {
        void GetClassID(out Guid pClassID);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, [MarshalAs(UnmanagedType.Bool)] bool fRemember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
        void GetCurFile([Out, MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
    }

    [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
     Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    interface IPropertyStore
    {
        void GetCount(out uint cProps);
        void GetAt(uint iProp, out PROPERTYKEY pkey);
        void GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        void SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        void Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Explicit)]
    struct PROPVARIANT
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr pszVal;
    }
}

static partial class Installer
{
    const string MB = "# >>> shell-secure >>>", ME = "# <<< shell-secure <<<";

    static string Home { get { return ShellSecureConfig.Home; } }
    static string Dir { get { return Path.Combine(Home, ".shell-secure"); } }
    static string Rc { get { return Path.Combine(Home, ".bashrc"); } }
    static string EnvLoaderPath { get { return Path.Combine(Dir, "env-loader.sh").Replace("\\", "/"); } }
    static string PreviousBashEnvPath { get { return Path.Combine(Dir, "previous-bash-env.txt"); } }

    public static string FindGitBash() { return GitBashDiscovery.FindGitBash(); }

    public static bool HasBashRcHook()
    {
        try
        {
            if (!File.Exists(Rc)) return false;
            string bashrc = File.ReadAllText(Rc, Encoding.UTF8);
            return bashrc.Contains(MB);
        }
        catch { return false; }
    }

    public static string GetUserBashEnv()
    {
        return Environment.GetEnvironmentVariable("BASH_ENV", EnvironmentVariableTarget.User) ?? "";
    }

    static string NormalizeEnvPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return "";
        path = path.Trim().Replace('\\', '/');
        if (Regex.IsMatch(path, @"^[A-Za-z]:/"))
            path = "/" + char.ToLowerInvariant(path[0]) + path.Substring(2);
        return path.TrimEnd('/').ToLowerInvariant();
    }

    public static bool IsOwnedBashEnv()
    {
        return NormalizeEnvPath(GetUserBashEnv()) == NormalizeEnvPath(EnvLoaderPath);
    }

    public static string GetPreviousBashEnv()
    {
        try
        {
            return File.Exists(PreviousBashEnvPath) ? File.ReadAllText(PreviousBashEnvPath, Encoding.UTF8).Trim() : "";
        }
        catch { return ""; }
    }

    public static bool HasRuntimeFiles()
    {
        return File.Exists(Path.Combine(Dir, "protection.sh")) && File.Exists(Path.Combine(Dir, "env-loader.sh"));
    }

    public static bool HasFullRuntime() { return FindGitBash() != null && HasRuntimeFiles() && IsOwnedBashEnv(); }
    public static bool HasInteractiveRuntime() { return FindGitBash() != null && File.Exists(Path.Combine(Dir, "protection.sh")) && HasBashRcHook(); }

    // True when installed runtime scripts differ from the EXE-embedded version
    // (for example when a new GUI build ships new protection layers while the
    // user installation still has older files). Compare scripts only, NOT the
    // config; user config must be preserved.
    public static bool IsRuntimeOutdated()
    {
        if (!HasRuntimeFiles()) return false;
        return !FileMatchesEmbedded(Path.Combine(Dir, "protection.sh"), EmbeddedScripts.ProtectionSh)
            || !FileMatchesEmbedded(Path.Combine(Dir, "env-loader.sh"), EmbeddedScripts.EnvLoaderSh);
    }

    static bool FileMatchesEmbedded(string path, string expected)
    {
        try
        {
            if (!File.Exists(path)) return false;
            // WrUnix normalizes on write: TrimStart CR/LF + CRLF->LF. Apply the
            // same normalization to the embedded string so round-trip comparisons
            // stay stable. Also normalize file content CRLF->LF in case an
            // external tool rewrote the file.
            string actual = File.ReadAllText(path, Encoding.UTF8).Replace("\r\n", "\n");
            string normalizedExpected = (expected ?? "").TrimStart('\r', '\n').Replace("\r\n", "\n");
            return string.Equals(actual, normalizedExpected, StringComparison.Ordinal);
        }
        catch
        {
            // On read errors, conservatively return "matches" so transient IO
            // issues do not trigger an update banner.
            return true;
        }
    }

    static void WrUnix(string path, string content)
    {
        File.WriteAllText(path, content.TrimStart('\r', '\n').Replace("\r\n", "\n"), new UTF8Encoding(false));
    }

    static void WritePreviousBashEnv(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            if (File.Exists(PreviousBashEnvPath)) File.Delete(PreviousBashEnvPath);
            return;
        }
        File.WriteAllText(PreviousBashEnvPath, value.Trim(), new UTF8Encoding(false));
    }

    static void ConfigureUserBashEnv(StringBuilder log)
    {
        string current = GetUserBashEnv();
        if (NormalizeEnvPath(current) == NormalizeEnvPath(EnvLoaderPath))
        {
            if (!string.Equals(current, EnvLoaderPath, StringComparison.OrdinalIgnoreCase))
                Environment.SetEnvironmentVariable("BASH_ENV", EnvLoaderPath, EnvironmentVariableTarget.User);
            log.AppendLine(Loc.T("installer.bash_env_correct"));
            return;
        }

        if (string.IsNullOrWhiteSpace(current))
        {
            WritePreviousBashEnv("");
            Environment.SetEnvironmentVariable("BASH_ENV", EnvLoaderPath, EnvironmentVariableTarget.User);
            log.AppendLine(Loc.T("installer.bash_env_enabled"));
            return;
        }

        WritePreviousBashEnv(current);
        Environment.SetEnvironmentVariable("BASH_ENV", EnvLoaderPath, EnvironmentVariableTarget.User);
        log.AppendLine(Loc.T("installer.bash_env_chained"));
    }

    public static string DoInstall()
    {
        var l = new StringBuilder();
        try
        {
            if (FindGitBash() == null) return Loc.T("installer.git_bash_missing");
            Directory.CreateDirectory(Dir);
            WrUnix(Path.Combine(Dir, "protection.sh"), EmbeddedScripts.ProtectionSh);
            l.AppendLine(Loc.T("installer.protection_installed"));
            string cfg = Path.Combine(Dir, "config.conf");
            if (!File.Exists(cfg)) { WrUnix(cfg, SeedFreshInstallDefaultAreas(EmbeddedScripts.DefaultConf)); l.AppendLine(Loc.T("installer.default_config_created")); }
            else l.AppendLine(Loc.T("installer.existing_config_kept"));
            string lp = Path.Combine(Dir, "blocked.log");
            if (!File.Exists(lp)) File.Create(lp).Dispose();
            WrUnix(Path.Combine(Dir, "env-loader.sh"), EmbeddedScripts.EnvLoaderSh);
            string bashrc = File.Exists(Rc) ? File.ReadAllText(Rc, Encoding.UTF8) : "";
            if (!bashrc.Contains(MB))
            {
                if (!File.Exists(Rc)) File.Create(Rc).Dispose();
                File.AppendAllText(Rc, EmbeddedScripts.BashrcBlock.Replace("\r\n", "\n"), new UTF8Encoding(false));
                l.AppendLine(Loc.T("installer.shell_config_updated"));
            }
            ConfigureUserBashEnv(l);
            try
            {
                ShortcutHelper.CreateStartMenuShortcut(GuiApp.AppUserModelId);
                l.AppendLine(Loc.T("installer.shortcut_created"));
            }
            catch (Exception ex) { l.AppendLine(Loc.F("installer.shortcut_warning", ex.Message)); }
            l.AppendLine(Loc.T("installer.install_done"));
        }
        catch (Exception ex) { l.AppendLine(Loc.F("installer.error_prefix", ex.Message)); }
        return l.ToString();
    }

    public static string DoUninstall()
    {
        var l = new StringBuilder();
        try
        {
            if (File.Exists(Rc))
            {
                string b = File.ReadAllText(Rc, Encoding.UTF8);
                if (b.Contains(MB))
                {
                    var ln = File.ReadAllLines(Rc, Encoding.UTF8);
                    var cl = new List<string>(); bool ib = false;
                    foreach (var line in ln)
                    {
                        if (line.Contains(MB)) { ib = true; continue; }
                        if (line.Contains(ME)) { ib = false; continue; }
                        if (!ib) cl.Add(line);
                    }
                    File.WriteAllText(Rc, string.Join("\n", cl).Replace("\r\n", "\n"), new UTF8Encoding(false));
                }
            }
            string lp = Path.Combine(Dir, "blocked.log");
            if (File.Exists(lp) && new FileInfo(lp).Length > 0)
            {
                string bk = Path.Combine(Home, "shell-secure-log-backup.txt");
                File.Copy(lp, bk, true);
                l.AppendLine(Loc.F("installer.log_backup", bk));
            }
            if (IsOwnedBashEnv())
            {
                string previous = GetPreviousBashEnv();
                Environment.SetEnvironmentVariable("BASH_ENV",
                    string.IsNullOrWhiteSpace(previous) ? null : previous,
                    EnvironmentVariableTarget.User);
            }
            SetAutostart(false);
            ShortcutHelper.RemoveStartMenuShortcut();
            if (Directory.Exists(Dir)) Directory.Delete(Dir, true);
            l.AppendLine(Loc.T("installer.removed"));
        }
        catch (Exception ex) { l.AppendLine(Loc.F("installer.error_prefix", ex.Message)); }
        return l.ToString();
    }

    public static string DoUpdate()
    {
        if (!Directory.Exists(Dir)) return Loc.T("installer.install_first");
        try
        {
            WrUnix(Path.Combine(Dir, "protection.sh"), EmbeddedScripts.ProtectionSh);
            WrUnix(Path.Combine(Dir, "env-loader.sh"), EmbeddedScripts.EnvLoaderSh);
            var log = new StringBuilder();
            ConfigureUserBashEnv(log);
            try { ShortcutHelper.CreateStartMenuShortcut(GuiApp.AppUserModelId); } catch { }
            log.AppendLine(Loc.T("installer.updated"));
            return log.ToString().Trim();
        }
        catch (Exception ex) { return Loc.F("installer.error_prefix", ex.Message); }
    }

    public static void RepairPortablePathArtifactsIfNeeded()
    {
        RepairAutostartPathIfNeeded();
        RepairStartMenuShortcutPathIfNeeded();
    }

    static void RepairStartMenuShortcutPathIfNeeded()
    {
        try
        {
            if (ShortcutHelper.HasStartMenuShortcut())
                ShortcutHelper.CreateStartMenuShortcut(GuiApp.AppUserModelId);
        }
        catch { }
    }

}
