// Read this file first when changing blocked-log rendering.
// Purpose: build and refresh the protocol page.
// Scope: log file reading lives in ShellSecureConfig.cs; toast classification lives in GuiApp.cs.

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

partial class MainPanel
{
    FrameworkElement BuildLogPage()
    {
        var scroll = MakeScroll();
        var stack = new StackPanel { Margin = new Thickness(32, 28, 32, 28) };

        var header = new Grid();
        var hl = new StackPanel { Orientation = Orientation.Horizontal };
        hl.Children.Add(T(Loc.T("log.title"), 22, TXT, true));
        _logCountTxt = T("", 13, TXT3); _logCountTxt.VerticalAlignment = VerticalAlignment.Bottom;
        _logCountTxt.Margin = new Thickness(12, 0, 0, 3);
        hl.Children.Add(_logCountTxt);
        header.Children.Add(hl);

        var btns = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom };
        var clrBtn = Pill(Loc.T("common.clear"), C_RED, delegate { DoClearLog(); });
        clrBtn.Margin = new Thickness(0, 0, 8, 0);
        btns.Children.Add(clrBtn);
        btns.Children.Add(Pill(Loc.T("common.refresh"), C_BLUE, delegate { RefreshLog(); }));
        header.Children.Add(btns);

        stack.Children.Add(header);
        stack.Children.Add(Sp(4));
        stack.Children.Add(T(Loc.T("log.subtitle"), 13, TXT2));
        stack.Children.Add(Sp(20));

        _logPanel = new StackPanel();
        stack.Children.Add(_logPanel);

        scroll.Content = stack;
        return scroll;
    }

    void RefreshLog()
    {
        _logPanel.Children.Clear();
        int total = _cfg.GetLogCount();
        _logCountTxt.Text = total > 0 ? "(" + total + ")" : "";
        _lastLog = total;
        _lastLogSize = _cfg.GetLogSize();

        var lines = _cfg.GetLogLines(30);
        if (lines.Count == 0)
        {
            var empty = Card();
            var es = new StackPanel { Margin = new Thickness(24, 40, 24, 40), HorizontalAlignment = HorizontalAlignment.Center };
            es.Children.Add(T("\u2714", 36, GREEN)); ((TextBlock)es.Children[0]).HorizontalAlignment = HorizontalAlignment.Center;
            es.Children.Add(Sp(12));
            var et = T(Loc.T("log.empty.title"), 14, TXT2); et.HorizontalAlignment = HorizontalAlignment.Center;
            es.Children.Add(et); es.Children.Add(Sp(4));
            var eh = T(Loc.T("log.empty.hint"), 12, TXT3); eh.HorizontalAlignment = HorizontalAlignment.Center;
            es.Children.Add(eh);
            empty.Child = es;
            _logPanel.Children.Add(empty);
            return;
        }

        foreach (var line in lines)
        {
            var entry = new Border
            {
                Background = B(C_CARD), CornerRadius = new CornerRadius(6),
                Padding = new Thickness(14, 10, 14, 10), Margin = new Thickness(0, 0, 0, 4),
                BorderBrush = B(C_BRD), BorderThickness = new Thickness(1),
            };
            var tb = new TextBlock
            {
                Text = line, FontSize = 11, Foreground = TXT3,
                FontFamily = new FontFamily("Consolas"),
                TextWrapping = TextWrapping.Wrap,
            };
            if (line.Contains("BLOCKED") || line.Contains("BLOCKIERT"))
            {
                tb.Foreground = ORANGE; tb.FontWeight = FontWeights.SemiBold;
                entry.BorderBrush = B(30, C_ORANGE.R, C_ORANGE.G, C_ORANGE.B);
            }
            entry.Child = tb;
            _logPanel.Children.Add(entry);
        }
    }
}
