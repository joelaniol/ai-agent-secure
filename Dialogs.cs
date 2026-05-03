// Read this file first when changing small modal GUI prompts.
// Purpose: result and text-input dialogs shared by MainPanel actions.
// Scope: page layout and installer/config behavior live in MainPanel.*.cs and Installer.cs.

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

class ResultDialog : Window
{
    public ResultDialog(string title, string message)
    {
        Width = 440; SizeToContent = SizeToContent.Height; MaxHeight = 500;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        WindowStyle = WindowStyle.None; AllowsTransparency = true;
        Background = Brushes.Transparent; ResizeMode = ResizeMode.NoResize;

        var b = new Border { Background = new SolidColorBrush(Color.FromRgb(24, 24, 36)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(25, 255, 255, 255)),
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12),
            Padding = new Thickness(28, 24, 28, 24) };
        var s = new StackPanel();
        s.Children.Add(new TextBlock { Text = title, FontSize = 18, FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(Color.FromRgb(232, 232, 248)), Margin = new Thickness(0, 0, 0, 16) });

        var sc = new ScrollViewer { MaxHeight = 300, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        sc.Content = new TextBlock { Text = message, FontSize = 13,
            Foreground = new SolidColorBrush(Color.FromRgb(145, 145, 172)),
            TextWrapping = TextWrapping.Wrap, LineHeight = 22 };
        s.Children.Add(sc);

        var ok = new Border { Background = new SolidColorBrush(Color.FromArgb(25, 72, 199, 116)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(45, 72, 199, 116)),
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8),
            Height = 42, Margin = new Thickness(0, 20, 0, 0), Cursor = Cursors.Hand };
        ok.Child = new TextBlock { Text = Loc.T("common.ok"), FontSize = 13, FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(Color.FromRgb(72, 199, 116)),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        ok.PreviewMouseLeftButtonDown += delegate { DialogResult = true; };
        ok.MouseEnter += delegate { ok.Opacity = 0.85; };
        ok.MouseLeave += delegate { ok.Opacity = 1.0; };
        s.Children.Add(ok);
        b.Child = s; Content = b;
        KeyDown += delegate(object sender, KeyEventArgs e) { if (e.Key == Key.Enter || e.Key == Key.Escape) DialogResult = true; };
    }
}

class InputDialog : Window
{
    TextBox _in; public string Result { get; private set; }

    public InputDialog(string title, string prompt)
    {
        Width = 440; SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        WindowStyle = WindowStyle.None; AllowsTransparency = true;
        Background = Brushes.Transparent; ResizeMode = ResizeMode.NoResize;

        var b = new Border { Background = new SolidColorBrush(Color.FromRgb(24, 24, 36)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(25, 255, 255, 255)),
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12),
            Padding = new Thickness(28, 24, 28, 24) };
        var s = new StackPanel();
        s.Children.Add(new TextBlock { Text = title, FontSize = 18, FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(Color.FromRgb(232, 232, 248)), Margin = new Thickness(0, 0, 0, 12) });
        s.Children.Add(new TextBlock { Text = prompt, FontSize = 12,
            Foreground = new SolidColorBrush(Color.FromRgb(145, 145, 172)),
            Margin = new Thickness(0, 0, 0, 14), TextWrapping = TextWrapping.Wrap });

        _in = new TextBox { FontSize = 14, Padding = new Thickness(12, 10, 12, 10),
            Background = new SolidColorBrush(Color.FromRgb(15, 15, 22)),
            Foreground = new SolidColorBrush(Color.FromRgb(220, 220, 240)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(25, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            CaretBrush = new SolidColorBrush(Color.FromRgb(72, 199, 116)) };
        _in.KeyDown += delegate(object sender, KeyEventArgs e) {
            if (e.Key == Key.Enter) { Result = _in.Text; DialogResult = true; }
            if (e.Key == Key.Escape) DialogResult = false;
        };
        s.Children.Add(_in);

        var br = new Grid { Margin = new Thickness(0, 18, 0, 0) };
        br.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        br.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
        br.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var cb = DlgBtn(Loc.T("common.cancel"), Color.FromRgb(120, 120, 140));
        cb.PreviewMouseLeftButtonDown += delegate { DialogResult = false; };
        Grid.SetColumn(cb, 0); br.Children.Add(cb);
        var ob = DlgBtn(Loc.T("common.add"), Color.FromRgb(72, 199, 116));
        ob.PreviewMouseLeftButtonDown += delegate { Result = _in.Text; DialogResult = true; };
        Grid.SetColumn(ob, 2); br.Children.Add(ob);

        s.Children.Add(br); b.Child = s; Content = b;
        Loaded += delegate { _in.Focus(); };
    }

    Border DlgBtn(string text, Color c)
    {
        var btn = new Border { Background = new SolidColorBrush(Color.FromArgb(20, c.R, c.G, c.B)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(40, c.R, c.G, c.B)),
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8),
            Height = 40, Cursor = Cursors.Hand };
        btn.Child = new TextBlock { Text = text, FontSize = 13,
            Foreground = new SolidColorBrush(c),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        btn.MouseEnter += delegate { btn.Opacity = 0.85; };
        btn.MouseLeave += delegate { btn.Opacity = 1.0; };
        return btn;
    }
}
