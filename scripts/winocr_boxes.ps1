# winocr_boxes.ps1 - full-page word BOUNDING BOXES via Windows.Media.Ocr.
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File winocr_boxes.ps1 <image.png> <out.txt>
# Output: line 1 "W H" (page pixels); then one line per word: "x y w h".
#
# The figure pipeline's text mask: regions carrying words are prose, and
# whatever is inky OUTSIDE them is a figure candidate. Geometry only - the
# words' TEXT stays out of this file; transcription is the model's job.
# Same in-memory decode as winocr_label.ps1 (OneDrive grabs fresh files).
param(
    [Parameter(Mandatory=$true)][string]$ImagePath,
    [Parameter(Mandatory=$true)][string]$OutPath
)
$ErrorActionPreference = 'Stop'
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
                       $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    function Await($WinRtTask, $ResultType) {
        $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        $netTask.Wait(-1) | Out-Null
        $netTask.Result
    }
    [Windows.Media.Ocr.OcrEngine, Windows.Foundation.UniversalApiContract, ContentType=WindowsRuntime] | Out-Null
    [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime] | Out-Null

    $bytes = $null
    for ($i = 0; $i -lt 8 -and $null -eq $bytes; $i++) {
        try { $bytes = [System.IO.File]::ReadAllBytes($ImagePath) }
        catch { Start-Sleep -Milliseconds 120 }
    }
    if ($null -eq $bytes) { throw "could not read $ImagePath after retries" }

    $mem     = New-Object System.IO.MemoryStream(,$bytes)
    $ras     = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($mem)
    $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap  = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $engine  = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($null -eq $engine) { throw "no OCR engine for the user profile languages" }
    $result  = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("$($bitmap.PixelWidth) $($bitmap.PixelHeight)")
    foreach ($line in $result.Lines) {
        foreach ($w in $line.Words) {
            $r = $w.BoundingRect
            [void]$sb.AppendLine(("{0} {1} {2} {3}" -f `
                [int][math]::Floor($r.X), [int][math]::Floor($r.Y), `
                [int][math]::Ceiling($r.Width), [int][math]::Ceiling($r.Height)))
        }
    }
    [System.IO.File]::WriteAllText($OutPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    exit 0
} catch {
    # empty first line = failure to the reader; reason chain on line 2
    $e = $_.Exception; $reason = "ERR"
    while ($null -ne $e) { $reason += " " + $e.GetType().Name + ": " + $e.Message; $e = $e.InnerException }
    [System.IO.File]::WriteAllText($OutPath, ("`n" + $reason), (New-Object System.Text.UTF8Encoding($false)))
    exit 1
}
