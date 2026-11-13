# EVIL v3 - static military/tactical data face (light grey + bright red, stencil digits). Generates:
#   res/drawable/bg.png        (charcoal, faint grid, bezel ticks)
#   res/raw/watchface.xml      (Watch Face Format v2, no animations, no glow)
#   res/drawable/preview.png   (local mock with sample data, same metrics)
# Text is positioned by CAP TOP (top edge of the digits) so the layout math matches the round screen.
param([string]$MockOut)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$S = 466; $C = 233

# ---------------------------------------------------------------- fonts + metrics
$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$fontInfo = @{ saira_stencil = @{ file = "saira_stencil.ttf"; name = "Saira Stencil One" }; mono_bold = @{ file = "mono_bold.ttf"; name = "JetBrains Mono" } }
foreach ($k in $fontInfo.Keys) { $pfc.AddFontFile("$root\res\font\$($fontInfo[$k].file)") }
function Fam($font) { $n = $fontInfo[$font].name; $pfc.Families | Where-Object { $_.Name -eq $n } | Select-Object -First 1 }
$metrics = @{}
foreach ($f in $fontInfo.Keys) {
  $fam = Fam $f; $st = [System.Drawing.FontStyle]::Regular; $em = $fam.GetEmHeight($st)
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddString("0", $fam, 0, 100, (New-Object System.Drawing.PointF 0, 0), [System.Drawing.StringFormat]::GenericTypographic)
  $b = $p.GetBounds()
  $metrics[$f] = @{ line = ($fam.GetCellAscent($st) + $fam.GetCellDescent($st)) / $em; capOff = $b.Y / 100; capH = $b.Height / 100 }
}

# ---------------------------------------------------------------- palette
$GREY = "#ffd4d7da"; $RED = "#ffff2424"; $LBL = "#ff7d8287"; $DIM = "#ff3a3d40"; $INK = "#ff0b0b0c"

# ---------------------------------------------------------------- primitives (shared by XML + mock)
$texts = New-Object System.Collections.ArrayList
$shapes = New-Object System.Collections.ArrayList
function Esc($s) { [System.Security.SecurityElement]::Escape($s) }
function Box($font, $size, $capTop) { $m = $metrics[$font]; @{ y = [math]::Round($capTop - $m.capOff * $size - 1); h = [math]::Ceiling($m.line * $size) + 2 } }
# text: $params = WFF expressions (null = literal); $sample = what the mock draws; $alphaExpr optional Transform
function Txt($name, $cx, $capTop, $w, $size, $font, $color, $tpl, $params, $sample, $align = "CENTER", $alphaExpr = $null, $alpha0 = 255) {
  $bx = Box $font $size $capTop
  $x = switch ($align) { "CENTER" { [math]::Round($cx - $w / 2) } "END" { $cx - $w } default { $cx } }
  $null = $texts.Add(@{ name = $name; x = $x; y = $bx.y; w = $w; h = $bx.h; size = $size; font = $font; color = $color; tpl = $tpl; params = $params; sample = $sample; align = $align; alphaExpr = $alphaExpr; alpha0 = $alpha0 })
}
function Ln($x1, $y1, $x2, $y2, $color, $w = 1) { $null = $shapes.Add(@{ t = "line"; x1 = $x1; y1 = $y1; x2 = $x2; y2 = $y2; color = $color; w = $w }) }
function Rect($x, $y, $w, $h, $color) { $null = $shapes.Add(@{ t = "rect"; x = $x; y = $y; w = $w; h = $h; color = $color }) }
function Bracket([double]$x, [double]$y, [int]$dx, [int]$dy, [int]$len, $color) { Ln $x $y ($x + $dx * $len) $y $color 2; Ln $x $y $x ($y + $dy * $len) $color 2 }

