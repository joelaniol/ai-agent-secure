// Read this file first when changing the dashboard/status surface.
// Purpose: build and refresh protection status, counters, banner, and tray color.
// Scope: install/update actions and config persistence live in MainPanel.Actions.cs.

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;

partial class MainPanel
{
    FrameworkElement BuildDashboardPage()
    {
        var scroll = MakeScroll();
        var stack = new StackPanel { Margin = new Thickness(32, 28, 32, 28) };

        stack.Children.Add(T(Loc.T("dashboard.title"), 22, TXT, true));
        stack.Children.Add(Sp(4));
        stack.Children.Add(T(Loc.T("dashboard.subtitle"), 13, TXT2));
        stack.Children.Add(Sp(24));

        _statusBanner = new Border { CornerRadius = new CornerRadius(10), Padding = new Thickness(18, 14, 18, 14) };
        var bRow = new StackPanel { Orientation = Orientation.Horizontal };
        _bannerIcon = T("", 16, GREEN); _bannerIcon.Margin = new Thickness(0, 0, 12, 0);
        _bannerText = T("", 14, GREEN, true);
        bRow.Children.Add(_bannerIcon); bRow.Children.Add(_bannerText);
        _statusBanner.Child = bRow;
        stack.Children.Add(_statusBanner);
        stack.Children.Add(Sp(10));

        // Update-Banner: zeigt sich nur wenn die installierte protection.sh
        // bzw. env-loader.sh nicht mit den ins EXE eingebetteten Versionen
        // uebereinstimmen. Triggert den bestehenden DoUpdate()-Pfad, sodass
        // bestehende Installationen die neuen Schutz-Layer aktiv ziehen
        // koennen, ohne dass der Nutzer die Installer-Seite findet.
        _updateBanner = new Border
        {
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(18, 14, 18, 14),
            Background = B(20, C_ORANGE.R, C_ORANGE.G, C_ORANGE.B),
            BorderBrush = B(60, C_ORANGE.R, C_ORANGE.G, C_ORANGE.B),
            BorderThickness = new Thickness(1),
            Visibility = Visibility.Collapsed,
        };
        var uRow = new Grid();
        uRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        uRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var uLeft = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 16, 0) };
        var uHead = new StackPanel { Orientation = Orientation.Horizontal };
        var uIcon = T("✨", 16, ORANGE); uIcon.Margin = new Thickness(0, 0, 10, 0);
        var uTitle = T(Loc.T("dashboard.update.title"), 14, ORANGE, true);
        uHead.Children.Add(uIcon); uHead.Children.Add(uTitle);
        uLeft.Children.Add(uHead);
        var uHint = T(Loc.T("dashboard.update.hint"), 12, TXT2);
        uHint.Margin = new Thickness(26, 4, 0, 0);
        uHint.TextWrapping = TextWrapping.Wrap;
        uLeft.Children.Add(uHint);
        Grid.SetColumn(uLeft, 0);
        uRow.Children.Add(uLeft);
        var uBtn = Pill(Loc.T("dashboard.update.button"), C_ORANGE, delegate { DoUpdate(); });
        uBtn.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(uBtn, 1);
        uRow.Children.Add(uBtn);
        _updateBanner.Child = uRow;
        stack.Children.Add(_updateBanner);
        stack.Children.Add(Sp(28));

        _powerBtn = new Border
        {
            Width = 130, Height = 130, CornerRadius = new CornerRadius(65),
            Cursor = System.Windows.Input.Cursors.Hand, HorizontalAlignment = HorizontalAlignment.Center,
        };
        _powerIcon = T("\u2714", 44, B(C_BG), true);
        _powerIcon.FontFamily = new FontFamily("Segoe UI Symbol");
        _powerIcon.HorizontalAlignment = HorizontalAlignment.Center;
        _powerIcon.VerticalAlignment = VerticalAlignment.Center;
        _powerBtn.Child = _powerIcon;
        _powerBtn.PreviewMouseLeftButtonDown += delegate(object s, System.Windows.Input.MouseButtonEventArgs e) { e.Handled = true; DoToggle(); };
        _powerBtn.MouseEnter += delegate { _powerBtn.Opacity = 0.88; };
        _powerBtn.MouseLeave += delegate { _powerBtn.Opacity = 1.0; };
        stack.Children.Add(_powerBtn);
        stack.Children.Add(Sp(16));

        _statusTitle = T("", 20, TXT, true);
        _statusTitle.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(_statusTitle);
        stack.Children.Add(Sp(6));
        _statusSub = T("", 12, TXT2);
        _statusSub.HorizontalAlignment = HorizontalAlignment.Center;
        _statusSub.TextAlignment = TextAlignment.Center;
        _statusSub.TextWrapping = TextWrapping.Wrap;
        stack.Children.Add(_statusSub);

        stack.Children.Add(Sp(32));
        var statsGrid = new Grid();
        statsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        statsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        statsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        statsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        statsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var s1 = MakeStatCard("\U0001F4C2", Loc.T("dashboard.stat.dirs"), out _statDirs);
        Grid.SetColumn(s1, 0); statsGrid.Children.Add(s1);
        var s2 = MakeStatCard("\u2705", Loc.T("dashboard.stat.whitelist"), out _statWhitelist);
        Grid.SetColumn(s2, 2); statsGrid.Children.Add(s2);
        var s3 = MakeStatCard("\U0001F6E1", Loc.T("dashboard.stat.blocked"), out _statBlocked);
        Grid.SetColumn(s3, 4); statsGrid.Children.Add(s3);
        stack.Children.Add(statsGrid);

        scroll.Content = stack;
        return scroll;
    }

    Border MakeStatCard(string icon, string label, out TextBlock valueTb)
    {
        var card = Card();
        var s = new StackPanel { Margin = new Thickness(16, 16, 16, 16), HorizontalAlignment = HorizontalAlignment.Center };
        var top = T(icon, 20, TXT3); top.HorizontalAlignment = HorizontalAlignment.Center;
        s.Children.Add(top);
        valueTb = T("0", 28, TXT, true); valueTb.HorizontalAlignment = HorizontalAlignment.Center;
        valueTb.Margin = new Thickness(0, 8, 0, 4);
        s.Children.Add(valueTb);
        var lb = T(label, 11, TXT3); lb.HorizontalAlignment = HorizontalAlignment.Center;
        s.Children.Add(lb);
        card.Child = s;
        return card;
    }

    void RefreshDashboard()
    {
        var state = GetProtectionState();
        if (state == ProtectionState.NotInstalled)
        {
            SetBanner(C_RED, "\u26A0", Loc.T("dashboard.banner.not_installed"));
            _powerBtn.Background = B(50, 255, 255, 255); _powerBtn.Effect = null;
            _powerIcon.Text = "!";
            _powerIcon.Foreground = TXT3; _powerBtn.IsEnabled = false;
            _statusTitle.Text = Loc.T("dashboard.status.not_installed"); _statusTitle.Foreground = TXT3;
            _statusSub.Text = Loc.T("dashboard.status.not_installed_hint");
        }
        else if (state == ProtectionState.FullyProtected)
        {
            SetBanner(C_GREEN, "\u2714", Loc.T("dashboard.banner.full"));
            _powerBtn.Background = GREEN;
            _powerBtn.Effect = new DropShadowEffect { Color = C_GREEN, BlurRadius = 50, ShadowDepth = 0, Opacity = 0.35 };
            _powerIcon.Text = "\u2714";
            _powerIcon.Foreground = B(C_BG); _powerBtn.IsEnabled = true;
            _statusTitle.Text = Loc.T("dashboard.status.on"); _statusTitle.Foreground = GREEN;
            _statusSub.Text = Loc.T("dashboard.status.full_hint");
        }
        else if (state == ProtectionState.InteractiveOnly)
        {
            SetBanner(C_ORANGE, "\u26A0", Loc.T("dashboard.banner.partial"));
            _powerBtn.Background = B(C_ORANGE);
            _powerBtn.Effect = new DropShadowEffect { Color = C_ORANGE, BlurRadius = 38, ShadowDepth = 0, Opacity = 0.3 };
            _powerIcon.Text = "\u2714";
            _powerIcon.Foreground = B(C_BG); _powerBtn.IsEnabled = true;
            _statusTitle.Text = Loc.T("dashboard.status.on"); _statusTitle.Foreground = ORANGE;
            _statusSub.Text = Loc.T("dashboard.status.partial_hint");
        }
        else if (state == ProtectionState.NeedsRepair)
        {
            SetBanner(C_RED, "\u26A0", Loc.T("dashboard.banner.repair"));
            _powerBtn.Background = RED;
            _powerBtn.Effect = new DropShadowEffect { Color = C_RED, BlurRadius = 35, ShadowDepth = 0, Opacity = 0.3 };
            _powerIcon.Text = "!";
            _powerIcon.Foreground = B(C_BG); _powerBtn.IsEnabled = true;
            _statusTitle.Text = Loc.T("dashboard.status.repair_title"); _statusTitle.Foreground = RED;
            _statusSub.Text = Loc.T("dashboard.status.repair_hint");
        }
        else
        {
            SetBanner(C_ORANGE, "\u26A0", Loc.T("dashboard.banner.disabled"));
            _powerBtn.Background = RED;
            _powerBtn.Effect = new DropShadowEffect { Color = C_RED, BlurRadius = 35, ShadowDepth = 0, Opacity = 0.3 };
            _powerIcon.Text = "\u2715";
            _powerIcon.Foreground = B(C_BG); _powerBtn.IsEnabled = true;
            _statusTitle.Text = Loc.T("dashboard.status.off"); _statusTitle.Foreground = RED;
            _statusSub.Text = Loc.T("dashboard.status.off_hint");
        }
        // Update-Banner nur zeigen wenn installiert UND Skripte veraltet sind.
        // Bei "nicht installiert" deckt schon der NotInstalled-Status alles ab;
        // wir wollen nicht beide Banner gleichzeitig.
        bool runtimeOutdated = _cfg.IsInstalled && Installer.IsRuntimeOutdated();
        _updateBanner.Visibility = runtimeOutdated ? Visibility.Visible : Visibility.Collapsed;

        RefreshStats();
        UpdateTrayIcon();
    }

    void RefreshStats()
    {
        if (_statDirs == null || _statWhitelist == null || _statBlocked == null) return;
        _statDirs.Text = _cfg.ProtectedDirs.Count.ToString();
        _statWhitelist.Text = _cfg.SafeTargets.Count.ToString();
        _statBlocked.Text = _lastLog.ToString();
    }

    void SetBanner(Color c, string icon, string text)
    {
        _statusBanner.Background = B(20, c.R, c.G, c.B);
        _bannerIcon.Text = icon; _bannerIcon.Foreground = B(c);
        _bannerText.Text = text; _bannerText.Foreground = B(c);
    }

    void UpdateTrayIcon()
    {
        if (_tray == null) return;
        var old = _tray.Icon;
        var state = GetProtectionState();
        var color = state == ProtectionState.FullyProtected ? C_GREEN
            : state == ProtectionState.InteractiveOnly ? C_ORANGE
            : C_RED;
        _tray.Icon = MakeShieldIcon(color);
        if (old != null) old.Dispose();
    }
}
