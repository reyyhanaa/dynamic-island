# Membaca volume speaker dan status WiFi Windows, lalu mengirimkannya sebagai JSON per baris.
# Perintah dari stdin: "vol 0.42" (atur volume 0-1), "mute" (bisukan / nyalakan suara), "bright 55" (kecerahan 0-100).
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
  int _a(); int _b(); int _c(); int _d();
  int SetMasterVolumeLevelScalar(float level, Guid ctx);
  int _e();
  int GetMasterVolumeLevelScalar(out float level);
  int _f(); int _g(); int _h(); int _i();
  int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, Guid ctx);
  int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
}
[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice { int Activate(ref Guid id, int ctx, int p, out IAudioEndpointVolume v); }
[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator { int _a(); int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice dev); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }

public static class Audio {
  static IAudioEndpointVolume Ep() {
    var en = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
    IMMDevice dev; Marshal.ThrowExceptionForHR(en.GetDefaultAudioEndpoint(0, 1, out dev));
    IAudioEndpointVolume v; var id = typeof(IAudioEndpointVolume).GUID;
    Marshal.ThrowExceptionForHR(dev.Activate(ref id, 23, 0, out v));
    return v;
  }
  public static float GetVolume() { float l; Ep().GetMasterVolumeLevelScalar(out l); return l; }
  public static bool GetMute() { bool m; Ep().GetMute(out m); return m; }
  public static void SetVolume(float l) { var e = Ep(); e.SetMasterVolumeLevelScalar(l, Guid.Empty); if (l > 0) e.SetMute(false, Guid.Empty); }
  public static void ToggleMute() { var e = Ep(); bool m; e.GetMute(out m); e.SetMute(!m, Guid.Empty); }
}

public static class Win {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern short GetKeyState(int key);
  public static bool CapsLock() { return (GetKeyState(0x14) & 1) == 1; }
  public static string ClassOf(IntPtr h) { var s = new System.Text.StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
}
'@
Add-Type -AssemblyName System.Windows.Forms
[Win]::SetProcessDPIAware() | Out-Null

# aplikasi layar penuh (video, game, presentasi) = jendela depan menutupi seluruh layar
function Get-Fullscreen {
  $h = [Win]::GetForegroundWindow()
  if ($h -eq [IntPtr]::Zero) { return $false }
  if (@('Progman', 'WorkerW', 'Shell_TrayWnd') -contains [Win]::ClassOf($h)) { return $false }
  $r = New-Object Win+RECT
  [Win]::GetWindowRect($h, [ref]$r) | Out-Null
  $b = [System.Windows.Forms.Screen]::FromHandle($h).Bounds
  return ($r.L -le $b.Left -and $r.T -le $b.Top -and $r.R -ge $b.Right -and $r.B -ge $b.Bottom)
}

function Send($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress)); [Console]::Out.Flush() }

function Get-Wifi {
  $out = netsh wlan show interfaces
  $ssid = ($out | Select-String '^\s*SSID\s*:\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value
  $sig = ($out | Select-String ':\s*(\d+)%' | Select-Object -First 1).Matches.Groups[1].Value
  if ($ssid) { return @{ type = 'wifi'; connected = $true; ssid = $ssid.Trim(); signal = [int]$sig } }
  return @{ type = 'wifi'; connected = $false }
}

$stdin = New-Object System.IO.StreamReader([Console]::OpenStandardInput())
$cmdTask = $stdin.ReadLineAsync()
$lastVol = ''; $lastWifi = ''; $lastCaps = $null; $lastFull = $null; $tick = 0
$brightMethods = $null; $wantBright = $null

while ($true) {
  # baca semua perintah yang menumpuk; untuk kecerahan cukup pakai nilai terakhir (mengatur kecerahan agak lambat)
  while ($cmdTask.IsCompleted) {
    $cmd = $cmdTask.Result
    if ($null -eq $cmd) { exit }
    $parts = $cmd.Trim().Split(' ')
    try {
      if ($parts[0] -eq 'vol') { [Audio]::SetVolume([float]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture)) }
      elseif ($parts[0] -eq 'mute') { [Audio]::ToggleMute() }
      elseif ($parts[0] -eq 'bright') { $wantBright = [int]$parts[1] }
    } catch {}
    $cmdTask = $stdin.ReadLineAsync()
  }
  if ($null -ne $wantBright -and $brightMethods) {
    try { $brightMethods.WmiSetBrightness(1, [byte][math]::Max(0, [math]::Min(100, $wantBright))) | Out-Null } catch {}
    $wantBright = $null
  }

  # kecerahan layar laptop: baca sekali, lalu dengarkan event perubahan dari Windows
  if ($tick -eq 2) {
    try {
      $b = (Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightness | Select-Object -First 1).CurrentBrightness
      if ($null -ne $b) {
        $brightMethods = Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightnessMethods | Select-Object -First 1
        Register-WmiEvent -Namespace root/wmi -Class WmiMonitorBrightnessEvent -SourceIdentifier bright | Out-Null
        Send @{ type = 'brightness'; level = [int]$b; initial = $true }
      }
    } catch {}
  }
  foreach ($ev in @(Get-Event -SourceIdentifier bright -ErrorAction SilentlyContinue)) {
    Send @{ type = 'brightness'; level = [int]$ev.SourceEventArgs.NewEvent.Brightness }
    Remove-Event -EventIdentifier $ev.EventIdentifier
  }

  try {
    $v = @{ type = 'volume'; level = [math]::Round([Audio]::GetVolume(), 2); muted = [Audio]::GetMute() }
    $j = $v | ConvertTo-Json -Compress
    if ($j -ne $lastVol) { $lastVol = $j; Send $v }
  } catch {}

  $caps = [Win]::CapsLock()
  if ($caps -ne $lastCaps) { $lastCaps = $caps; Send @{ type = 'caps'; on = $caps } }

  if ($tick % 2 -eq 0) {
    $full = Get-Fullscreen
    if ($full -ne $lastFull) { $lastFull = $full; Send @{ type = 'fullscreen'; on = $full } }
  }

  if ($tick % 12 -eq 0) {
    $w = Get-Wifi
    $j = $w | ConvertTo-Json -Compress
    if ($j -ne $lastWifi) { $lastWifi = $j; Send $w }
  }
  $tick++
  Start-Sleep -Milliseconds 250
}
