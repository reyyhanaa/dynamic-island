# Membaca lagu/video yang sedang diputar dari Windows (Spotify, YouTube di browser, dll)
# lalu mengirimkannya sebagai JSON per baris. Juga menerima perintah dari stdin:
# "toggle", "next", "prev".
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
  $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function Await($op, [Type]$type) {
  $t = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
  $t.Wait(3000) | Out-Null
  $t.Result
}

[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.Streams.IInputStream, Windows.Storage.Streams, ContentType = WindowsRuntime] | Out-Null
$asStream = [System.IO.WindowsRuntimeStreamExtensions].GetMethod('AsStreamForRead', [type[]]@([Windows.Storage.Streams.IInputStream]))
$mgr = Await ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])

$stdin = New-Object System.IO.StreamReader([Console]::OpenStandardInput())
$cmdTask = $stdin.ReadLineAsync()
$lastKey = ''
$lastArt = ''
$lastJson = ''
$tick = 0

function Get-Art($props) {
  try {
    if (-not $props.Thumbnail) { return '' }
    $stream = Await ($props.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
    # PowerShell tidak bisa memanggil method stream WinRT langsung, jadi lewat reflection
    $net = $asStream.Invoke($null, @($stream))
    $ms = New-Object System.IO.MemoryStream
    $net.CopyTo($ms); $net.Dispose()
    if ($ms.Length -eq 0) { return '' }
    return 'data:image/png;base64,' + [Convert]::ToBase64String($ms.ToArray())
  } catch { return '' }
}

while ($true) {
  # perintah kontrol dari aplikasi
  if ($cmdTask.IsCompleted) {
    $cmd = $cmdTask.Result
    if ($null -eq $cmd) { break }   # aplikasi ditutup
    $s = $mgr.GetCurrentSession()
    if ($s) {
      $parts = $cmd.Trim().Split(' ')
      switch ($parts[0]) {
        'toggle' { Await ($s.TryTogglePlayPauseAsync()) ([bool]) | Out-Null }
        'next'   { Await ($s.TrySkipNextAsync()) ([bool]) | Out-Null }
        'prev'   { Await ($s.TrySkipPreviousAsync()) ([bool]) | Out-Null }
        # "seek 83.5" = lompat ke detik ke-83,5 (satuan Windows: 100 nanodetik)
        'seek'   { $sec = [double]::Parse($parts[1], [Globalization.CultureInfo]::InvariantCulture)
                   Await ($s.TryChangePlaybackPositionAsync([long]($sec * 10000000))) ([bool]) | Out-Null }
      }
    }
    $cmdTask = $stdin.ReadLineAsync()
    $tick = 99  # langsung kirim status terbaru
  }

  $tick++
  if ($tick -ge 4) {
    $tick = 0
    $s = $mgr.GetCurrentSession()
    if ($s) {
      $props = Await ($s.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
      $pb = $s.GetPlaybackInfo()
      $tl = $s.GetTimelineProperties()
      $key = "$($props.Title)|$($props.Artist)"
      # sampul kadang baru tersedia beberapa detik setelah lagu ganti, jadi coba lagi selama masih kosong
      $sendArt = $false
      if ($key -ne $lastKey -or (-not $lastArt -and $artTries -lt 10)) {
        if ($key -ne $lastKey) { $artTries = 0 }
        $lastKey = $key; $artTries++
        $lastArt = Get-Art $props
        $sendArt = [bool]$lastArt -or $artTries -eq 1
      }
      $obj = [ordered]@{
        type     = 'media'
        active   = $true
        title    = "$($props.Title)"
        artist   = "$($props.Artist)"
        app      = "$($s.SourceAppUserModelId)"
        playing  = ($pb.PlaybackStatus.ToString() -eq 'Playing')
        position = $tl.Position.TotalSeconds
        duration = $tl.EndTime.TotalSeconds
        updated  = $tl.LastUpdatedTime.ToUnixTimeMilliseconds()
      }
      $json = $obj | ConvertTo-Json -Compress
      if ($sendArt -or $json -ne $lastJson) {
        $lastJson = $json
        if ($sendArt) { $obj.art = $lastArt; $json = $obj | ConvertTo-Json -Compress }
        [Console]::Out.WriteLine($json); [Console]::Out.Flush()
      }
    } elseif ($lastJson -ne 'none') {
      $lastJson = 'none'; $lastKey = ''
      [Console]::Out.WriteLine('{"type":"media","active":false}'); [Console]::Out.Flush()
    }
  }
  Start-Sleep -Milliseconds 250
}
