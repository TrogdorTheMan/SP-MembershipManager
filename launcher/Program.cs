using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;

string? pwsh = FindPwsh();

if (pwsh is null)
{
    ShowError(
        "SP-MembershipManager requires PowerShell 7 or later.\n\n" +
        "Download from: https://aka.ms/powershell");
    return 1;
}

string tempScript = Path.Combine(Path.GetTempPath(), $"sp-mm-{Guid.NewGuid():N}.ps1");
try
{
    var asm = Assembly.GetExecutingAssembly();
    using var stream = asm.GetManifestResourceStream("SP-MembershipManager.ps1")
        ?? throw new InvalidOperationException("Embedded script resource not found.");
    using var reader = new StreamReader(stream);
    File.WriteAllText(tempScript, reader.ReadToEnd(), System.Text.Encoding.UTF8);

    using var proc = Process.Start(new ProcessStartInfo
    {
        FileName = pwsh,
        Arguments = $"-NonInteractive -File \"{tempScript}\"",
        UseShellExecute = false,
        CreateNoWindow = true,
    })!;

    proc.WaitForExit();
    return proc.ExitCode;
}
catch (Exception ex)
{
    ShowError($"Failed to launch SP-MembershipManager:\n\n{ex.Message}");
    return 1;
}
finally
{
    if (File.Exists(tempScript))
        File.Delete(tempScript);
}

static string? FindPwsh()
{
    var candidates = new[]
    {
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "PowerShell", "7", "pwsh.exe"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "PowerShell", "7-preview", "pwsh.exe"),
    };

    foreach (var path in candidates)
        if (File.Exists(path)) return path;

    // Fall back to PATH
    foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
    {
        try
        {
            var full = Path.Combine(dir.Trim(), "pwsh.exe");
            if (File.Exists(full)) return full;
        }
        catch { /* skip invalid path entries */ }
    }

    return null;
}

static void ShowError(string message)
{
    MessageBoxW(IntPtr.Zero, message, "SP-MembershipManager", 0x00000010 /* MB_ICONERROR */);
}

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);
