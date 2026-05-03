// Read this file first when changing release/about information in the GUI.
// Purpose: build the About page with version, build, author, and project metadata.
// Scope: release metadata values live in AppInfo.cs and build-gui.ps1.

using System.Windows;
using System.Windows.Controls;

partial class MainPanel
{
    FrameworkElement BuildAboutPage()
    {
        var scroll = MakeScroll();
        var stack = new StackPanel { Margin = new Thickness(32, 28, 32, 28) };

        stack.Children.Add(T(Loc.T("about.title"), 22, TXT, true));
        stack.Children.Add(Sp(4));
        var sub = T(Loc.T("about.subtitle"), 13, TXT2);
        sub.TextWrapping = TextWrapping.Wrap;
        stack.Children.Add(sub);
        stack.Children.Add(Sp(24));

        var card = Card();
        var inner = new StackPanel { Margin = new Thickness(22, 20, 22, 20) };
        inner.Children.Add(T(AppInfo.ProductName, 18, TXT, true));
        inner.Children.Add(Sp(14));
        AddAboutLine(inner, Loc.F("about.core", AppInfo.CoreName));
        AddAboutLine(inner, Loc.F("about.version", AppInfo.Version));
        AddAboutLine(inner, Loc.F("about.build", AppInfo.BuildId));
        AddAboutLine(inner, Loc.F("about.commit", AppInfo.BuildCommit));
        AddAboutLine(inner, Loc.F("about.built", AppInfo.BuildTimeUtc));
        inner.Children.Add(Sp(10));
        AddAboutLine(inner, Loc.F("about.author", AppInfo.Author));
        AddAboutLine(inner, Loc.F("about.project", AppInfo.ProjectUrl));
        card.Child = inner;
        stack.Children.Add(card);

        scroll.Content = stack;
        return scroll;
    }

    void AddAboutLine(Panel parent, string text)
    {
        var line = T(text, 13, TXT2);
        line.TextWrapping = TextWrapping.Wrap;
        line.Margin = new Thickness(0, 0, 0, 8);
        parent.Children.Add(line);
    }

    void RefreshAbout()
    {
    }
}
