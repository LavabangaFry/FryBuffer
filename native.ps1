#requires -Version 5.1
<#
    Системные вызовы Windows, которых нет в WPF: стекло под окном, форма
    окна, «не забирать фокус», глобальный хоткей, возврат фокуса.
#>

if (-not ('ClipNative' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class ClipNative
{
    [StructLayout(LayoutKind.Sequential)]
    private struct AccentPolicy { public int AccentState; public int AccentFlags; public int GradientColor; public int AnimationId; }

    [StructLayout(LayoutKind.Sequential)]
    private struct WinCompAttrData { public int Attribute; public IntPtr Data; public int SizeOfData; }

    [DllImport("user32.dll")] private static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WinCompAttrData data);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
    [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int cx, int cy);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr obj);

    // state: 0 выкл, 3 размытие, 4 акрил. Цвет — ABGR.
    public static bool Accent(IntPtr hwnd, int state, int abgr)
    {
        AccentPolicy policy = new AccentPolicy();
        policy.AccentState = state;
        policy.AccentFlags = 2;
        policy.GradientColor = abgr;
        int size = Marshal.SizeOf(typeof(AccentPolicy));
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(policy, ptr, false);
            WinCompAttrData data = new WinCompAttrData();
            data.Attribute = 19;
            data.Data = ptr;
            data.SizeOfData = size;
            return SetWindowCompositionAttribute(hwnd, ref data) != 0;
        }
        finally { Marshal.FreeHGlobal(ptr); }
    }

    // Видимая часть окна — скруглённый прямоугольник в физических пикселях
    public static void SetRoundRegion(IntPtr hwnd, int x, int y, int w, int h, int radius)
    {
        IntPtr rgn = CreateRoundRectRgn(x, y, x + w + 1, y + h + 1, radius * 2, radius * 2);
        if (SetWindowRgn(hwnd, rgn, true) == 0) DeleteObject(rgn);
    }

    public static void ClearRegion(IntPtr hwnd) { SetWindowRgn(hwnd, IntPtr.Zero, true); }

    // Окно не активируется по клику и не попадает в Alt+Tab
    public static void MakeNoActivate(IntPtr hwnd)
    {
        int ex = GetWindowLong(hwnd, -20);
        SetWindowLong(hwnd, -20, ex | 0x08000000 | 0x80);
    }

    public static void MakeToolWindow(IntPtr hwnd)
    {
        int ex = GetWindowLong(hwnd, -20);
        SetWindowLong(hwnd, -20, ex | 0x80);
    }
}

// Глобальный хоткей. Окно-приёмник только для сообщений, событие приходит
// в поток, создавший объект, — то есть в поток интерфейса.
public class ClipHotkey : NativeWindow, IDisposable
{
    [DllImport("user32.dll")] private static extern bool RegisterHotKey(IntPtr hWnd, int id, int mods, int vk);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public event EventHandler Pressed;
    private bool registered;

    public ClipHotkey()
    {
        CreateParams cp = new CreateParams();
        cp.Parent = new IntPtr(-3);
        CreateHandle(cp);
    }

    // 0x4000 — MOD_NOREPEAT: зажатая клавиша не шлёт повторов
    public bool Register(int mods, int vk)
    {
        Unregister();
        registered = RegisterHotKey(Handle, 1, mods | 0x4000, vk);
        return registered;
    }

    public void Unregister()
    {
        if (registered) { UnregisterHotKey(Handle, 1); registered = false; }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == 0x0312 && Pressed != null) Pressed(this, EventArgs.Empty);
        base.WndProc(ref m);
    }

    public void Dispose() { Unregister(); DestroyHandle(); }
}
'@
}
