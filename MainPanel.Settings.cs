// Read this file first when changing settings toggles, system status, or whitelist UI.
// Purpose: build and refresh the settings page.
// Scope: actual config mutation lives in MainPanel.Actions.cs.

using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

partial class MainPanel
{
    void MakeToggle(out Border toggle, out Border dot, Action onClick)
    {
        toggle = new Border
        {
            Width = 50, Height = 28, CornerRadius = new CornerRadius(14),
            Cursor = Cursors.Hand,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        dot = new Border
        {
            Width = 22, Height = 22, CornerRadius = new CornerRadius(11),
            Background = TXT, VerticalAlignment = VerticalAlignment.Center
        };
        toggle.Child = dot;
        var click = onClick;
        toggle.PreviewMouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
        {
            e.Handled = true;
            click();
        };
    }

    void SetToggleVisual(Border toggle, Border dot, bool on)
    {
        toggle.Background = on ? GREEN : B(50, 255, 255, 255);
        dot.HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left;
        dot.Margin = on ? new Thickness(0, 0, 3, 0) : new Thickness(3, 0, 0, 0);
    }

    // Language picker: two pill buttons (EN/DE) instead of a toggle because the
    // choice is not semantically on/off. The active language gets a brighter
    // accent; the inactive one stays muted.
    Border BuildLanguageRow(string title, string hint, out Border enBtn, out Border deBtn,
        Action onPickEn, Action onPickDe)
    {
        var card = Card();
        var inner = new Grid { Margin = new Thickness(20, 18, 20, 18) };
        inner.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        inner.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var left = new StackPanel { Margin = new Thickness(0, 0, 16, 0), VerticalAlignment = VerticalAlignment.Center };
        left.Children.Add(T(title, 14, TXT, true));
        var h = T(hint, 12, TXT3);
        h.Margin = new Thickness(0, 4, 0, 0);
        h.TextWrapping = TextWrapping.Wrap;
        left.Children.Add(h);
        Grid.SetColumn(left, 0);
        inner.Children.Add(left);

        var pickerRow = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        enBtn = MakeLanguagePill(Loc.T("settings.language.en"), onPickEn);
        deBtn = MakeLanguagePill(Loc.T("settings.language.de"), onPickDe);
        deBtn.Margin = new Thickness(8, 0, 0, 0);
        pickerRow.Children.Add(enBtn);
        pickerRow.Children.Add(deBtn);
        Grid.SetColumn(pickerRow, 1);
        inner.Children.Add(pickerRow);

        card.Child = inner;
        return card;
    }

    Border MakeLanguagePill(string label, Action onClick)
    {
        var pill = new Border
        {
            CornerRadius = new CornerRadius(16),
            Padding = new Thickness(16, 7, 16, 7),
            Cursor = Cursors.Hand,
            BorderThickness = new Thickness(1)
        };
        pill.Child = T(label, 12, TXT, true);
        var click = onClick;
        pill.PreviewMouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
        {
            e.Handled = true;
            click();
        };
        pill.MouseEnter += delegate { pill.Opacity = 0.85; };
        pill.MouseLeave += delegate { pill.Opacity = 1.0; };
        return pill;
    }

    void SetLanguagePillVisual(Border pill, bool active)
    {
        if (active)
        {
            pill.Background = B(40, C_GREEN.R, C_GREEN.G, C_GREEN.B);
            pill.BorderBrush = B(80, C_GREEN.R, C_GREEN.G, C_GREEN.B);
            ((TextBlock)pill.Child).Foreground = GREEN;
        }
        else
        {
            pill.Background = B(12, 255, 255, 255);
            pill.BorderBrush = B(C_BRD);
            ((TextBlock)pill.Child).Foreground = TXT2;
        }
    }

    Border BuildToggleRow(string title, string hint, out Border toggle, out Border dot, Action onClick)
    {
        var card = Card();
        var inner = new Grid { Margin = new Thickness(20, 18, 20, 18) };
        // Right margin for the toggle; otherwise long hint text overlaps the pill.
        var left = new StackPanel { Margin = new Thickness(0, 0, 70, 0) };
        left.Children.Add(T(title, 14, TXT, true));
        var h = T(hint, 12, TXT3);
        h.Margin = new Thickness(0, 4, 0, 0);
        h.TextWrapping = TextWrapping.Wrap;
        left.Children.Add(h);
        inner.Children.Add(left);
        MakeToggle(out toggle, out dot, onClick);
        inner.Children.Add(toggle);
        card.Child = inner;
        return card;
    }

    // Number input row for tunable protection values. Commits on
    // Enter / LostFocus when the value is a valid integer in [min, max].
    // Invalid input gets reverted via RefreshSettings (which rebuilds the
    // page and re-syncs the textbox from the current config).
    Border BuildNumberInputRow(string title, string hint, int current, int min, int max, out TextBox input, Action<int> onCommit)
    {
        var card = Card();
        var inner = new Grid { Margin = new Thickness(20, 18, 20, 18) };
        inner.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        inner.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel { Margin = new Thickness(0, 0, 16, 0), VerticalAlignment = VerticalAlignment.Center };
        left.Children.Add(T(title, 14, TXT, true));
        var h = T(hint, 12, TXT3);
        h.Margin = new Thickness(0, 4, 0, 0);
        h.TextWrapping = TextWrapping.Wrap;
        left.Children.Add(h);
        Grid.SetColumn(left, 0);
        inner.Children.Add(left);

        var box = new TextBox
        {
            Width = 90,
            FontSize = 14,
            Padding = new Thickness(10, 8, 10, 8),
            Background = new SolidColorBrush(Color.FromRgb(15, 15, 22)),
            Foreground = TXT,
            BorderBrush = B(40, 255, 255, 255),
            BorderThickness = new Thickness(1),
            CaretBrush = GREEN,
            TextAlignment = TextAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Text = current.ToString()
        };
        var captured = box;
        int boundMin = min;
        int boundMax = max;
        Action<int> commit = onCommit;
        Action tryCommit = delegate
        {
            int v;
            if (int.TryParse(captured.Text.Trim(), out v) && v >= boundMin && v <= boundMax)
            {
                commit(v);
                return;
            }
            // Invalid input is not persisted; reset the textbox to the last
            // saved config value so stale text cannot linger in the UI.
            RefreshSettings();
        };
        captured.LostFocus += delegate { tryCommit(); };
        captured.KeyDown += delegate(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Enter)
            {
                tryCommit();
                Keyboard.ClearFocus();
                e.Handled = true;
            }
        };
        Grid.SetColumn(captured, 1);
        inner.Children.Add(captured);

        card.Child = inner;
        input = captured;
        return card;
    }

