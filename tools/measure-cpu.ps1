# Measures CPU% of the Wear OS watch face runtime while a face is shown (screen kept on).
param([string]$Serial = "emulator-5554", [string]$Package, [int]$Samples = 6)
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb -s $Serial shell am broadcast -a com.google.android.wearable.app.DEBUG_SURFACE --es operation set-watchface --es watchFaceId $Package | Out-Null
& $adb -s $Serial shell settings put system screen_off_timeout 600000
& $adb -s $Serial shell input keyevent KEYCODE_WAKEUP
Start-Sleep 8
$rt = (& $adb -s $Serial shell pidof com.google.wear.watchface.runtime).Trim()
$vals = @()
for ($i = 0; $i -lt $Samples; $i++) {
  $line = & $adb -s $Serial shell top -b -n 1 -d 1 -p $rt | Select-String $rt | Select-Object -Last 1
  $cols = ($line.Line -split '\s+') | Where-Object { $_ }
  $vals += [double]$cols[8]
  Start-Sleep 1
}
& $adb -s $Serial shell settings put system screen_off_timeout 15000
$avg = ($vals | Measure-Object -Average).Average
"{0}: CPU% samples = {1}  avg = {2:N1}" -f $Package, ($vals -join ', '), $avg
