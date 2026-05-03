// Read this file first when changing the GUI shell chrome.
// Purpose: titlebar, sidebar, page switching, and small UI factory helpers.
// Scope: page-specific controls live in MainPanel.Dashboard/Folders/Settings/Log.

using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;

partial class MainPanel
{
    Grid _titleBarCache;

    UIElement BuildShell()
    {
        var root = new Grid();
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(42) });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var outer = new Border
        {
            Background = B(C_BG), BorderBrush = B(20, 255, 255, 255),
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12),
            ClipToBounds = true, Child = root,
        };

        var titleBar = BuildTitleBar();
        Grid.SetRow(titleBar, 0);
        root.Children.Add(titleBar);

        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        Grid.SetRow(body, 1);
        root.Children.Add(body);

        var sidebar = BuildSidebar();
        Grid.SetColumn(sidebar, 0);
        body.Children.Add(sidebar);

        var sep = new Border { Width = 1, Background = B(C_BRD), HorizontalAlignment = HorizontalAlignment.Left };
        Grid.SetColumn(sep, 1);
        body.Children.Add(sep);

        _pageContainer = new Border { Margin = new Thickness(0) };
        Grid.SetColumn(_pageContainer, 1);
        body.Children.Add(_pageContainer);

        _pages = new FrameworkElement[] {
            BuildDashboardPage(),
            BuildFoldersPage(),
            BuildSettingsPage(),
            BuildLogPage(),
            BuildAboutPage(),
        };

        return outer;
    }

    Grid BuildTitleBar()
    {
        if (_titleBarCache != null) return _titleBarCache;
        var g = new Grid { Background = B(C_SIDE) };
        var drag = new Border { Background = TRANS };
        drag.MouseLeftButtonDown += delegate { try { DragMove(); } catch {} };
        g.Children.Add(drag);

        var left = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(16, 0, 0, 0), IsHitTestVisible = false };
        left.Children.Add(T("\U0001F6E1", 13, GREEN));
        left.Children.Add(T("  " + AppInfo.ProductName, 13, TXT, true));
        g.Children.Add(left);

        var btns = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 0, 4, 0) };
        btns.Children.Add(WinBtn("\u2500", delegate { WindowState = WindowState.Minimized; }));
        btns.Children.Add(WinBtn("\u2715", delegate { Hide(); }));
        g.Children.Add(btns);

        _titleBarCache = g;
        return g;
    }

    Border WinBtn(string icon, Action click)
    {
        var b = new Border { Width = 34, Height = 34, CornerRadius = new CornerRadius(6), Background = TRANS, Cursor = Cursors.Hand };
        var t = T(icon, 12, TXT3); t.HorizontalAlignment = HorizontalAlignment.Center; t.VerticalAlignment = VerticalAlignment.Center;
        b.Child = t;
        b.PreviewMouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e) { e.Handled = true; click(); };
        b.MouseEnter += delegate { b.Background = B(25, 255, 255, 255); ((TextBlock)b.Child).Foreground = TXT; };
        b.MouseLeave += delegate { b.Background = TRANS; ((TextBlock)b.Child).Foreground = TXT3; };
        return b;
    }

    UIElement BuildSidebar()
    {
        var panel = new Border { Background = B(C_SIDE) };
        var stack = new StackPanel { Margin = new Thickness(10, 16, 10, 16) };

        string[] labels = {
            Loc.T("nav.dashboard"),
            Loc.T("nav.folders"),
            Loc.T("nav.settings"),
            Loc.T("nav.log"),
            Loc.T("nav.about")
        };
        string[] icons = { "\U0001F6E1", "\U0001F4C2", "\u2699", "\U0001F4CB", "\u24D8" };

        _navItems = new Border[labels.Length];
        _navLabels = new TextBlock[labels.Length];

        for (int i = 0; i < labels.Length; i++)
        {
            int idx = i;
            var item = new Border
            {
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(12, 10, 12, 10),
                Margin = new Thickness(0, 2, 0, 2),
                Cursor = Cursors.Hand,
                Background = TRANS,
            };

            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(T(icons[i], 14, TXT3));
            var lbl = T("  " + labels[i], 13, TXT2);
            row.Children.Add(lbl);
            item.Child = row;

            item.PreviewMouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e) { e.Handled = true; ShowPage(idx); };
            item.MouseEnter += delegate { if (_activePage != idx) item.Background = B(15, 255, 255, 255); };
            item.MouseLeave += delegate { if (_activePage != idx) item.Background = TRANS; };

            _navItems[i] = item;
            _navLabels[i] = lbl;
            stack.Children.Add(item);
        }

        stack.Children.Add(new Border { Height = 1, Background = B(C_BRD), Margin = new Thickness(4, 16, 4, 16) });

        var installBtn = SidebarBtn(Loc.T("sidebar.install"), C_GREEN, delegate { if (!_cfg.IsInstalled) DoInstall(); });
        _installActionBtn = installBtn;
        _installActionText = (TextBlock)installBtn.Child;
        var updateBtn = SidebarBtn(Loc.T("sidebar.update"), C_BLUE, delegate { DoUpdate(); });
        var uninstallBtn = SidebarBtn(Loc.T("sidebar.uninstall"), C_RED, delegate { DoUninstall(); });
        stack.Children.Add(installBtn);
        stack.Children.Add(updateBtn);
        stack.Children.Add(uninstallBtn);

        panel.Child = stack;
        return panel;
    }

    void RefreshSidebarActions()
    {
        if (_installActionBtn == null || _installActionText == null) return;
        if (_cfg.IsInstalled)
        {
            _installActionText.Text = Loc.T("sidebar.installed");
            _installActionText.Foreground = GREEN;
            _installActionBtn.Cursor = Cursors.Arrow;
        }
        else
        {
            _installActionText.Text = Loc.T("sidebar.install");
            _installActionText.Foreground = B(C_GREEN);
            _installActionBtn.Cursor = Cursors.Hand;
        }
    }

    Border SidebarBtn(string text, Color c, Action click)
    {
        var b = new Border
        {
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(12, 8, 12, 8),
            Margin = new Thickness(0, 2, 0, 2),
            Cursor = Cursors.Hand,
            Background = TRANS,
        };
        b.Child = T(text, 12, B(c));
        b.PreviewMouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e) { e.Handled = true; click(); };
        b.MouseEnter += delegate { b.Background = B(15, c.R, c.G, c.B); };
        b.MouseLeave += delegate { b.Background = TRANS; };
        return b;
    }

    void ShowPage(int idx)
    {
        _activePage = idx;
        _pageContainer.Child = _pages[idx];

        for (int i = 0; i < _navItems.Length; i++)
        {
            if (i == idx)
            {
                _navItems[i].Background = B(20, C_GREEN.R, C_GREEN.G, C_GREEN.B);
                var row = (StackPanel)_navItems[i].Child;
                ((TextBlock)row.Children[0]).Foreground = GREEN;
                _navLabels[i].Foreground = TXT;
                _navLabels[i].FontWeight = FontWeights.SemiBold;
            }
            else
            {
                _navItems[i].Background = TRANS;
                var row = (StackPanel)_navItems[i].Child;
                ((TextBlock)row.Children[0]).Foreground = TXT3;
                _navLabels[i].Foreground = TXT2;
                _navLabels[i].FontWeight = FontWeights.Normal;
            }
        }

        switch (idx)
        {
            case 0: RefreshDashboard(); break;
            case 1: RefreshDirs(); break;
            case 2: RefreshSettings(); break;
            case 3: RefreshLog(); break;
            case 4: RefreshAbout(); break;
        }
    }

    TextBlock T(string text, double size, SolidColorBrush fg, bool bold = false)
    {
        return new TextBlock { Text = text, FontSize = size, Foreground = fg,
            FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
            VerticalAlignment = VerticalAlignment.Center };
    }

    Border Card()
    {
        return new Border { Background = B(C_SURF), CornerRadius = new CornerRadius(10),
            BorderBrush = B(C_BRD), BorderThickness = new Thickness(1) };
    }

    Border Pill(string text, Color c, Action click)
    {
        var b = new Border { Background = B(18, c.R, c.G, c.B), CornerRadius = new CornerRadius(16),
            Padding = new Thickness(14, 7, 14, 7), Cursor = Cursors.Hand };
        b.Child = T(text, 12, B(c), true);
        b.PreviewMouseLeftButtonDown += delegate(object s, MouseButtonEventArgs e) { e.Handled = true; click(); };
        b.MouseEnter += delegate { b.Opacity = 0.8; };
        b.MouseLeave += delegate { b.Opacity = 1.0; };
        return b;
    }

    ScrollViewer MakeScroll()
    {
        var sv = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Background = TRANS,
        };
        sv.Resources.Add(typeof(ScrollBar), DarkScrollBarStyle());
        return sv;
    }

    Style DarkScrollBarStyle()
    {
        var style = new Style(typeof(ScrollBar));
        style.Setters.Add(new Setter(ScrollBar.WidthProperty, 8.0));
        style.Setters.Add(new Setter(ScrollBar.MinWidthProperty, 8.0));
        style.Setters.Add(new Setter(ScrollBar.BackgroundProperty, TRANS));
        style.Setters.Add(new Setter(ScrollBar.TemplateProperty, DarkScrollBarTemplate()));

        var horizontal = new Trigger { Property = ScrollBar.OrientationProperty, Value = Orientation.Horizontal };
        horizontal.Setters.Add(new Setter(ScrollBar.HeightProperty, 8.0));
        horizontal.Setters.Add(new Setter(ScrollBar.MinHeightProperty, 8.0));
        horizontal.Setters.Add(new Setter(ScrollBar.WidthProperty, double.NaN));
        horizontal.Setters.Add(new Setter(ScrollBar.MinWidthProperty, 0.0));
        style.Triggers.Add(horizontal);

        return style;
    }

    ControlTemplate DarkScrollBarTemplate()
    {
        // Track subparts are property elements in .NET 4 WPF, so keep the
        // complete template in XAML instead of a partial code-built style.
        const string xaml = @"
<ControlTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
                 xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
                 TargetType='{x:Type ScrollBar}'>
    <Grid Background='Transparent' SnapsToDevicePixels='True'>
        <Track x:Name='PART_Track' IsDirectionReversed='True'>
            <Track.DecreaseRepeatButton>
                <RepeatButton Focusable='False'
                              Opacity='0'
                              Command='{x:Static ScrollBar.PageUpCommand}'
                              CommandTarget='{Binding RelativeSource={RelativeSource TemplatedParent}}'>
                    <RepeatButton.Template>
                        <ControlTemplate TargetType='{x:Type RepeatButton}'>
                            <Border Background='Transparent' />
                        </ControlTemplate>
                    </RepeatButton.Template>
                </RepeatButton>
            </Track.DecreaseRepeatButton>
            <Track.Thumb>
                <Thumb x:Name='Thumb' Background='#46FFFFFF'>
                    <Thumb.Template>
                        <ControlTemplate TargetType='{x:Type Thumb}'>
                            <Border x:Name='ThumbChrome'
                                    Margin='1'
                                    CornerRadius='4'
                                    Background='{TemplateBinding Background}' />
                        </ControlTemplate>
                    </Thumb.Template>
                </Thumb>
            </Track.Thumb>
            <Track.IncreaseRepeatButton>
                <RepeatButton Focusable='False'
                              Opacity='0'
                              Command='{x:Static ScrollBar.PageDownCommand}'
                              CommandTarget='{Binding RelativeSource={RelativeSource TemplatedParent}}'>
                    <RepeatButton.Template>
                        <ControlTemplate TargetType='{x:Type RepeatButton}'>
                            <Border Background='Transparent' />
                        </ControlTemplate>
                    </RepeatButton.Template>
                </RepeatButton>
            </Track.IncreaseRepeatButton>
        </Track>
    </Grid>
    <ControlTemplate.Triggers>
        <Trigger SourceName='Thumb' Property='IsMouseOver' Value='True'>
            <Setter TargetName='Thumb' Property='Background' Value='#73FFFFFF' />
        </Trigger>
        <Trigger SourceName='Thumb' Property='IsDragging' Value='True'>
            <Setter TargetName='Thumb' Property='Background' Value='#96FFFFFF' />
        </Trigger>
        <Trigger Property='Orientation' Value='Horizontal'>
            <Setter TargetName='PART_Track' Property='IsDirectionReversed' Value='False' />
        </Trigger>
    </ControlTemplate.Triggers>
</ControlTemplate>";
        return (ControlTemplate)XamlReader.Parse(xaml);
    }

    UIElement Sp(double h) { return new Border { Height = h }; }
}