    FrameworkElement BuildSettingsPage()
    {
        ResetSettingsDetailRows();

        var scroll = MakeScroll();
        var stack = new StackPanel { Margin = new Thickness(32, 28, 32, 28) };

        stack.Children.Add(T(Loc.T("settings.title"), 22, TXT, true));
        stack.Children.Add(Sp(4));
        stack.Children.Add(T(Loc.T("settings.subtitle"), 13, TXT2));
        stack.Children.Add(Sp(24));

        // Language picker sits at the top because a change rebuilds the full
        // settings screen immediately, which feels more natural at the top.
        stack.Children.Add(BuildLanguageRow(
            Loc.T("settings.language.title"),
            Loc.T("settings.language.hint"),
            out _languageEnBtn, out _languageDeBtn,
            delegate { DoSetLanguage("en"); },
            delegate { DoSetLanguage("de"); }));
        stack.Children.Add(Sp(24));

        // Fine-grained on/off switches per protection layer; they apply only
        // when the master switch (dashboard power button) is ON.
        stack.Children.Add(T(Loc.T("settings.categories.title"), 16, TXT, true));
        var catHint = T(Loc.T("settings.categories.hint"), 12, TXT3);
        catHint.Margin = new Thickness(0, 4, 0, 0);
        catHint.TextWrapping = TextWrapping.Wrap;
        stack.Children.Add(catHint);
        stack.Children.Add(Sp(14));

        stack.Children.Add(BuildExpandableToggleRow(
            "delete",
            Loc.T("settings.delete.title"),
            Loc.T("settings.delete.hint"),
            Detail(
                "settings.details.delete.blocked.rm",
                "settings.details.delete.blocked.cmd",
                "settings.details.delete.blocked.ps",
                "settings.details.delete.blocked.cwd"),
            Detail(
                "settings.details.delete.allowed.files",
                "settings.details.delete.allowed.safe",
                "settings.details.delete.allowed.outside"),
            out _deleteToggle, out _deleteDot, DoToggleDelete));
        stack.Children.Add(Sp(10));

        stack.Children.Add(BuildExpandableToggleRow(
            "git",
            Loc.T("settings.git.title"),
            Loc.T("settings.git.hint"),
            Detail(
                "settings.details.git.blocked.stash_dirty",
                "settings.details.git.blocked.stash_mutation",
                "settings.details.git.blocked.reset",
                "settings.details.git.blocked.clean",
                "settings.details.git.blocked.overwrite",
                "settings.details.git.blocked.branch"),
            Detail(
                "settings.details.git.allowed.stash_read",
                "settings.details.git.allowed.clean_dry",
                "settings.details.git.allowed.clean_tree",
                "settings.details.git.allowed.reset_soft"),
            out _gitToggle, out _gitDot, DoToggleGit));
        stack.Children.Add(Sp(10));

        stack.Children.Add(BuildExpandableToggleRow(
            "git_leak",
            Loc.T("settings.git_leak.title"),
            Loc.T("settings.git_leak.hint"),
            Detail(
                "settings.details.git_leak.blocked.env",
                "settings.details.git_leak.blocked.agent",
                "settings.details.git_leak.blocked.credentials",
                "settings.details.git_leak.blocked.timeout"),
            Detail(
                "settings.details.git_leak.allowed.examples",
                "settings.details.git_leak.allowed.clean_push",
                "settings.details.git_leak.allowed.force"),
            out _gitLeakToggle, out _gitLeakDot, DoToggleGitLeak));
        stack.Children.Add(Sp(10));

        stack.Children.Add(BuildNumberInputRow(
            Loc.T("settings.leak_timeout.title"),
            Loc.T("settings.leak_timeout.hint"),
            _cfg.GitLeakTimeout, 1, 3600,
            out _gitLeakTimeoutInput, DoCommitGitLeakTimeout));
        stack.Children.Add(Sp(10));

        stack.Children.Add(BuildExpandableToggleRow(
            "git_flood",
            Loc.T("settings.git_flood.title"),
            Loc.T("settings.git_flood.hint"),
            Detail(
                "settings.details.flood.blocked.network",
                "settings.details.flood.blocked.threshold",
                "settings.details.flood.blocked.agent_loop"),
            Detail(
                "settings.details.flood.allowed.local",
                "settings.details.flood.allowed.under_limit",
                "settings.details.flood.allowed.window_reset"),
            out _gitFloodToggle, out _gitFloodDot, DoToggleGitFlood));
        stack.Children.Add(Sp(10));

        // Threshold/window apply only when the flood toggle is ON, but remain
        // editable so users can prepare values before flipping the toggle.
        stack.Children.Add(BuildNumberInputRow(
            Loc.T("settings.flood_threshold.title"),
            Loc.T("settings.flood_threshold.hint"),
            _cfg.GitFloodThreshold, 1, 9999,
            out _gitFloodThresholdInput, DoCommitGitFloodThreshold));
        stack.Children.Add(Sp(10));

        stack.Children.Add(BuildNumberInputRow(
            Loc.T("settings.flood_window.title"),
            Loc.T("settings.flood_window.hint"),
            _cfg.GitFloodWindow, 1, 86400,
            out _gitFloodWindowInput, DoCommitGitFloodWindow));
        stack.Children.Add(Sp(10));

        stack.Children.Add(BuildExpandableToggleRow(
            "http_api",
            Loc.T("settings.http_api.title"),
            Loc.T("settings.http_api.hint"),
            Detail(
                "settings.details.http.blocked.delete",
                "settings.details.http.blocked.destructive_payload",
                "settings.details.http.blocked.authenticated"),
            Detail(
                "settings.details.http.allowed.readonly",
                "settings.details.http.allowed.unauthenticated",
                "settings.details.http.allowed.permission"),
            out _httpApiToggle, out _httpApiDot, DoToggleHttpApi));
        stack.Children.Add(Sp(10));

        stack.Children.Add(BuildExpandableToggleRow(
            "ps_utf8",
            Loc.T("settings.ps_utf8.title"),
            Loc.T("settings.ps_utf8.hint"),
            Detail(
                "settings.details.ps.blocked.cmdlets",
                "settings.details.ps.blocked.redirect",
                "settings.details.ps.blocked.dotnet"),
            Detail(
                "settings.details.ps.allowed.encoding",
                "settings.details.ps.allowed.gitbash",
                "settings.details.ps.allowed.readonly"),
            out _psEncodingToggle, out _psEncodingDot, DoTogglePsEncoding));
        stack.Children.Add(Sp(24));

        stack.Children.Add(BuildToggleRow(
            Loc.T("settings.autostart.title"),
            Loc.T("settings.autostart.hint"),
            out _autostartToggle, out _autostartDot, DoToggleAutostart));
        stack.Children.Add(Sp(16));

        var sysCard = Card();
        var sysInner = new StackPanel { Margin = new Thickness(20, 18, 20, 18) };
        sysInner.Children.Add(T(Loc.T("settings.system.title"), 14, TXT, true));
        sysInner.Children.Add(Sp(12));
        _gitBashLabel = T("", 12, TXT2); sysInner.Children.Add(_gitBashLabel);
        sysInner.Children.Add(Sp(6));
        _bashEnvLabel = T("", 12, TXT2); sysInner.Children.Add(_bashEnvLabel);
        sysCard.Child = sysInner;
        stack.Children.Add(sysCard);
        stack.Children.Add(Sp(24));

        var whHeader = new Grid();
        var whLeft = new StackPanel();
        whLeft.Children.Add(T(Loc.T("settings.whitelist.title"), 18, TXT, true));
        var whHint = T(Loc.T("settings.whitelist.hint"), 12, TXT3);
        whHint.TextWrapping = TextWrapping.Wrap; whHint.Margin = new Thickness(0, 4, 0, 0);
        whLeft.Children.Add(whHint);
        whHeader.Children.Add(whLeft);
        var whAdd = Pill(Loc.T("settings.whitelist.add"), C_BLUE, delegate { DoAddWhitelist(); });
        whAdd.HorizontalAlignment = HorizontalAlignment.Right;
        whAdd.VerticalAlignment = VerticalAlignment.Bottom;
        whHeader.Children.Add(whAdd);
        stack.Children.Add(whHeader);
        stack.Children.Add(Sp(14));

        _whitelistPanel = new StackPanel();
        stack.Children.Add(_whitelistPanel);

        scroll.Content = stack;
        return scroll;
    }

