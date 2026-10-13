// FryBuffer.exe — вся программа одним файлом.
//
// Внутри как ресурсы лежат скрипты панели, образец конфига и набор эмодзи.
// Скрипты выполняются из памяти PowerShell'ом в этом же процессе: отдельного
// powershell.exe нет, и на диск не распаковывается ничего исполняемого —
// распаковка с последующим запуском .ps1 первой настораживает антивирусы.
// На диск, в %LOCALAPPDATA%\FryBuffer, ложатся только картинки эмодзи:
// держать 1300 штук в памяти незачем.
//
// Сборка: tools\build-exe.ps1 (компилятор csc есть в любой Windows с .NET 4).
// Версия сборки (AssemblyVersion, FileVersion, InformationalVersion)
// генерируется этим скриптом отдельным файлом — она видна в свойствах exe.
//
//   FryBuffer.exe            — запустить панель (второй экземпляр выйдет сам)
//   FryBuffer.exe --restart  — дождаться выхода прежнего экземпляра и запустить

using System;
using System.Collections;
using System.IO;
using System.IO.Compression;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("FryBuffer")]
[assembly: AssemblyProduct("FryBuffer")]
[assembly: AssemblyDescription("Эмодзи-кнопки у края экрана: клик кладёт текст в буфер обмена")]

static class Launcher
{
    static readonly string[] Parts = { "core.ps1", "native.ps1", "ui.ps1", "settings.ps1", "dock.ps1" };

    [STAThread]
    static int Main(string[] args)
    {
        string exe = Assembly.GetExecutingAssembly().Location;
        string dir = Path.GetDirectoryName(exe);
        try
        {
            if (Array.IndexOf(args, "--restart") >= 0) WaitForPreviousExit();

            var parts = new Hashtable(StringComparer.OrdinalIgnoreCase);
            foreach (string p in Parts) parts[p] = ReadText(p);

            string emojiDir = PrepareEmoji();
            var host = new Hashtable(StringComparer.OrdinalIgnoreCase);
            host["Root"] = dir;
            host["Exe"] = exe;
            host["Parts"] = parts;
            host["EmojiDir"] = emojiDir;
            host["Example"] = Path.Combine(emojiDir, "config.example.json");
            // Версию вшивает сборка: дата и номер коммита, видны в трее и настройках
            host["Version"] = ReadText("version.txt").Trim();

            // Окна WPF живут только в STA-потоке, поэтому PowerShell работает
            // прямо в главном потоке процесса, а не в своём
            var iss = InitialSessionState.CreateDefault();
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.ApartmentState = ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                rs.SessionStateProxy.SetVariable("ClipHost", host);
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddScript(ReadText("FryBuffer.ps1"));
                    ps.Invoke();
                    if (ps.HadErrors && ps.Streams.Error.Count > 0)
                    {
                        // Ошибки, которые скрипт не поймал сам: в лог и человеку
                        var sb = new StringBuilder();
                        foreach (ErrorRecord e in ps.Streams.Error)
                        {
                            sb.AppendLine(e.ToString());
                            if (e.InvocationInfo != null) sb.AppendLine(e.InvocationInfo.PositionMessage);
                        }
                        Fail(dir, sb.ToString());
                        return 1;
                    }
                }
            }
            return 0;
        }
        catch (Exception e)
        {
            Fail(dir, e.ToString());
            return 1;
        }
    }

    static Stream Res(string name)
    {
        Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
        if (s == null) throw new InvalidOperationException("В FryBuffer.exe нет ресурса «" + name + "» — exe собран не полностью, пересоберите tools\\build-exe.ps1");
        return s;
    }

    static string ReadText(string name)
    {
        using (var r = new StreamReader(Res(name), Encoding.UTF8)) return r.ReadToEnd();
    }

    // Картинки распаковываются один раз на версию набора: имя папки — хеш
    // архива, поэтому новая сборка с другим набором не возьмёт старые файлы
    static string PrepareEmoji()
    {
        string baseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FryBuffer");
        string hash;
        using (Stream z = Res("emoji.zip"))
        using (var sha = SHA1.Create())
            hash = BitConverter.ToString(sha.ComputeHash(z)).Replace("-", "").Substring(0, 10).ToLowerInvariant();
        string target = Path.Combine(baseDir, "emoji-" + hash);
        if (File.Exists(Path.Combine(target, ".ok"))) return target;

        string tmp = target + ".tmp-" + System.Diagnostics.Process.GetCurrentProcess().Id;
        if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
        Directory.CreateDirectory(tmp);
        using (Stream z = Res("emoji.zip"))
        using (var zip = new ZipArchive(z, ZipArchiveMode.Read))
            zip.ExtractToDirectory(tmp);
        using (Stream src = Res("config.example.json"))
        using (Stream dst = File.Create(Path.Combine(tmp, "config.example.json")))
            src.CopyTo(dst);
        File.WriteAllText(Path.Combine(tmp, ".ok"), hash);
        try
        {
            if (Directory.Exists(target)) Directory.Delete(target, true);
            Directory.Move(tmp, target);
        }
        catch
        {
            // Параллельный запуск успел распаковать раньше — берём его копию
            if (!File.Exists(Path.Combine(target, ".ok"))) throw;
            try { Directory.Delete(tmp, true); } catch { }
        }
        // Кеш эмодзи программы под прежним именем clipbuttons больше не нужен
        string legacy = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "clipbuttons");
        if (Directory.Exists(legacy)) try { Directory.Delete(legacy, true); } catch { }
        // Наборы прежних версий больше не нужны
        foreach (string old in Directory.GetDirectories(baseDir, "emoji-*"))
            if (!string.Equals(old, target, StringComparison.OrdinalIgnoreCase))
                try { Directory.Delete(old, true); } catch { }
        return target;
    }

    // Пока прежний экземпляр держит мьютекс, новый сразу выйдет как второй —
    // поэтому ждём, когда мьютекс исчезнет, но не дольше 15 секунд
    static void WaitForPreviousExit()
    {
        for (int i = 0; i < 150; i++)
        {
            Mutex m;
            if (!Mutex.TryOpenExisting(@"Local\FryBuffer", out m)) return;
            m.Dispose();
            Thread.Sleep(100);
        }
    }

    static void Fail(string dir, string text)
    {
        string log = Path.Combine(dir, "FryBuffer-error.log");
        try { File.AppendAllText(log, DateTime.Now.ToString("s") + " [exe] " + text + Environment.NewLine, Encoding.UTF8); }
        catch
        {
            log = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "FryBuffer", "FryBuffer-error.log");
            try { Directory.CreateDirectory(Path.GetDirectoryName(log)); File.AppendAllText(log, DateTime.Now.ToString("s") + " [exe] " + text + Environment.NewLine, Encoding.UTF8); } catch { }
        }
        MessageBox.Show("FryBuffer не запустился:\n\n" + (text.Length > 1500 ? text.Substring(0, 1500) + "…" : text) +
            "\n\nПодробности: " + log, "FryBuffer", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}
