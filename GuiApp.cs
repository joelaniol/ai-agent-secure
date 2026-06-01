// AI Agent Secure GUI - Portable WPF Application
// Build: build-gui.ps1 -> dist/shell-secure-gui.exe
// Purpose: GUI entry point and MainPanel lifecycle/tray orchestration.
// Scope: UI pages, dialogs, config parsing, and installer work live in the sibling *.cs files.
// Read with: MainPanel.*.cs, ShellSecureConfig.cs, Installer.cs, ToastWindow.cs, Dialogs.cs.

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using WinForms = System.Windows.Forms;
using Drawing = System.Drawing;

// =================================================================
// Entry Point
// =================================================================

class GuiApp
{
    // Must match in the shortcut and process so Windows shows toast/balloon
    // notifications reliably (Win10 1607+).
    public const string AppUserModelId = "AIAgentSecure.Gui";

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void SetCurrentProcessExplicitAppUserModelID(
        [MarshalAs(UnmanagedType.LPWStr)] string AppID);

    [STAThread]
    static void Main(string[] args)
    {
        try
        {
            try { SetCurrentProcessExplicitAppUserModelID(AppUserModelId); } catch { }
            Installer.RepairPortablePathArtifactsIfNeeded();
            var app = new Application();
            app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            app.DispatcherUnhandledException += delegate(object sender, DispatcherUnhandledExceptionEventArgs e)
            {
                ShowFatalError(e.Exception);
                e.Handled = true;
                app.Shutdown(-1);
            };
            var win = new MainPanel(app);
            app.Run(win);
        }
        catch (Exception ex)
        {
            ShowFatalError(ex);
        }
    }

    static void ShowFatalError(Exception ex)
    {
        try
        {
            MessageBox.Show(
                Loc.F("fatal.message", ex.Message),
                Loc.T("fatal.title"),
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        catch { }
    }
}

// =================================================================
// Main Window Core
// =================================================================

partial class MainPanel : Window
{
    enum ProtectionState
    {
        NotInstalled,
        Disabled,
        FullyProtected,
        InteractiveOnly,
        NeedsRepair
    }

    ShellSecureConfig _cfg = new ShellSecureConfig();
    Application _app;
    WinForms.NotifyIcon _tray;
    ToastWindow _toast;
    DispatcherTimer _watcher;
    FileSystemWatcher _fsWatcher;
    int _lastLog = 0;
    long _lastLogSize = 0;
    long _lastToastLogSize = 0;
    string _lastToastLogPath = "";
    string _watchedLogPath = "";
    bool _allowClose = false;

    // ── Design Tokens ──
    static SolidColorBrush B(byte a, byte r, byte g, byte b) { return new SolidColorBrush(Color.FromArgb(a, r, g, b)); }
    static SolidColorBrush B(Color c) { return new SolidColorBrush(c); }

    static readonly Color C_BG      = Color.FromRgb(15, 15, 22);
    static readonly Color C_SIDE    = Color.FromRgb(20, 20, 30);
    static readonly Color C_SURF    = Color.FromRgb(24, 24, 36);
    static readonly Color C_CARD    = Color.FromRgb(30, 30, 44);
    static readonly Color C_GREEN   = Color.FromRgb(72, 199, 116);
    static readonly Color C_RED     = Color.FromRgb(235, 77, 77);
    static readonly Color C_ORANGE  = Color.FromRgb(255, 170, 50);
    static readonly Color C_BLUE    = Color.FromRgb(88, 166, 255);
    static readonly Color C_TXT     = Color.FromRgb(232, 232, 248);
    static readonly Color C_TXT2    = Color.FromRgb(145, 145, 172);
    static readonly Color C_TXT3    = Color.FromRgb(80, 80, 105);
    static readonly Color C_BRD     = Color.FromArgb(15, 255, 255, 255);

    static readonly SolidColorBrush GREEN = B(C_GREEN), RED = B(C_RED), ORANGE = B(C_ORANGE);
    static readonly SolidColorBrush BLUE = B(C_BLUE), TXT = B(C_TXT), TXT2 = B(C_TXT2);
    static readonly SolidColorBrush TXT3 = B(C_TXT3), TRANS = Brushes.Transparent;

    Border _pageContainer;
    int _activePage = 0;
    string _lastUiLang;
    Border[] _navItems;
    TextBlock[] _navLabels;
    FrameworkElement[] _pages;

    Border _powerBtn; TextBlock _powerIcon, _statusTitle, _statusSub;
    Border _statusBanner; TextBlock _bannerIcon, _bannerText;
    Border _updateBanner;
    TextBlock _statDirs, _statWhitelist, _statBlocked;

    StackPanel _dirsPanel;

    Border _installActionBtn; TextBlock _installActionText;
    Border _autostartToggle, _autostartDot;
    Border _languageEnBtn, _languageDeBtn;
    Border _deleteToggle, _deleteDot;
    Border _gitToggle, _gitDot;
    Border _gitLeakToggle, _gitLeakDot;
    System.Windows.Controls.TextBox _gitLeakTimeoutInput;
    Border _corruptionToggle, _corruptionDot;
    Border _gitFloodToggle, _gitFloodDot;
    System.Windows.Controls.TextBox _gitFloodThresholdInput;
    System.Windows.Controls.TextBox _gitFloodWindowInput;
    Border _httpApiToggle, _httpApiDot;
    Border _psEncodingToggle, _psEncodingDot;
    TextBlock _gitBashLabel, _bashEnvLabel;
    StackPanel _whitelistPanel;

    StackPanel _logPanel; TextBlock _logCountTxt;

    // Borderless transparent WPF windows do not get native resize edges.
    const int ResizeHitPadding = 8;
    const int WM_NCHITTEST = 0x0084;
    const int HTLEFT = 10;
    const int HTRIGHT = 11;
    const int HTTOP = 12;
    const int HTTOPLEFT = 13;
    const int HTTOPRIGHT = 14;
    const int HTBOTTOM = 15;
    const int HTBOTTOMLEFT = 16;
    const int HTBOTTOMRIGHT = 17;

    public MainPanel(Application app)
    {
        _app = app;
        Title = AppInfo.ProductName;
        var work = WinForms.Screen.PrimaryScreen.WorkingArea;
        double maxInitialWidth = Math.Max(760, work.Width - 80);
        double maxInitialHeight = Math.Max(620, work.Height - 80);
        Width = Math.Min(maxInitialWidth, Math.Max(960, Math.Min(1180, work.Width * 0.82)));
        Height = Math.Min(maxInitialHeight, Math.Max(700, Math.Min(900, work.Height * 0.84)));
        MinWidth = 760; MinHeight = 600;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = B(C_BG);
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        ResizeMode = ResizeMode.CanResize;

        ReloadConfig(true);
        Content = BuildShell();
        _lastUiLang = Loc.Lang;
        SetupTray();
        SetupWatcher();
        RefreshAll();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        var source = PresentationSource.FromVisual(this) as HwndSource;
        if (source != null) source.AddHook(WindowHitTestHook);
    }

    IntPtr WindowHitTestHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg != WM_NCHITTEST || ResizeMode == ResizeMode.NoResize || WindowState == WindowState.Maximized)
            return IntPtr.Zero;

        var p = PointFromScreen(GetScreenPoint(lParam));
        if (p.X < 0 || p.Y < 0 || p.X > ActualWidth || p.Y > ActualHeight)
            return IntPtr.Zero;

        bool left = p.X <= ResizeHitPadding;
        bool right = p.X >= ActualWidth - ResizeHitPadding;
        bool top = p.Y <= ResizeHitPadding;
        bool bottom = p.Y >= ActualHeight - ResizeHitPadding;

        if (!left && !right && !top && !bottom) return IntPtr.Zero;

        handled = true;
        if (top && left) return new IntPtr(HTTOPLEFT);
        if (top && right) return new IntPtr(HTTOPRIGHT);
        if (bottom && left) return new IntPtr(HTBOTTOMLEFT);
        if (bottom && right) return new IntPtr(HTBOTTOMRIGHT);
        if (left) return new IntPtr(HTLEFT);
        if (right) return new IntPtr(HTRIGHT);
        if (top) return new IntPtr(HTTOP);
        return new IntPtr(HTBOTTOM);
    }