# ---------------------------------------------------------------- layout (cap tops)
$sDate = 28; $sTop = 38; $sTime = 130; $sA = 42; $sB = 36; $sLbl = 13; $sBrand = 28
$yDate = 48; $yTopL = 84; $yTopV = 99; $yTime = 147; $yAL = 268; $yAV = 284; $yBL = 332; $yBV = 348; $yBrand = 394
$gap = 26
$RLIM = 204   # content limit; chrono numerals live at r ~216, minute ticks at r 225-231
$GOAL = "clamp(round([STEP_COUNT] * 100.0 / clamp([STEP_GOAL], 1, 100000)), 0, 999)"
$lowOn = "([BATTERY_PERCENT] <= 20) ? 255 : 0"; $lowOff = "([BATTERY_PERCENT] <= 20) ? 0 : 255"

Txt "date" $C $yDate 300 $sDate "saira_stencil" $GREY "%s %s %s" @("[DAY_OF_WEEK_S]", "[DAY]", "[MONTH_S]") "WED 11 NOV"

# top row: HR | WEEK | MSG
$xT = @(124, 233, 342)
Txt "lHr"  $xT[0] $yTopL 90 $sLbl "mono_bold" $LBL "HR" $null "HR"
# [HEART_RATE] arrives as text on the OnePlus Watch 3: comparing it directly always fails, so go through round().
# The sensor also reports 0 between readings, so show "--" until a real value is there.
$HR = "round([HEART_RATE])"
Txt "vHr"  $xT[0] $yTopV 110 $sTop "saira_stencil" $RED "%s" @($HR) "72" "CENTER" "($HR > 0) ? 255 : 0" 0
Txt "vHr0" $xT[0] $yTopV 110 $sTop "saira_stencil" $RED "--" $null "" "CENTER" "($HR > 0) ? 0 : 255" 255
Txt "lWk"  $xT[1] $yTopL 90 $sLbl "mono_bold" $LBL "WEEK" $null "WEEK"
Txt "vWk"  $xT[1] $yTopV 110 $sTop "saira_stencil" $GREY "%s" @("[WEEK_IN_YEAR]") "46"
Txt "lMsg" $xT[2] $yTopL 90 $sLbl "mono_bold" $LBL "MSG" $null "MSG"
Txt "vMsg" $xT[2] $yTopV 110 $sTop "saira_stencil" $GREY "%s" @("[UNREAD_NOTIFICATION_COUNT]") "3"

# time: HH light grey, MM bright red, solid (no outline / glow)
$tw = 210; $hx = $C - $gap / 2; $mx = $C + $gap / 2
Txt "hh24" $hx $yTime $tw $sTime "saira_stencil" $GREY "%s" @("[HOUR_0_23_Z]") "10" "END" "[IS_24_HOUR_MODE] ? 255 : 0" 255
Txt "hh12" $hx $yTime $tw $sTime "saira_stencil" $GREY "%s" @("[HOUR_1_12_Z]") "" "END" "[IS_24_HOUR_MODE] ? 0 : 255" 0
Txt "mm"   $mx $yTime $tw $sTime "saira_stencil" $RED "%s" @("[MINUTE_Z]") "42" "START"
$capT = $metrics.saira_stencil.capH * $sTime
$c1 = [math]::Round($yTime + $capT * 0.25 - 5); $c2 = [math]::Round($yTime + $capT * 0.75 - 5)
Rect 228 $c1 10 10 $RED; Rect 228 $c2 10 10 $RED

# row A: BAT | STEPS | GOAL
$xA = @(102, 233, 364)
Txt "lBat"  $xA[0] $yAL 110 $sLbl "mono_bold" $LBL "BAT" $null "BAT"
Txt "vBat"  $xA[0] $yAV 130 $sA "saira_stencil" $GREY "%s%%" @("[BATTERY_PERCENT]") "76%" "CENTER" $lowOff 255
Txt "vBatL" $xA[0] $yAV 130 $sA "saira_stencil" $RED "%s%%" @("[BATTERY_PERCENT]") "" "CENTER" $lowOn 0
Txt "lStp"  $xA[1] $yAL 130 $sLbl "mono_bold" $LBL "STEPS" $null "STEPS"
Txt "vStp"  $xA[1] $yAV 136 $sA "saira_stencil" $GREY "%s" @("[STEP_COUNT]") "8426"
Txt "lGol"  $xA[2] $yAL 110 $sLbl "mono_bold" $LBL "GOAL" $null "GOAL"
Txt "vGol"  $xA[2] $yAV 130 $sA "saira_stencil" $RED "%s%%" @($GOAL) "84%"

