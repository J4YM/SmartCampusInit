# Regenerates windows/runner/resources/app_icon.ico from a source PNG
# (defaults to the STI logo) as a proper multi-resolution icon — standard
# sizes, PNG-encoded frames (supported since Windows Vista, avoids the
# 8-bit-depth limits of legacy BMP-in-ICO). No external tools required
# (System.Drawing is part of .NET). Run from the repo root whenever the
# source logo changes; re-run `flutter build windows` and the Inno Setup
# compile (kiosk_installer.iss) afterward to pick it up.
#
# Usage: powershell -ExecutionPolicy Bypass -File windows/installer/make_icon.ps1

param(
    [string]$SourcePng = "assets/images/sti_logo.png",
    [string]$OutputIco = "windows/runner/resources/app_icon.ico",
    [int[]]$Sizes = @(16, 32, 48, 64, 128, 256)
)

Add-Type -AssemblyName System.Drawing

$src = [System.Drawing.Image]::FromFile((Resolve-Path $SourcePng))

$pngBytesPerSize = @{}
foreach ($size in $Sizes) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($src, 0, 0, $size, $size)
    $g.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBytesPerSize[$size] = $ms.ToArray()
    $ms.Dispose()
    $bmp.Dispose()
}
$src.Dispose()

# ICO container: ICONDIR (6 bytes) + one ICONDIRENTRY (16 bytes) per image,
# followed by the raw PNG bytes for each image back to back.
$count = $Sizes.Count
$headerSize = 6 + (16 * $count)
$offset = $headerSize

$stream = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter($stream)

# ICONDIR: reserved(2)=0, type(2)=1 (icon), count(2)
$w.Write([UInt16]0)
$w.Write([UInt16]1)
$w.Write([UInt16]$count)

foreach ($size in $Sizes) {
    $bytes = $pngBytesPerSize[$size]
    # width/height byte: 0 means 256
    $dim = if ($size -eq 256) { 0 } else { $size }
    $w.Write([Byte]$dim)      # width
    $w.Write([Byte]$dim)      # height
    $w.Write([Byte]0)         # color palette (0 = no palette, PNG frame)
    $w.Write([Byte]0)         # reserved
    $w.Write([UInt16]1)       # color planes
    $w.Write([UInt16]32)      # bits per pixel
    $w.Write([UInt32]$bytes.Length)
    $w.Write([UInt32]$offset)
    $offset += $bytes.Length
}

foreach ($size in $Sizes) {
    $w.Write($pngBytesPerSize[$size])
}

$w.Flush()
[System.IO.File]::WriteAllBytes((Join-Path (Get-Location) $OutputIco), $stream.ToArray())
$w.Dispose()
$stream.Dispose()

Write-Output "Wrote $OutputIco ($($Sizes -join ', ') px)"
