[CmdletBinding()]
param([switch]$SkipLegacyFolderSync)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$stage=Join-Path $root "dist\release_$stamp\Fix_ThongBao_Vivo_OriginOS"
[void][System.IO.Directory]::CreateDirectory($stage)
$required=@('VivoNotificationFixer.ps1','NotificationState.ps1','CHAY_CONG_CU_FIX_THONG_BAO.bat','1_KIEM_TRA_TRANG_THAI.bat','2_TOI_UU_THONG_BAO.bat','3_KHOI_PHUC_HOAN_TAC.bat','4_KIEM_TRA_KET_NOI_FCM.bat','5_KIEM_TRA_AP_DUNG_LAI.bat')
foreach ($name in $required) {
    $source=Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing release file: $source" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name)
}
foreach ($name in @('adb.exe','AdbWinApi.dll','AdbWinUsbApi.dll')) {
    $source=Join-Path $PSScriptRoot $name
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $stage $name) }
}
foreach ($name in @('README.md','HUONG_DAN_SU_DUNG.txt')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $stage $name) }
$archive=Join-Path (Split-Path $stage -Parent) 'Fix_ThongBao_Vivo_OriginOS.zip'
# Build from an allowlist in a new directory; device logs/backups never enter it.
Compress-Archive -LiteralPath $stage -DestinationPath $archive -CompressionLevel Optimal
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[System.IO.Compression.ZipFile]::OpenRead($archive)
try {
    if (@($zip.Entries | Where-Object { $_.FullName -match '(^|[/\\])(logs|backups|reports)([/\\]|$)' }).Count -gt 0) { throw 'Private runtime data found in ZIP.' }
    foreach ($name in $required + @('README.md','HUONG_DAN_SU_DUNG.txt')) {
        if (@($zip.Entries | Where-Object { ($_.FullName -replace '\\','/') -eq "Fix_ThongBao_Vivo_OriginOS/$name" }).Count -ne 1) { throw "Missing/duplicate archive file: $name" }
    }
    foreach ($entry in $zip.Entries) {
        if (-not $entry.Name) { continue }
        $stream=$entry.Open(); $sha=[System.Security.Cryptography.SHA256]::Create()
        try { $zipHash=([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
        finally { $stream.Dispose(); $sha.Dispose() }
        $file=Join-Path $stage $entry.Name
        if ($zipHash -cne (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash) { throw "Archive content mismatch: $($entry.Name)" }
    }
} finally { $zip.Dispose() }
$destination=Join-Path $root 'Fix_ThongBao_Vivo_OriginOS.zip'
if (Test-Path -LiteralPath $destination) {
    $previousDir=Join-Path $root 'dist\previous'
    [void][System.IO.Directory]::CreateDirectory($previousDir)
    Copy-Item -LiteralPath $destination -Destination (Join-Path $previousDir "Fix_ThongBao_Vivo_OriginOS_$stamp.zip")
}
Copy-Item -LiteralPath $archive -Destination $destination -Force
if (-not $SkipLegacyFolderSync) {
    $legacy=Join-Path $root 'Fix_ThongBao_Vivo_OriginOS'
    [void][System.IO.Directory]::CreateDirectory($legacy)
    # Remove obsolete launchers, but preserve runtime data in an existing install.
    # The new staging folder and ZIP above already exclude private runtime data.
    foreach ($obsolete in @('2_KHOI_PHUC_HOAN_TAC.bat','3_CHAN_DOAN_FCM.bat')) {
        $oldFile = Join-Path $legacy $obsolete
        if (Test-Path -LiteralPath $oldFile) { Remove-Item -LiteralPath $oldFile -Force }
    }
    foreach ($file in (Get-ChildItem -LiteralPath $stage -File)) { Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $legacy $file.Name) -Force }
}
Write-Host "Release ZIP: $destination"
Write-Host "Clean folder: $stage"
Write-Host "SHA256: $((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash)"