    static Point GetScreenPoint(IntPtr lParam)
    {
        long value = lParam.ToInt64();
        int x = unchecked((short)(value & 0xffff));
        int y = unchecked((short)((value >> 16) & 0xffff));
        return new Point(x, y);
    }

    void SetupTray()
    {
        _tray = new WinForms.NotifyIcon();
        _tray.Text = AppInfo.ProductName;
        _tray.Icon = MakeShieldIcon(C_GREEN);
        _tray.Visible = true;
        _tray.MouseClick += delegate(object s, WinForms.MouseEventArgs e)
        {
            if (e.Button == WinForms.MouseButtons.Left) { Show(); WindowState = WindowState.Normal; Activate(); }
        };
        RefreshTrayMenu();
    }

    void RefreshTrayMenu()
    {
        if (_tray == null) return;
        var m = new WinForms.ContextMenuStrip();
        m.Items.Add(Loc.T("tray.show"), null, delegate { Show(); WindowState = WindowState.Normal; Activate(); });
        m.Items.Add(Loc.T("tray.about"), null, delegate { Show(); WindowState = WindowState.Normal; Activate(); DoAbout(); });
        m.Items.Add(new WinForms.ToolStripSeparator());
        m.Items.Add(Loc.T("tray.exit"), null, delegate { RealClose(); });
        var oldMenu = _tray.ContextMenuStrip;
        _tray.ContextMenuStrip = m;
        if (oldMenu != null) oldMenu.Dispose();
    }

    Drawing.Icon MakeShieldIcon(Color c)
    {
        using (var bmp = new Drawing.Bitmap(16, 16))
        {
            using (var g = Drawing.Graphics.FromImage(bmp))
            using (var br = new Drawing.SolidBrush(Drawing.Color.FromArgb(c.R, c.G, c.B)))
            {
                g.SmoothingMode = Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(Drawing.Color.Transparent);
                g.FillPolygon(br, new Drawing.PointF[] {
                    new Drawing.PointF(8,1), new Drawing.PointF(14,3), new Drawing.PointF(14,9),
                    new Drawing.PointF(8,15), new Drawing.PointF(2,9), new Drawing.PointF(2,3)
                });
            }
            IntPtr h = bmp.GetHicon();
            try { using (var t = Drawing.Icon.FromHandle(h)) return (Drawing.Icon)t.Clone(); }
            finally { DestroyIcon(h); }
        }
    }

    [DllImport("user32.dll")]
    static extern bool DestroyIcon(IntPtr h);

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (!_allowClose)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        base.OnClosing(e);
    }

    protected override void OnStateChanged(EventArgs e)
    {
        if (WindowState == WindowState.Minimized) Hide();
        base.OnStateChanged(e);
    }

    void RealClose()
    {
        _allowClose = true;
        if (_watcher != null) _watcher.Stop();
        DisposeFsWatcher();
        if (_tray != null)
        {
            _tray.Visible = false;
            _tray.Dispose();
            _tray = null;
        }
        if (_toast != null)
        {
            try { _toast.HideToast(); _toast.Close(); } catch { }
            _toast = null;
        }
        _app.Shutdown();
    }
}
