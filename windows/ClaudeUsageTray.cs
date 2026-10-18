// ClaudeUsageTray - MIGATRONIX (Windows)
// Tray icon with Claude plan usage, read from %USERPROFILE%\.claude\usage-cache.json
// (written by statusline-usage.ps1 whenever Claude Code refreshes its status line).
// Shown only while Claude runs (desktop app or Claude Code, both claude.exe).
// Built by session-start.ps1 into a GUI executable: no console window, so closing a
// terminal or Claude Code never takes the tray icon down with it.
// C# 5 only: Windows PowerShell's Add-Type compiler does not accept newer syntax.

using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace Migatronix
{
    public class UsageWindow
    {
        public double UsedPct;
        public long ResetsAt;
    }

    public class UsageSnapshot
    {
        public UsageWindow FiveHour;
        public UsageWindow SevenDay;
        public double? ContextPct;
        public long UpdatedAt;
    }

    public static class Cache
    {
        static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

        // The cache file is small, flat JSON written by our own status-line script.
        public static UsageSnapshot Read(string path)
        {
            if (!File.Exists(path)) return null;
            string json;
            try { json = File.ReadAllText(path); } catch (IOException) { return null; }

            var snap = new UsageSnapshot();
            long updated;
            if (!TryLong(Field(json, "updated_at"), out updated)) return null;
            snap.UpdatedAt = updated;
            snap.FiveHour = Window(ObjectText(json, "five_hour"));
            snap.SevenDay = Window(ObjectText(json, "seven_day"));
            double ctx;
            if (TryDouble(Field(json, "context_pct"), out ctx)) snap.ContextPct = ctx;
            return snap;
        }

        static UsageWindow Window(string obj)
        {
            if (obj == null) return null;
            double pct; long resets;
            if (!TryDouble(Field(obj, "used_percentage"), out pct)) return null;
            if (!TryLong(Field(obj, "resets_at"), out resets)) return null;
            var w = new UsageWindow();
            w.UsedPct = pct;
            w.ResetsAt = resets;
            return w;
        }

        static string ObjectText(string json, string key)
        {
            var m = Regex.Match(json, "\"" + key + "\"\\s*:\\s*\\{([^{}]*)\\}");
            return m.Success ? m.Groups[1].Value : null;
        }

        static string Field(string json, string key)
        {
            var m = Regex.Match(json, "\"" + key + "\"\\s*:\\s*(-?[0-9.eE+]+)");
            return m.Success ? m.Groups[1].Value : null;
        }

        static bool TryDouble(string s, out double v)
        {
            v = 0;
            return s != null && double.TryParse(s, NumberStyles.Float, Inv, out v);
        }

        static bool TryLong(string s, out long v)
        {
            v = 0;
            double d;
            if (!TryDouble(s, out d)) return false;
            v = (long)d;
            return true;
        }
    }

    public static class Fmt
    {
        public static long Now()
        {
            return (long)(DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
        }

        public static string Left(long seconds)
        {
            long s = Math.Max(0, seconds);
            long d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60;
            if (d > 0) return string.Format("{0}d {1}h", d, h);
            if (h > 0) return string.Format("{0}h {1:00}m", h, m);
            return string.Format("{0}m", m);
        }

        public static string Clock(long epoch, bool withDay)
        {
            var t = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(epoch).ToLocalTime();
            return t.ToString(withDay ? "ddd HH:mm" : "HH:mm", CultureInfo.InvariantCulture);
        }

        public static string Ago(long seconds)
        {
            long m = seconds / 60;
            if (m < 1) return "just now";
            if (m < 60) return m + " min ago";
            return string.Format("{0}h {1}m ago", m / 60, m % 60);
        }
    }

    public class TrayApp : ApplicationContext
    {
        [DllImport("user32.dll")]
        static extern bool DestroyIcon(IntPtr handle);

        static readonly Color Magenta = Color.FromArgb(0xB7, 0x00, 0x6A);
        static readonly Color Amber = Color.FromArgb(0xE0, 0x9A, 0x00);
        static readonly Color Blue = Color.FromArgb(0x00, 0x5F, 0xCC);
        static readonly Color Grey = Color.FromArgb(0x88, 0x88, 0x88);
        const long StaleAfter = 15 * 60;

        readonly string cachePath;
        readonly string alwaysShowFlag;
        readonly NotifyIcon tray = new NotifyIcon();
        readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        readonly Form popup = new Form();
        Label head5, body5, headW, bodyW, ctxLabel, updatedLabel;
        IntPtr iconHandle = IntPtr.Zero;
        UsageSnapshot snap;

        public TrayApp(string claudeDir)
        {
            cachePath = Path.Combine(claudeDir, "usage-cache.json");
            alwaysShowFlag = Path.Combine(Path.Combine(claudeDir, "usage-meter"), "always-show");

            BuildPopup();

            var menu = new ContextMenuStrip();
            menu.Items.Add("Show", null, delegate { ShowPopup(); });
            menu.Items.Add("Reload", null, delegate { Refresh(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Quit", null, delegate { Quit(); });
            tray.ContextMenuStrip = menu;
            tray.MouseClick += delegate(object s, MouseEventArgs e)
            {
                if (e.Button != MouseButtons.Left) return;
                if (popup.Visible) popup.Hide(); else ShowPopup();
            };

            // One 2-second tick does both jobs: show/hide with Claude, and re-read the cache.
            timer.Interval = 2000;
            timer.Tick += delegate { Tick(); };
            Tick();
            timer.Start();
        }

        static bool ClaudeRunning()
        {
            var procs = Process.GetProcessesByName("claude");
            bool any = procs.Length > 0;
            foreach (var p in procs) p.Dispose();
            return any;
        }

        void Tick()
        {
            bool show = File.Exists(alwaysShowFlag) || ClaudeRunning();
            if (show)
            {
                Refresh();
                if (!tray.Visible) tray.Visible = true;
            }
            else if (tray.Visible)
            {
                popup.Hide();
                tray.Visible = false;
            }
        }

        static Color LevelColor(double pct)
        {
            if (pct >= 90) return Magenta;
            if (pct >= 70) return Amber;
            return Blue;
        }

        void Refresh()
        {
            snap = Cache.Read(cachePath);
            long now = Fmt.Now();
            UsageWindow five = snap == null ? null : snap.FiveHour;

            if (five != null && five.ResetsAt > now)
            {
                SetIcon(five.UsedPct, LevelColor(five.UsedPct), true);
                string tip = string.Format("Claude 5h: {0}% \u00B7 reset in {1}",
                    (int)Math.Round(five.UsedPct), Fmt.Left(five.ResetsAt - now));
                tray.Text = tip.Length > 63 ? tip.Substring(0, 63) : tip;
            }
            else
            {
                SetIcon(0, Grey, false);
                tray.Text = snap == null ? "Claude usage: no data yet" : "Claude usage: waiting for new data";
            }

            if (popup.Visible) FillPopup(now);
        }

        void SetIcon(double pct, Color color, bool active)
        {
            using (var bmp = new Bitmap(32, 32))
            {
                using (var g = Graphics.FromImage(bmp))
                using (var track = new Pen(Color.FromArgb(110, 128, 128, 128), 6))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.DrawEllipse(track, 4, 4, 24, 24);
                    if (active)
                    {
                        using (var pen = new Pen(color, 6))
                        {
                            float sweep = (float)(360 * Math.Min(1.0, Math.Max(0.02, pct / 100)));
                            g.DrawArc(pen, 4, 4, 24, 24, -90, sweep);
                        }
                    }
                }
                IntPtr handle = bmp.GetHicon();
                tray.Icon = Icon.FromHandle(handle);
                if (iconHandle != IntPtr.Zero) DestroyIcon(iconHandle);
                iconHandle = handle;
            }
        }

        Label AddLabel(int x, int y, int w, int h, float size, bool bold)
        {
            var l = new Label();
            l.Location = new Point(x, y);
            l.Size = new Size(w, h);
            l.Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular);
            popup.Controls.Add(l);
            return l;
        }

        void BuildPopup()
        {
            popup.FormBorderStyle = FormBorderStyle.FixedToolWindow;
            popup.ShowInTaskbar = false;
            popup.TopMost = true;
            popup.StartPosition = FormStartPosition.Manual;
            popup.Text = "Claude usage";
            popup.ClientSize = new Size(300, 236);
            popup.BackColor = Color.White;

            AddLabel(14, 10, 270, 28, 12, true).Text = "Claude usage";
            head5 = AddLabel(14, 44, 270, 24, 10, true);
            body5 = AddLabel(14, 68, 270, 36, 9, false);
            headW = AddLabel(14, 108, 270, 24, 10, true);
            bodyW = AddLabel(14, 132, 270, 36, 9, false);
            ctxLabel = AddLabel(14, 172, 270, 20, 8.5f, false);
            updatedLabel = AddLabel(14, 192, 270, 20, 8.5f, false);
            var brand = AddLabel(14, 212, 140, 18, 7.5f, true);
            brand.Text = "MIGATRONIX";
            brand.ForeColor = Magenta;
            ctxLabel.ForeColor = Grey;

            popup.Deactivate += delegate { popup.Hide(); };
            popup.FormClosing += delegate(object s, FormClosingEventArgs e)
            {
                if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; popup.Hide(); }
            };
        }

        void FillWindow(Label head, Label body, string title, UsageWindow w, bool withDay, long now)
        {
            if (w == null)
            {
                head.Text = title + "  -";
                head.ForeColor = Grey;
                body.Text = "no data";
                return;
            }
            if (w.ResetsAt <= now)
            {
                head.Text = title + "  reset";
                head.ForeColor = Grey;
                body.Text = "reset at " + Fmt.Clock(w.ResetsAt, withDay) + "\r\nawaiting new data";
                return;
            }
            int p = (int)Math.Round(w.UsedPct);
            head.Text = string.Format("{0}  {1}% used  \u00B7  {2}% left", title, p, 100 - p);
            head.ForeColor = LevelColor(w.UsedPct);
            body.Text = "resets in " + Fmt.Left(w.ResetsAt - now) + "\r\nat " + Fmt.Clock(w.ResetsAt, withDay);
        }

        void FillPopup(long now)
        {
            FillWindow(head5, body5, "5-hour", snap == null ? null : snap.FiveHour, false, now);
            FillWindow(headW, bodyW, "Weekly", snap == null ? null : snap.SevenDay, true, now);
            ctxLabel.Text = snap != null && snap.ContextPct.HasValue
                ? "Last session context: " + (int)Math.Round(snap.ContextPct.Value) + "%"
                : "";
            if (snap == null)
            {
                updatedLabel.Text = "No data yet - run claude and send one message";
                updatedLabel.ForeColor = Grey;
                return;
            }
            long age = now - snap.UpdatedAt;
            updatedLabel.Text = "Updated " + Fmt.Ago(age) + (age > StaleAfter ? " - open Claude Code to refresh" : "");
            updatedLabel.ForeColor = age > StaleAfter ? Amber : Grey;
        }

        void ShowPopup()
        {
            Refresh();
            FillPopup(Fmt.Now());
            var area = Screen.PrimaryScreen.WorkingArea;
            popup.Location = new Point(area.Right - popup.Width - 12, area.Bottom - popup.Height - 12);
            popup.Show();
            popup.Activate();
        }

        void Quit()
        {
            timer.Stop();
            tray.Visible = false;
            ExitThread();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                timer.Dispose();
                tray.Dispose();
                popup.Dispose();
                if (iconHandle != IntPtr.Zero) { DestroyIcon(iconHandle); iconHandle = IntPtr.Zero; }
            }
            base.Dispose(disposing);
        }
    }

    public static class Program
    {
        static string logPath;

        static void Log(string msg)
        {
            try
            {
                File.AppendAllText(logPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture)
                    + " " + msg + Environment.NewLine);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }

        [STAThread]
        public static void Main()
        {
            string claudeDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");
            string meterDir = Path.Combine(claudeDir, "usage-meter");
            Directory.CreateDirectory(meterDir);
            logPath = Path.Combine(meterDir, "tray.log");

            bool created;
            using (var mutex = new Mutex(true, "Local\\MigatronixClaudeUsageTray", out created))
            {
                if (!created) return;

                // Never let one bad tick take the tray down: log it and keep running.
                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
                Application.ThreadException += delegate(object s, ThreadExceptionEventArgs e)
                {
                    Log("error: " + e.Exception);
                };
                AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs e)
                {
                    Log("fatal: " + e.ExceptionObject);
                };

                Log("tray started (pid " + Process.GetCurrentProcess().Id + ")");
                Application.EnableVisualStyles();
                Application.Run(new TrayApp(claudeDir));
                Log("tray exited");
            }
        }
    }
}