# row B: TEMP | RAIN | KM
$xB = @(128, 233, 344)
Txt "lTmp" $xB[0] $yBL 100 $sLbl "mono_bold" $LBL "TEMP" $null "TEMP"
Txt "vTmp" $xB[0] $yBV 116 $sB "saira_stencil" $GREY "%s°C" @("([WEATHER.TEMPERATURE_UNIT] == 2) ? round(([WEATHER.TEMPERATURE] - 32) / 1.8) : [WEATHER.TEMPERATURE]") "19°C"
Txt "lRn"  $xB[1] $yBL 100 $sLbl "mono_bold" $LBL "RAIN" $null "RAIN"
Txt "vRn"  $xB[1] $yBV 116 $sB "saira_stencil" $GREY "%s%%" @("[WEATHER.CHANCE_OF_PRECIPITATION]") "20%"
# distance is estimated from the step count ($STRIDE metres per step); one decimal built from two integers
$STRIDE = 0.762; $M = "([STEP_COUNT] * $STRIDE)"
Txt "lKm"  $xB[2] $yBL 100 $sLbl "mono_bold" $LBL "KM" $null "KM"
Txt "vKm"  ($xB[2] - 4) $yBV 116 $sB "saira_stencil" $RED "%s.%s" @("floor($M / 1000)", "floor($M / 100) % 10") "6.4"

# brand placard
Rect 171 ($yBrand - 8) 124 36 $RED
Txt "evil" $C $yBrand 124 $sBrand "saira_stencil" $INK "EVIL" $null "EVIL"

# tactical decoration: corner brackets round the time, row rules with red end marks, cell dividers, label ticks
$tb = @{ l = 58; r = 408; t = $yTime - 12; b = $yTime + $capT + 12 }
Bracket $tb.l $tb.t 1 1 16 $LBL; Bracket $tb.r $tb.t -1 1 16 $LBL
$ruleA = $yAL - 11; $ruleB = $yBL - 10
Ln 40 $ruleA 426 $ruleA $DIM 2; Rect 40 ($ruleA - 2) 12 4 $RED; Rect 414 ($ruleA - 2) 12 4 $RED
Ln 62 $ruleB 404 $ruleB $DIM 1
foreach ($vx in 166, 300) { Ln $vx ($yAL - 2) $vx ($yAV + 34) $DIM 1 }
foreach ($vx in 174, 292) { Ln $vx ($yBL - 2) $vx ($yBV + 28) $DIM 1; Ln $vx ($yTopL - 2) $vx ($yTopV + 30) $DIM 1 }
Ln 131 ($yBrand + 10) 161 ($yBrand + 10) $DIM 2; Ln 305 ($yBrand + 10) 335 ($yBrand + 10) $DIM 2

