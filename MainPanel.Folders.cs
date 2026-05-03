// Read this file first when changing protected-directory UI.
// Purpose: build and refresh the protected areas page.
// Scope: config save/remove actions live in MainPanel.Actions.cs.

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

partial class MainPanel
{
    FrameworkElement BuildFoldersPage()
    {
        var scroll = MakeScroll();
        var stack = new StackPanel { Margin = new Thickness(32, 28, 32, 28) };

        var header = new Grid();
        var hl = new StackPanel();
        hl.Children.Add(T(Loc.T("folders.title"), 22, TXT, true));
        hl.Children.Add(Sp(4));
        hl.Children.Add(T(Loc.T("folders.subtitle"), 13, TXT2));
        header.Children.Add(hl);

        var addBtn = Pill(Loc.T("folders.add"), C_BLUE, delegate { DoAddDir(); });
        addBtn.HorizontalAlignment = HorizontalAlignment.Right;
        addBtn.VerticalAlignment = VerticalAlignment.Bottom;
        header.Children.Add(addBtn);

        stack.Children.Add(header);
        stack.Children.Add(Sp(20));

        _dirsPanel = new StackPanel();
        stack.Children.Add(_dirsPanel);

        scroll.Content = stack;
        return scroll;
    }

    void RefreshDirs()
    {
        _dirsPanel.Children.Clear();
        if (_cfg.ProtectedDirs.Count == 0)
        {
            var empty = Card();
            var es = new StackPanel { Margin = new Thickness(24, 40, 24, 40), HorizontalAlignment = HorizontalAlignment.Center };
            var ei = T("\U0001F4C2", 36, TXT3); ei.HorizontalAlignment = HorizontalAlignment.Center;
            es.Children.Add(ei); es.Children.Add(Sp(12));
            var et = T(Loc.T("folders.empty.title"), 14, TXT2); et.HorizontalAlignment = HorizontalAlignment.Center;
            es.Children.Add(et); es.Children.Add(Sp(6));
            var eh = T(Loc.T("folders.empty.hint"), 12, TXT3);
            eh.HorizontalAlignment = HorizontalAlignment.Center; eh.TextWrapping = TextWrapping.Wrap; eh.TextAlignment = TextAlignment.Center;
            es.Children.Add(eh);
            empty.Child = es;
            _dirsPanel.Children.Add(empty);
            return;
        }

        foreach (var dir in _cfg.ProtectedDirs)
        {
            var row = new Border
            {
                Background = B(C_CARD), CornerRadius = new CornerRadius(8),
                Padding = new Thickness(16, 14, 16, 14), Margin = new Thickness(0, 0, 0, 8),
                BorderBrush = B(C_BRD), BorderThickness = new Thickness(1),
            };
            var g = new Grid();
            var left = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            left.Children.Add(T("\U0001F4C1", 16, BLUE));
            var dl = T("  " + dir, 13, TXT); dl.TextTrimming = TextTrimming.CharacterEllipsis; dl.MaxWidth = 340;
            left.Children.Add(dl);
            g.Children.Add(left);

            string cap = dir;
            var rb = Pill(Loc.T("common.remove"), C_RED, delegate { DoRemoveDir(cap); });
            rb.HorizontalAlignment = HorizontalAlignment.Right;
            rb.VerticalAlignment = VerticalAlignment.Center;
            g.Children.Add(rb);
            row.Child = g;
            _dirsPanel.Children.Add(row);
        }
    }
}
