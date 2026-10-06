# winocr_label.ps1 - page-indicator OCR via Windows.Media.Ocr (WinRT).
# Usage: powershell.exe -NoProfile -ExecutionPolicy Bypass -File winocr_label.ps1 <image.png> <out.txt>
# Reads "Page 33 of 286"-class labels in ~0.2-0.5 s where the 7B vision
# model needs seconds. Requires Windows PowerShell 5.1 (WinRT projection).
#
# The image is read as bytes and decoded from memory: StorageFile's brokered
# open loses a sharing race against OneDrive, which grabs freshly written
# files to hash and upload - exactly when the capture engine calls us.
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

    # bytes first, retried: the writer (or OneDrive) may still hold the file
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
    # single line out: the page-position parser wants plain text
    [System.IO.File]::WriteAllText($OutPath, $result.Text, (New-Object System.Text.UTF8Encoding($false)))
    exit 0
} catch {
    # empty first line = failure to the engine; the full reason chain rides
    # on line 2 so a stuck ETA can be diagnosed from the probe file itself.
    $e = $_.Exception; $reason = "ERR"
    while ($null -ne $e) { $reason += " " + $e.GetType().Name + ": " + $e.Message; $e = $e.InnerException }
    [System.IO.File]::WriteAllText($OutPath, ("`n" + $reason), (New-Object System.Text.UTF8Encoding($false)))
    exit 1
}