# ---------------------------------------------------------------- fit check: worst-case ink box must stay inside the chrono ring
$worst = @{ date = "WED 30 SEP"; vHr = "188"; vWk = "52"; vMsg = "99"; hh24 = "00"; mm = "00"; vBat = "100%"; vStp = "18888"; vGol = "100%"; vTmp = "-12°C"; vRn = "100%"; vKm = "99.9" }
$chkG = [System.Drawing.Graphics]::FromImage((New-Object System.Drawing.Bitmap 4, 4))
foreach ($t in $texts) {
  $smp = if ($worst[$t.name]) { $worst[$t.name] } else { $t.sample }; if (-not $smp) { continue }
  $m = $metrics[$t.font]; $fnt = New-Object System.Drawing.Font (Fam $t.font), $t.size, ([System.Drawing.GraphicsUnit]::Pixel)
  $wid = $chkG.MeasureString($smp, $fnt, 10000, [System.Drawing.StringFormat]::GenericTypographic).Width
  $x0 = switch ($t.align) { "CENTER" { $t.x + ($t.w - $wid) / 2 } "END" { $t.x + $t.w - $wid } default { $t.x } }
  $y0 = $t.y + 1 + $m.capOff * $t.size; $y1 = $y0 + $m.capH * $t.size
  $rr = 0; foreach ($px in $x0, ($x0 + $wid)) { foreach ($py in $y0, $y1) { $rr = [math]::Max($rr, [math]::Sqrt(($px - $C) * ($px - $C) + ($py - $C) * ($py - $C))) } }
  if ($rr -gt $RLIM) { Write-Warning ("{0} '{1}' reaches r={2:N0} (limit {3})" -f $t.name, $smp, $rr, $RLIM) }
}

