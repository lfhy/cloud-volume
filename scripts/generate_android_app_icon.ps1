param(
    [string]$Source = "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png",
    [string]$OutputRoot = "android/app/src/main/res",
    # Adaptive-icon safe zone: Android keeps only the inner ~66dp of the 108dp
    # canvas across launcher masks, so the artwork is fitted into this ratio.
    [ValidateRange(0.4, 0.9)]
    [double]$SafeZoneRatio = 66 / 108,
    # Pixels below this channel value count as artwork when locating the
    # content bounding box on the opaque white master.
    [ValidateRange(128, 254)]
    [int]$ContentThreshold = 245
)

# Generates the Android launcher icon family from the shared brand raster:
# legacy square + round PNGs for pre-API-26 launchers, and adaptive-icon
# foreground PNGs whose artwork sits inside the API 26+ safe zone.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = [IO.Path]::GetFullPath((Join-Path $repoRoot $Source))
$outputRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))

# density -> legacy launcher px (48dp base), adaptive foreground px (108dp canvas)
$densities = @(
    @{ Name = "mdpi";    Legacy = 48;  Foreground = 108 }
    @{ Name = "hdpi";    Legacy = 72;  Foreground = 162 }
    @{ Name = "xhdpi";   Legacy = 96;  Foreground = 216 }
    @{ Name = "xxhdpi";  Legacy = 144; Foreground = 324 }
    @{ Name = "xxxhdpi"; Legacy = 192; Foreground = 432 }
)

if (-not [IO.File]::Exists($sourcePath)) {
    throw "Icon source does not exist: $sourcePath"
}

function New-Graphics {
    param([Drawing.Bitmap]$Bitmap)

    $graphics = [Drawing.Graphics]::FromImage($Bitmap)
    $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    return $graphics
}

