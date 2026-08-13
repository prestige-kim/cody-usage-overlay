using System.Threading;
using System.Windows;

namespace CodyUsageOverlay.App;

public partial class App : Application
{
    private Mutex? mutex;
    protected override void OnStartup(StartupEventArgs e)
    {
        mutex = new Mutex(true, @"Local\CodyUsageOverlay.Windows", out var created);
        if (!created) { Shutdown(); return; }
        var window = new MainWindow();
        MainWindow = window;
        window.Show();
    }

    protected override void OnExit(ExitEventArgs e) { mutex?.ReleaseMutex(); mutex?.Dispose(); base.OnExit(e); }
}