# ---------------------------------------------------------------- XML
function TextXml($t, $ind) {
  $color = $t.color; $body = if ($t.params) { "<Template>$(Esc $t.tpl)" + (($t.params | ForEach-Object { "<Parameter expression=`"$(Esc $_)`"/>" }) -join "") + "</Template>" } else { Esc $t.tpl }
  if ($t.name -like "date*") { $body = "<Upper>$body</Upper>" }
  $alpha = if ($t.alphaExpr) { " alpha=`"$($t.alpha0)`"" } else { "" }
  $tr = if ($t.alphaExpr) { "<Transform target=`"alpha`" value=`"$(Esc $t.alphaExpr)`"/>" } else { "" }
  "$ind<PartText name=`"$($t.name)`" x=`"$($t.x)`" y=`"$($t.y)`" width=`"$($t.w)`" height=`"$($t.h)`"$alpha>$tr<Text align=`"$($t.align)`"><Font family=`"$($t.font)`" size=`"$($t.size)`" color=`"$color`">$body</Font></Text></PartText>`n"
}
$shapeXml = "      <PartDraw name=`"deco`" x=`"0`" y=`"0`" width=`"466`" height=`"466`">`n"
foreach ($sh in $shapes) {
  if ($sh.t -eq "line") { $shapeXml += "        <Line startX=`"$($sh.x1)`" startY=`"$($sh.y1)`" endX=`"$($sh.x2)`" endY=`"$($sh.y2)`"><Stroke color=`"$($sh.color)`" thickness=`"$($sh.w)`"/></Line>`n" }
  else { $shapeXml += "        <Rectangle x=`"$($sh.x)`" y=`"$($sh.y)`" width=`"$($sh.w)`" height=`"$($sh.h)`"><Fill color=`"$($sh.color)`"/></Rectangle>`n" }
}
$shapeXml += "      </PartDraw>`n"
$active = $shapeXml; foreach ($t in $texts) { $active += TextXml $t "      " }
# chrono seconds hand: outer needle only (r 150..231), pivot = screen centre
$HW = 24; $HH = 233
$active += @"
      <AnalogClock name="chrono" x="0" y="0" width="466" height="466">
        <SecondHand resource="sec_hand" x="$($C - $HW / 2)" y="0" width="$HW" height="$HH" pivotX="0.5" pivotY="1.0"/>
      </AnalogClock>

"@

# always-on: outline-only time only (grey hours, red minutes)
$aod = ""
foreach ($t in $texts | Where-Object { $_.name -in "hh24", "hh12", "mm" }) {
  $oc = if ($t.name -eq "mm") { "#ffc81c1c" } else { "#ffa9adb1" }
  $a = $t.Clone(); $a.name += "A"
  $x = TextXml $a "      "
  $aod += $x -replace "color=`"$($t.color)`">(.*)</Font>", "color=`"#ff000000`"><Outline color=`"$oc`" width=`"2`">`$1</Outline></Font>"
}
# (no colon, no date in AOD - fewer lit pixels)

$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<!-- EVIL v4: military data face with chrono seconds hand, Watch Face Format v2, 466x466. Generated by tools/gen-evil.ps1 - edit that, not this. -->
<WatchFace width="466" height="466">
  <Metadata key="CLOCK_TYPE" value="DIGITAL"/>
  <Metadata key="PREVIEW_TIME" value="10:42:37"/>
  <Scene backgroundColor="#ff000000">

    <PartImage name="bg" x="0" y="0" width="466" height="466" alpha="255">
      <Variant mode="AMBIENT" target="alpha" value="0"/>
      <Image resource="bg"/>
    </PartImage>

    <!-- ================= ACTIVE ================= -->
    <Group name="active" x="0" y="0" width="466" height="466" alpha="255">
      <Variant mode="AMBIENT" target="alpha" value="0"/>
$active    </Group>

    <!-- ================= ALWAYS-ON ================= -->
    <Group name="aod" x="0" y="0" width="466" height="466" alpha="0">
      <Variant mode="AMBIENT" target="alpha" value="255"/>
$aod    </Group>

  </Scene>
</WatchFace>
"@
Set-Content (Join-Path $root "res\raw\watchface.xml") $xml -NoNewline -Encoding utf8NoBOM
Write-Host "watchface.xml written"

# ---------------------------------------------------------------- background bitmap
function ParseCol($hex) { $v = [Convert]::ToUInt32($hex.TrimStart('#'), 16); [System.Drawing.Color]::FromArgb([int](($v -shr 24) -band 255), [int](($v -shr 16) -band 255), [int](($v -shr 8) -band 255), [int]($v -band 255)) }
$bg = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bg); $g.SmoothingMode = 'AntiAlias'; $g.Clear([System.Drawing.Color]::Black)
$path = New-Object System.Drawing.Drawing2D.GraphicsPath; $path.AddEllipse(-80, -80, $S + 160, $S + 160)
$pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $path
$pgb.CenterColor = [System.Drawing.Color]::FromArgb(255, 20, 21, 22); $pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(255, 4, 4, 4))
$g.FillRectangle($pgb, 0, 0, $S, $S)
$grid = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(12, 200, 205, 210)), 1
for ($i = 13; $i -lt $S; $i += 24) { $g.DrawLine($grid, $i, 0, $i, $S); $g.DrawLine($grid, 0, $i, $S, $i) }
# bezel: 60 minute ticks, longer every 5, red index at 12
$minor = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(130, 125, 129, 133)), 1.2
for ($k = 0; $k -lt 300; $k++) {
  # 1/5-second graduations (chrono scale): every 1.2 deg; full seconds longer
  if ($k % 25 -eq 0) { continue }
  $a = $k * 1.2 * [math]::PI / 180; $full = ($k % 5 -eq 0); $r1 = 231; $r0 = if ($full) { 224 } else { 228 }
  $pen = if ($full) { $minor } else { New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, 125, 129, 133)), 0.8 }
  $g.DrawLine($pen, [float]($C + $r0 * [math]::Sin($a)), [float]($C - $r0 * [math]::Cos($a)), [float]($C + $r1 * [math]::Sin($a)), [float]($C - $r1 * [math]::Cos($a)))
}
# chrono numerals 5..55 (60 = red index)
$numFam = Fam "mono_bold"; $numBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 176, 180, 184))
for ($n = 5; $n -le 55; $n += 5) {
  $a = $n * 6 * [math]::PI / 180; $rN = 213
  $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp.AddString([string]$n, $numFam, 1, 14, (New-Object System.Drawing.PointF 0, 0), [System.Drawing.StringFormat]::GenericTypographic)
  $b = $gp.GetBounds(); $mx2 = New-Object System.Drawing.Drawing2D.Matrix
  $mx2.Translate([float]($C + $rN * [math]::Sin($a) - $b.X - $b.Width / 2), [float]($C - $rN * [math]::Cos($a) - $b.Y - $b.Height / 2))
  $gp.Transform($mx2); $g.FillPath($numBrush, $gp)
}
$g.FillPolygon((New-Object System.Drawing.SolidBrush (ParseCol $RED)), [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 226, 3), (New-Object System.Drawing.PointF 240, 3), (New-Object System.Drawing.PointF 233, 16)))
$g.Dispose()
$bg.Save((Join-Path $root "res\drawable\bg.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$hand = New-Object System.Drawing.Bitmap $HW, $HH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($hand); $g.SmoothingMode = 'AntiAlias'; $g.Clear([System.Drawing.Color]::Transparent)
$hc = $HW / 2; $hb = New-Object System.Drawing.SolidBrush (ParseCol $RED)
$g.FillRectangle($hb, [float]($hc - 1.25), [float]($HH - 226), 2.5, 226 - 150)          # needle r 150..226
$g.FillPolygon($hb, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF $hc, ($HH - 232)), (New-Object System.Drawing.PointF ($hc + 4.5), ($HH - 218)), (New-Object System.Drawing.PointF ($hc - 4.5), ($HH - 218))))  # arrow tip
$g.FillRectangle($hb, [float]($hc - 3), [float]($HH - 160), 6, 10)                      # tail block
$g.Dispose()
$hand.Save((Join-Path $root "res\drawable\sec_hand.png"), [System.Drawing.Imaging.ImageFormat]::Png)