function New-LegacySquare {
    param([Drawing.Image]$Master, [int]$Size)

    $frame = [Drawing.Bitmap]::new($Size, $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = New-Graphics -Bitmap $frame
    try {
        $graphics.DrawImage($Master, [Drawing.Rectangle]::new(0, 0, $Size, $Size))
    } finally {
        $graphics.Dispose()
    }
    return $frame
}

function New-LegacyRound {
    param([Drawing.Image]$Master, [int]$Size)

    # TextureBrush samples the image at native pixel scale, so the circular
    # mask must be applied to an already-resized square, never the 1024 master.
    $square = New-LegacySquare -Master $Master -Size $Size
    $frame = [Drawing.Bitmap]::new($Size, $Size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = New-Graphics -Bitmap $frame
    $brush = $null
    $path = $null
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $brush = [Drawing.TextureBrush]::new($square, [Drawing.Drawing2D.WrapMode]::Clamp)
        $path = [Drawing.Drawing2D.GraphicsPath]::new()
        $path.AddEllipse(0, 0, $Size, $Size)
        $graphics.FillPath($brush, $path)
    } finally {
        if ($null -ne $brush) { $brush.Dispose() }
        if ($null -ne $path) { $path.Dispose() }
        $graphics.Dispose()
        $square.Dispose()
    }
    return $frame
}

function Get-ContentBounds {
    # Locates the non-white artwork bounding box on the opaque master so the
    # adaptive foreground can scale the actual logo instead of guessing margins.
    param([Drawing.Bitmap]$Master)

    $rect = [Drawing.Rectangle]::new(0, 0, $Master.Width, $Master.Height)
    $data = $Master.LockBits(
        $rect,
        [Drawing.Imaging.ImageLockMode]::ReadOnly,
        [Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    try {
        $bytes = [byte[]]::new($data.Stride * $data.Height)
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
        $minX = $Master.Width; $minY = $Master.Height; $maxX = -1; $maxY = -1
        for ($y = 0; $y -lt $Master.Height; $y++) {
            $row = $y * $data.Stride
            for ($x = 0; $x -lt $Master.Width; $x++) {
                $offset = $row + ($x * 4)
                $b = $bytes[$offset]
                $g = $bytes[$offset + 1]
                $r = $bytes[$offset + 2]
                if ($r -lt $ContentThreshold -or $g -lt $ContentThreshold -or $b -lt $ContentThreshold) {
                    if ($x -lt $minX) { $minX = $x }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }
    } finally {
        $Master.UnlockBits($data)
    }

    if ($maxX -lt 0) {
        throw "Icon source appears blank (no non-white pixels): $sourcePath"
    }
    return [Drawing.Rectangle]::FromLTRB($minX, $minY, $maxX + 1, $maxY + 1)
}

function New-AdaptiveForeground {
    param(
        [Drawing.Image]$Master,
        [Drawing.Rectangle]$Content,
        [int]$CanvasSize
    )

    # Pad the crop so anti-aliased artwork edges keep their neighbouring white
    # pixels instead of being resampled against a hard crop boundary.
    $pad = [int][Math]::Max(1, [Math]::Round($Master.Width * 0.01))
    $crop = [Drawing.Rectangle]::new(
        [Math]::Max(0, $Content.X - $pad),
        [Math]::Max(0, $Content.Y - $pad),
        0,
        0
    )
    $crop.Width = [Math]::Min($Master.Width - $crop.X, $Content.Width + (2 * $pad))
    $crop.Height = [Math]::Min($Master.Height - $crop.Y, $Content.Height + (2 * $pad))

    $frame = [Drawing.Bitmap]::new($CanvasSize, $CanvasSize, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = New-Graphics -Bitmap $frame
    try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $safeSize = $CanvasSize * $SafeZoneRatio
        $scale = [Math]::Min($safeSize / $crop.Width, $safeSize / $crop.Height)
        $drawWidth = $crop.Width * $scale
        $drawHeight = $crop.Height * $scale
        $destination = [Drawing.Rectangle]::new(
            [int](($CanvasSize - $drawWidth) / 2),
            [int](($CanvasSize - $drawHeight) / 2),
            [int][Math]::Ceiling($drawWidth),
            [int][Math]::Ceiling($drawHeight)
        )
        $graphics.DrawImage($Master, $destination, $crop, [Drawing.GraphicsUnit]::Pixel)
    } finally {
        $graphics.Dispose()
    }
    return $frame
}

function Save-Png {
    param([Drawing.Bitmap]$Frame, [string]$RelativePath)

    $target = [IO.Path]::GetFullPath((Join-Path $outputRoot $RelativePath))
    [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
    $Frame.Save($target, [Drawing.Imaging.ImageFormat]::Png)
    Write-Host "Generated $target ($($Frame.Width)x$($Frame.Height))"
}

# LockBits converts to Format32bppArgb on read, so the master keeps its
# native on-disk format.
$master = [Drawing.Bitmap]::new($sourcePath)
try {
    if ($master.Width -ne $master.Height) {
        throw "Icon source must be square: $sourcePath"
    }

    $content = Get-ContentBounds -Master $master
    Write-Host (
        "Artwork content bounds: {0},{1} {2}x{3} of {4}x{4}" -f `
            $content.X, $content.Y, $content.Width, $content.Height, $master.Width
    )

    foreach ($density in $densities) {
        $name = $density.Name
        $legacy = New-LegacySquare -Master $master -Size $density.Legacy
        try {
            Save-Png -Frame $legacy -RelativePath "mipmap-$name/ic_launcher.png"
        } finally {
            $legacy.Dispose()
        }

        $round = New-LegacyRound -Master $master -Size $density.Legacy
        try {
            Save-Png -Frame $round -RelativePath "mipmap-$name/ic_launcher_round.png"
        } finally {
            $round.Dispose()
        }

        $foreground = New-AdaptiveForeground -Master $master -Content $content -CanvasSize $density.Foreground
        try {
            Save-Png -Frame $foreground -RelativePath "mipmap-$name/ic_launcher_foreground.png"
        } finally {
            $foreground.Dispose()
        }
    }
} finally {
    $master.Dispose()
}

Write-Host (
    "Android launcher icons generated from {0} into {1}." -f $sourcePath, $outputRoot
)
