// Read this file first when changing expandable settings detail cards.
// Purpose: render accordion details for protection category toggles.
// Scope: settings page composition stays in MainPanel.Settings.cs; config mutation stays in MainPanel.Actions.cs.

using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

partial class MainPanel
{
    class SettingsDetailRow
    {
        public string Key;
        public Border Card;
        public Border Details;
        public Border Expander;
        public TextBlock Chevron;
    }

    string _expandedSettingsKey;
    List<SettingsDetailRow> _settingsDetailRows = new List<SettingsDetailRow>();

    void ResetSettingsDetailRows()
    {
        _settingsDetailRows.Clear();
    }

    string[] Detail(params string[] keys)
    {
        var values = new string[keys.Length];
        for (int i = 0; i < keys.Length; i++)
            values[i] = Loc.T(keys[i]);
        return values;
    }

    Border BuildExpandableToggleRow(
        string key,
        string title,
        string hint,
        string[] blocked,
        string[] allowed,
        out Border toggle,
        out Border dot,
        Action onClick)
    {
        var card = Card();
        var outer = new StackPanel();

        var top = new Grid { Margin = new Thickness(20, 18, 20, 18) };
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var left = new StackPanel { Margin = new Thickness(0, 0, 16, 0), Cursor = Cursors.Hand };
        left.Children.Add(T(title, 14, TXT, true));
        var h = T(hint, 12, TXT3);
        h.Margin = new Thickness(0, 4, 0, 0);
        h.TextWrapping = TextWrapping.Wrap;
        left.Children.Add(h);
        left.PreviewMouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
        {
            e.Handled = true;
            ToggleSettingsDetail(key);
        };
        Grid.SetColumn(left, 0);
        top.Children.Add(left);

        var expand = new Border
        {
            Width = 32,
            Height = 32,
            CornerRadius = new CornerRadius(16),
            Background = B(14, 255, 255, 255),
            BorderBrush = B(24, 255, 255, 255),
            BorderThickness = new Thickness(1),
            Cursor = Cursors.Hand,
            Margin = new Thickness(0, 0, 14, 0),
            ToolTip = Loc.T("settings.details.toggle")
        };
        var chevron = T("\u2304", 16, TXT2, true);
        chevron.HorizontalAlignment = HorizontalAlignment.Center;
        chevron.VerticalAlignment = VerticalAlignment.Center;
        expand.Child = chevron;
        expand.PreviewMouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
        {
            e.Handled = true;
            ToggleSettingsDetail(key);
        };
        expand.MouseEnter += delegate { expand.Background = B(24, 255, 255, 255); chevron.Foreground = TXT; };
        expand.MouseLeave += delegate { ApplySettingsDetailExpansion(); };
        Grid.SetColumn(expand, 1);
        top.Children.Add(expand);

        MakeToggle(out toggle, out dot, onClick);
        Grid.SetColumn(toggle, 2);
        top.Children.Add(toggle);
        outer.Children.Add(top);

        var details = BuildSettingsDetails(blocked, allowed);
        outer.Children.Add(details);
        card.Child = outer;

        _settingsDetailRows.Add(new SettingsDetailRow
        {
            Key = key,
            Card = card,
            Details = details,
            Expander = expand,
            Chevron = chevron
        });
        ApplySettingsDetailExpansion();
        return card;
    }

    Border BuildSettingsDetails(string[] blocked, string[] allowed)
    {
        var box = new Border
        {
            Margin = new Thickness(20, 0, 20, 18),
            Padding = new Thickness(16, 14, 16, 14),
            CornerRadius = new CornerRadius(8),
            Background = B(10, 255, 255, 255),
            BorderBrush = B(18, 255, 255, 255),
            BorderThickness = new Thickness(1)
        };
        var stack = new StackPanel();
        stack.Children.Add(BuildRuleSection(Loc.T("settings.details.blocked"), "\u00D7", RED, blocked));
        stack.Children.Add(Sp(12));
        stack.Children.Add(BuildRuleSection(Loc.T("settings.details.allowed"), "\u2713", GREEN, allowed));
        box.Child = stack;
        return box;
    }

    FrameworkElement BuildRuleSection(string title, string marker, SolidColorBrush accent, IEnumerable<string> items)
    {
        var section = new StackPanel();
        var header = T(title, 12, accent, true);
        header.Margin = new Thickness(0, 0, 0, 8);
        section.Children.Add(header);
        foreach (string item in items)
            section.Children.Add(BuildRuleLine(marker, accent, item));
        return section;
    }

    FrameworkElement BuildRuleLine(string marker, SolidColorBrush accent, string text)
    {
        var row = new Grid { Margin = new Thickness(0, 0, 0, 6) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(22) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var mark = T(marker, 13, accent, true);
        mark.VerticalAlignment = VerticalAlignment.Top;
        Grid.SetColumn(mark, 0);
        row.Children.Add(mark);

        var label = T(text, 12, TXT2);
        label.TextWrapping = TextWrapping.Wrap;
        Grid.SetColumn(label, 1);
        row.Children.Add(label);
        return row;
    }

    void ToggleSettingsDetail(string key)
    {
        _expandedSettingsKey = string.Equals(_expandedSettingsKey, key, StringComparison.Ordinal)
            ? null
            : key;
        ApplySettingsDetailExpansion();
    }

    void ApplySettingsDetailExpansion()
    {
        foreach (var row in _settingsDetailRows)
        {
            bool open = string.Equals(_expandedSettingsKey, row.Key, StringComparison.Ordinal);
            row.Details.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
            row.Chevron.Text = open ? "\u2303" : "\u2304";
            row.Chevron.Foreground = open ? GREEN : TXT2;
            row.Expander.Background = open ? B(18, C_GREEN.R, C_GREEN.G, C_GREEN.B) : B(14, 255, 255, 255);
            row.Expander.BorderBrush = open ? B(45, C_GREEN.R, C_GREEN.G, C_GREEN.B) : B(24, 255, 255, 255);
            row.Card.BorderBrush = open ? B(60, C_GREEN.R, C_GREEN.G, C_GREEN.B) : B(C_BRD);
        }
    }
}