# ---------------------------------------------------------------- mock preview
$mk = New-Object System.Drawing.Bitmap $S, $S; $g = [System.Drawing.Graphics]::FromImage($mk)
$g.SmoothingMode = 'AntiAlias'; $g.DrawImage($bg, 0, 0, $S, $S)
foreach ($sh in $shapes) {
  if ($sh.t -eq "line") { $g.DrawLine((New-Object System.Drawing.Pen (ParseCol $sh.color), $sh.w), $sh.x1, $sh.y1, $sh.x2, $sh.y2) }
  else { $g.FillRectangle((New-Object System.Drawing.SolidBrush (ParseCol $sh.color)), $sh.x, $sh.y, $sh.w, $sh.h) }
}
$sf0 = [System.Drawing.StringFormat]::GenericTypographic
foreach ($t in $texts) {
  if (-not $t.sample) { continue }
  $fam = Fam $t.font; $font = New-Object System.Drawing.Font $fam, $t.size, ([System.Drawing.GraphicsUnit]::Pixel)
  $wid = $g.MeasureString($t.sample, $font, 10000, $sf0).Width
  $x = switch ($t.align) { "CENTER" { $t.x + ($t.w - $wid) / 2 } "END" { $t.x + $t.w - $wid } default { $t.x } }
  $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp.AddString($t.sample, $fam, 0, $t.size, (New-Object System.Drawing.PointF $x, ($t.y + 1)), $sf0)
  $g.FillPath((New-Object System.Drawing.SolidBrush (ParseCol $t.color)), $gp)
}
$st = $g.Save(); $g.TranslateTransform($C, $C); $g.RotateTransform(37 * 6); $g.DrawImage($hand, [float](-$HW / 2), [float](-$HH), [float]$HW, [float]$HH); $g.Restore($st)
$clip = New-Object System.Drawing.Drawing2D.GraphicsPath; $clip.AddEllipse(0, 0, $S, $S)
$reg = New-Object System.Drawing.Region (New-Object System.Drawing.Rectangle 0, 0, $S, $S); $reg.Exclude($clip); $g.FillRegion([System.Drawing.Brushes]::Black, $reg)
$g.Dispose()
$mk.Save((Join-Path $root "res\drawable\preview.png"), [System.Drawing.Imaging.ImageFormat]::Png)
if ($MockOut) { $mk.Save($MockOut, [System.Drawing.Imaging.ImageFormat]::Png) }
Write-Host "bg.png + preview.png written"
