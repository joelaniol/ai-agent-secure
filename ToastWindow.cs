// Read this file first when changing blocked-action notifications.
// Purpose: custom WPF toast window used instead of NotifyIcon.ShowBalloonTip.
// Scope: tray lifecycle and log classification stay in GuiApp.cs/MainPanel core.

using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using WinForms = System.Windows.Forms;

// Windows 10/11 unterdrueckt Balloons oft still (Focus Assist, fehlende
// AUMID-Bindung). Ein eigenes, topmost WPF-Fenster ist verlaesslich und
// wird von Windows-Einstellungen nicht gefiltert.
class ToastWindow : Window
{
    DispatcherTimer _closeTimer;
    TextBlock _titleTb, _msgTb;
    public event Action Clicked;

    public ToastWindow()
    {
        Title = AppInfo.ProductName + " Notification";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ShowActivated = false;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.WidthAndHeight;
        Focusable = false;

        var card = new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(24, 24, 36)),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(20, 16, 14, 16),
            BorderBrush = new SolidColorBrush(Color.FromRgb(235, 77, 77)),
            BorderThickness = new Thickness(1),
            Effect = new DropShadowEffect
            {
                BlurRadius = 22, ShadowDepth = 6, Opacity = 0.6,
                Color = Colors.Black, Direction = 270
            }
        };

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });   // Icon
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); // Content
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });   // X

        var icon = new TextBlock
        {
            Text = "\u26A0",
            FontSize = 26,
            Foreground = new SolidColorBrush(Color.FromRgb(255, 170, 50)),
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 2, 14, 0)
        };
        Grid.SetColumn(icon, 0);
        grid.Children.Add(icon);

        var stack = new StackPanel { MinWidth = 280 };
        _titleTb = new TextBlock
        {
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(Color.FromRgb(232, 232, 248)),
            TextWrapping = TextWrapping.Wrap
        };
        _msgTb = new TextBlock
        {
            FontSize = 12,
            Foreground = new SolidColorBrush(Color.FromRgb(190, 190, 215)),
            Margin = new Thickness(0, 4, 0, 0),
            MaxWidth = 360,
            TextWrapping = TextWrapping.Wrap
        };
        stack.Children.Add(_titleTb);
        stack.Children.Add(_msgTb);
        Grid.SetColumn(stack, 1);
        grid.Children.Add(stack);

        // X-Button rechts oben schliesst nur den Toast, ohne die Klick-Aktion
        // des Fensters auszuloesen (Event wird als Handled markiert).
        var closeX = new TextBlock
        {
            Text = "\u2715",
            FontSize = 13,
            FontWeight = FontWeights.Bold,
            Foreground = new SolidColorBrush(Color.FromRgb(130, 130, 160)),
            // Transparenter Background ist notwendig, sonst erfassen die Padding-
            // Flaechen keine Mouse-Events (WPF hit-testing bei null-Background).
            Background = Brushes.Transparent,
            Cursor = Cursors.Hand,
            VerticalAlignment = VerticalAlignment.Top,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(12, -4, -4, 0),
            Padding = new Thickness(8, 4, 8, 4)
        };
        closeX.MouseEnter += delegate { closeX.Foreground = new SolidColorBrush(Color.FromRgb(232, 232, 248)); };
        closeX.MouseLeave += delegate { closeX.Foreground = new SolidColorBrush(Color.FromRgb(130, 130, 160)); };
        closeX.MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
        {
            e.Handled = true;
            HideToast();
        };
        Grid.SetColumn(closeX, 2);
        grid.Children.Add(closeX);

        card.Child = grid;
        Content = card;

        MouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e)
        {
            if (e.Handled) return;
            var h = Clicked;
            if (h != null) h();
            HideToast();
        };
    }

    public void ShowToast(string title, string message, int durationMs)
    {
        _titleTb.Text = title;
        _msgTb.Text = message;

        if (!IsVisible) Show();

        // Positionieren nach Layout-Pass, damit ActualWidth/Height korrekt sind
        Dispatcher.BeginInvoke((Action)delegate
        {
            var work = WinForms.Screen.PrimaryScreen.WorkingArea;
            double w = ActualWidth > 0 ? ActualWidth : 360;
            double h = ActualHeight > 0 ? ActualHeight : 72;
            Left = work.Right - w - 16;
            Top = work.Bottom - h - 16;
        }, DispatcherPriority.Loaded);

        if (_closeTimer == null)
        {
            _closeTimer = new DispatcherTimer();
            _closeTimer.Tick += delegate { _closeTimer.Stop(); HideToast(); };
        }
        _closeTimer.Stop();
        _closeTimer.Interval = TimeSpan.FromMilliseconds(durationMs);
        _closeTimer.Start();
    }

    public void HideToast()
    {
        if (_closeTimer != null) _closeTimer.Stop();
        if (IsVisible) Hide();
    }
}