    void RefreshSettings()
    {
        if (_languageEnBtn != null && _languageDeBtn != null)
        {
            SetLanguagePillVisual(_languageEnBtn, _cfg.Language != "de");
            SetLanguagePillVisual(_languageDeBtn, _cfg.Language == "de");
        }
        SetToggleVisual(_deleteToggle, _deleteDot, _cfg.DeleteProtect);
        SetToggleVisual(_gitToggle, _gitDot, _cfg.GitProtect);
        SetToggleVisual(_gitLeakToggle, _gitLeakDot, _cfg.GitLeakProtect);
        SetToggleVisual(_gitFloodToggle, _gitFloodDot, _cfg.GitFloodProtect);
        SetToggleVisual(_httpApiToggle, _httpApiDot, _cfg.HttpApiProtect);
        SetToggleVisual(_psEncodingToggle, _psEncodingDot, _cfg.PsEncodingProtect);
        // Number inputs are fed from current config again; after invalid input
        // this acts like a revert to the last persisted value.
        if (_gitLeakTimeoutInput != null)
            _gitLeakTimeoutInput.Text = _cfg.GitLeakTimeout.ToString();
        if (_gitFloodThresholdInput != null)
            _gitFloodThresholdInput.Text = _cfg.GitFloodThreshold.ToString();
        if (_gitFloodWindowInput != null)
            _gitFloodWindowInput.Text = _cfg.GitFloodWindow.ToString();

        SetToggleVisual(_autostartToggle, _autostartDot, Installer.IsAutostartEnabled());

        string bash = Installer.FindGitBash();
        _gitBashLabel.Text = bash != null ? Loc.F("settings.git_bash.found", bash) : Loc.T("settings.git_bash.missing");
        _gitBashLabel.Foreground = bash != null ? GREEN : RED;

        string be = Installer.GetUserBashEnv();
        if (Installer.IsOwnedBashEnv() && File.Exists(Path.Combine(_cfg.InstallDir, "env-loader.sh")))
        {
            string previous = Installer.GetPreviousBashEnv();
            _bashEnvLabel.Text = string.IsNullOrWhiteSpace(previous)
                ? Loc.T("settings.bash_env.full")
                : Loc.T("settings.bash_env.chained");
            _bashEnvLabel.Foreground = GREEN;
        }
        else if (!string.IsNullOrWhiteSpace(be))
        {
            _bashEnvLabel.Text = Loc.T("settings.bash_env.foreign");
            _bashEnvLabel.Foreground = RED;
        }
        else
        {
            _bashEnvLabel.Text = Loc.T("settings.bash_env.missing");
            _bashEnvLabel.Foreground = ORANGE;
        }

        _whitelistPanel.Children.Clear();
        var wrap = new WrapPanel();
        foreach (var t in _cfg.SafeTargets)
        {
            var tag = new Border
            {
                Background = B(12, 255, 255, 255), CornerRadius = new CornerRadius(14),
                Padding = new Thickness(12, 6, 8, 6), Margin = new Thickness(0, 0, 8, 8),
            };
            var r = new StackPanel { Orientation = Orientation.Horizontal };
            r.Children.Add(T(t, 12, TXT2));
            string cap = t;
            var x = T(" \u2715", 11, TXT3); x.Cursor = Cursors.Hand; x.Margin = new Thickness(4, 0, 0, 0);
            x.MouseLeftButtonUp += delegate { DoRemoveWhitelist(cap); };
            x.MouseEnter += delegate { x.Foreground = RED; };
            x.MouseLeave += delegate { x.Foreground = TXT3; };
            r.Children.Add(x);
            tag.Child = r;
            wrap.Children.Add(tag);
        }
        _whitelistPanel.Children.Add(wrap);
    }
}
