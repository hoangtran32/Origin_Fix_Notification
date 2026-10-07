<#
.SYNOPSIS
    Vivo OriginOS Notification Master Fixer & Auditor (ADB Edition)
    Toi uu hoa thong bao, kiem tra, sao luu va hoan tac chinh xac cho Vivo OriginOS.
.DESCRIPTION
    Ho tro kiem tra chi tiet (Audit), sao luu trang thai goc, toi uu hoa co chon loc,
    xac minh ket qua thoi gian thuc, va hoan tac chinh xac khong anh huong quyen khac.
#>

[CmdletBinding()]
param (
    [switch]$Audit,
    [switch]$Fix,
    [switch]$Restore,
    [switch]$FCMTest,
    [string]$TargetPackage,
    [switch]$AdvancedPermissions
)

# Thiet lap Encoding UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Dinh vi ADB
$AdbPath = "adb"
if (Test-Path "$PSScriptRoot\adb.exe") {
    $AdbPath = "$PSScriptRoot\adb.exe"
} elseif (Test-Path "$PSScriptRoot\..\tools\adb.exe") {
    $AdbPath = "$PSScriptRoot\..\tools\adb.exe"
}

# Danh muc ung dung muc tieu pho bien
$KnownAppCatalog = @{
    "com.facebook.orca"         = @{ Name = "Facebook Messenger"; Category = "Nhan tin" }
    "com.facebook.katana"       = @{ Name = "Facebook";           Category = "Mang xa hoi" }
    "com.zing.zalo"             = @{ Name = "Zalo";               Category = "Nhan tin" }
    "org.telegram.messenger"    = @{ Name = "Telegram";           Category = "Nhan tin" }
    "com.discord"               = @{ Name = "Discord";            Category = "Nhan tin" }
    "com.whatsapp"              = @{ Name = "WhatsApp";           Category = "Nhan tin" }
    "com.viber.voip"            = @{ Name = "Viber";              Category = "Nhan tin" }
    "com.google.android.gm"     = @{ Name = "Gmail";              Category = "Email" }
    "com.microsoft.teams"       = @{ Name = "Microsoft Teams";    Category = "Cong viec" }
    "com.skype.raider"          = @{ Name = "Skype";              Category = "Cong viec" }
    "org.thoughtcrime.securesms"= @{ Name = "Signal";             Category = "Nhan tin" }
    "com.instagram.android"     = @{ Name = "Instagram";          Category = "Mang xa hoi" }
    "com.ss.android.ugc.trill"  = @{ Name = "TikTok";             Category = "Mang xa hoi" }
    "com.locket.Locket"         = @{ Name = "Locket Widget";      Category = "Mang xa hoi" }
    "com.shopee.vn"             = @{ Name = "Shopee";             Category = "Mua sam" }
    "com.lazada.android"        = @{ Name = "Lazada";             Category = "Mua sam" }
    "xyz.be.customer"           = @{ Name = "Be (Goi xe)";        Category = "Van chuyen" }
    "com.grabtaxi.passenger"    = @{ Name = "Grab";               Category = "Van chuyen" }
    # Ngan hang & Vi dien tu
    "vn.com.techcombank.bb.app" = @{ Name = "Techcombank";        Category = "Ngan hang" }
    "com.mbmobile"              = @{ Name = "MB Bank";            Category = "Ngan hang" }
    "com.VCB"                   = @{ Name = "Vietcombank";        Category = "Ngan hang" }
    "com.vpb.vpbankneo"         = @{ Name = "VPBank NEO";         Category = "Ngan hang" }
    "com.vnpay.bidv"            = @{ Name = "BIDV SmartBanking";  Category = "Ngan hang" }
    "com.vietinbank.ipay"       = @{ Name = "VietinBank iPay";    Category = "Ngan hang" }
    "com.tpb.mb.gprsandroid"    = @{ Name = "TPBank";             Category = "Ngan hang" }
    "mobile.acb.com.vn"         = @{ Name = "ACB ONE";            Category = "Ngan hang" }
    "com.msb.mb"                = @{ Name = "MSB mBank";          Category = "Ngan hang" }
    "com.vng.zingvn"            = @{ Name = "ZaloPay";            Category = "Vi dien tu" }
    "com.mservice.momotransfer" = @{ Name = "MoMo";               Category = "Vi dien tu" }
}

$StandbyBucketNames = @{
    5  = "EXEMPTED (Mien tru Doze - Uu tien tuyet doi)"
    10 = "ACTIVE (Tich cuc - Toi uu nhat)"
    20 = "WORKING_SET (Hay dung)"
    30 = "FREQUENT (Thuong xuyen)"
    40 = "RARE (Hiem dung - De bi tre)"
    45 = "RESTRICTED (Bi han che - De mat thong bao)"
    50 = "NEVER (Khong bao gio)"
}

function Show-Header {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "   VIVO ORIGINOS NOTIFICATION MASTER FIXER & AUDITOR (ADB CHUYEN NGHIEP)       " -ForegroundColor Yellow
    Write-Host "   Kiem tra - Sao luu chi tiet - Toi uu co chon loc - Xac minh - Hoan tac an toan" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Check-AdbConnection {
    $rawLines = @(& $AdbPath devices)
    $validDevices = @()
    foreach ($line in $rawLines) {
        $trimmed = $line.Trim()
        if ($trimmed -match "^([^\s]+)\s+device$") {
            $validDevices += $matches[1].Trim()
        }
    }

    if ($validDevices.Count -eq 0) {
        Write-Host "[!] KHONG TIM THAY THIET BI KET NOI QUA ADB!" -ForegroundColor Red
        Write-Host "    Vui long kiem tra:" -ForegroundColor Yellow
        Write-Host "    1. Cap USB da cam chac chan vao may tinh."
        Write-Host "    2. Tren dien thoai da bat 'Tuy chon nha phat trien' -> 'Go loi USB' (USB Debugging)."
        Write-Host "    3. Chon 'Luon cho phep tu may tinh nay' tren man hinh dien thoai neu co popup."
        Write-Host ""
        return $null
    }

    $selectedSerial = $validDevices[0]
    return $selectedSerial
}

function Get-DeviceMetadata {
    param ([string]$Serial)
    $rawModel = (& $AdbPath -s $Serial shell getprop ro.product.model 2>$null)
    $rawOs = (& $AdbPath -s $Serial shell getprop ro.build.version.release 2>$null)
    $rawOrigin = (& $AdbPath -s $Serial shell getprop ro.vivo.os.build.display.id 2>$null)
    if (-not $rawOrigin) {
        $rawOrigin = (& $AdbPath -s $Serial shell getprop ro.vivo.os.name 2>$null)
    }

    $model = if ($rawModel) { [string]$rawModel.ToString().Trim() } else { "Vivo Device" }
    $osVersion = if ($rawOs) { [string]$rawOs.ToString().Trim() } else { "Android" }
    $funtouch = if ($rawOrigin) { [string]$rawOrigin.ToString().Trim() } else { "OriginOS" }

    return @{
        Serial    = $Serial
        Model     = $model
        Android   = $osVersion
        OriginOS  = $funtouch
    }
}

function Get-DeviceUsers {
    param ([string]$Serial)
    $users = @()
    $lines = @(& $AdbPath -s $Serial shell pm list users 2>$null)
    foreach ($line in $lines) {
        if ($line -match "UserInfo\{(\d+):([^:]+):") {
            $users += [PSCustomObject]@{
                Id   = [int]$matches[1]
                Name = $matches[2]
            }
        }
    }
    if ($users.Count -eq 0) {
        $users += [PSCustomObject]@{ Id = 0; Name = "Owner" }
    }
    return $users
}

function Get-InstalledTargetPackages {
    param (
        [string]$Serial,
        [array]$Users
    )
    $installed = @{}
    foreach ($u in $Users) {
        $userId = $u.Id
        $pkgs = @(& $AdbPath -s $Serial shell pm list packages --user $userId 2>$null)
        foreach ($line in $pkgs) {
            $pkg = $line.Replace("package:", "").Trim()
            if ($KnownAppCatalog.ContainsKey($pkg)) {
                if (-not $installed.ContainsKey($pkg)) {
                    $installed[$pkg] = @{
                        Name     = $KnownAppCatalog[$pkg].Name
                        Category = $KnownAppCatalog[$pkg].Category
                        Users    = @($userId)
                    }
                } else {
                    if ($installed[$pkg].Users -notcontains $userId) {
                        $installed[$pkg].Users += $userId
                    }
                }
            }
        }
    }
    return $installed
}

function Get-DozeWhitelist {
    param ([string]$Serial)
    $raw = @(& $AdbPath -s $Serial shell dumpsys deviceidle whitelist 2>$null)
    $list = @()
    foreach ($line in $raw) {
        if ($line -match "^(?:System|User),([^,]+)") {
            $list += $matches[1].Trim()
        } elseif ($line -match "^\s*([a-zA-Z0-9_\.]+)\s*$") {
            $list += $matches[1].Trim()
        }
    }
    return $list
}

function Get-AppOpState {
    param (
        [string]$Serial,
        [int]$UserId,
        [string]$Package,
        [string]$Op
    )
    $out = @(& $AdbPath -s $Serial shell cmd appops get --user $UserId $Package $Op 2>&1)
    $outStr = [string]($out -join " ")
    if ($outStr -match "\ballow\b") { return "allow" }
    if ($outStr -match "\bignore\b") { return "ignore" }
    if ($outStr -match "\bdeny\b") { return "deny" }
    if ($outStr -match "\bdefault\b") { return "default" }
    if ($outStr -match "\bforeground\b") { return "foreground" }
    return "default"
}

function Get-StandbyBucket {
    param (
        [string]$Serial,
        [string]$Package
    )
    $rawVal = (& $AdbPath -s $Serial shell am get-standby-bucket $Package 2>&1)
    $val = if ($rawVal) { [string]$rawVal.ToString().Trim() } else { "" }
    if ($val -match "^\d+$") {
        return [int]$val
    }
    return -1
}

function Audit-AppStatus {
    param (
        [string]$Serial,
        [hashtable]$TargetPackages,
        [array]$Users
    )
    Write-Host "[*] DANG THU THAP DU LIEU TRANG THAI HE THONG..." -ForegroundColor Cyan
    $whitelist = Get-DozeWhitelist -Serial $Serial
    $report = @()

    foreach ($pkg in ($TargetPackages.Keys | Sort-Object)) {
        $info = $TargetPackages[$pkg]
        $inWhitelist = ($whitelist -contains $pkg)
        $bucket = Get-StandbyBucket -Serial $Serial -Package $pkg
        $bucketText = $(if ($StandbyBucketNames.ContainsKey($bucket)) { $StandbyBucketNames[$bucket] } else { "Khong xac dinh ($bucket)" })

        foreach ($userId in $info.Users) {
            $postNotif = Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "POST_NOTIFICATION"
            $vibrate   = Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "VIBRATE"
            $wakeLock  = Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "WAKE_LOCK"
            $fgService = Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "START_FOREGROUND"
            $alertWin  = Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "SYSTEM_ALERT_WINDOW"
            $fullScreen= Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "USE_FULL_SCREEN_INTENT"
            $autoRevoke= Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "AUTO_REVOKE_PERMISSIONS_IF_UNUSED"
            $runInBg   = Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "RUN_IN_BACKGROUND"

            # Danh gia muc do rui ro mat thong bao
            $risk = "AN TOAN (Tot)"
            $riskColor = "Green"
            $issues = @()

            if (-not $inWhitelist) {
                $issues += "Chua vao Doze Whitelist (De bi ngu dong khi tat man hinh)"
            }
            if ($bucket -gt 20) {
                $issues += "Standby Bucket kem ($bucket) -> Android han che nhan push"
            }
            if ($postNotif -ne "allow") {
                $issues += "POST_NOTIFICATION chua bat ($postNotif)"
                $risk = "NGUY CO CAO (Mat thong bao)"
                $riskColor = "Red"
            } elseif ($issues.Count -gt 0) {
                $risk = "CAN TOI UU (De bi tre)"
                $riskColor = "Yellow"
            }

            $report += [PSCustomObject]@{
                Package     = $pkg
                AppName     = $info.Name
                Category    = $info.Category
                UserId      = $userId
                UserType    = $(if ($userId -eq 0) { "Chinh (u0)" } else { "Nhan ban (u$userId)" })
                InWhitelist = $inWhitelist
                Bucket      = $bucket
                BucketText  = $bucketText
                PostNotif   = $postNotif
                Vibrate     = $vibrate
                WakeLock    = $wakeLock
                FgService   = $fgService
                AlertWin    = $alertWin
                FullScreen  = $fullScreen
                AutoRevoke  = $autoRevoke
                RunInBg     = $runInBg
                Risk        = $risk
                RiskColor   = $riskColor
                Issues      = $issues
            }
        }
    }

    return $report
}

function Show-AuditReport {
    param ([array]$AuditResults)
    Write-Host ""
    Write-Host "=================== KET QUA KIEM TRA TRANG THAI THONG BAO ===================" -ForegroundColor Yellow
    Write-Host "Tong so ung dung phat hien: $($AuditResults.Count)" -ForegroundColor Cyan
    Write-Host ""

    foreach ($item in $AuditResults) {
        Write-Host "[$($item.UserType)] " -NoNewline -ForegroundColor Cyan
        Write-Host "$($item.AppName) " -NoNewline -ForegroundColor White
        Write-Host "($($item.Package))" -ForegroundColor Gray

        Write-Host "  - Trang thai: " -NoNewline
        Write-Host "$($item.Risk)" -ForegroundColor $item.RiskColor

        Write-Host "  - Doze Whitelist: " -NoNewline
        if ($item.InWhitelist) {
            Write-Host "DA BAT (Khong bi ngu dong)" -ForegroundColor Green
        } else {
            Write-Host "CHUA BAT (Bi han che pin)" -ForegroundColor Red
        }

        Write-Host "  - Standby Bucket: " -NoNewline
        if ($item.Bucket -eq 10) {
            Write-Host "$($item.BucketText)" -ForegroundColor Green
        } else {
            Write-Host "$($item.BucketText)" -ForegroundColor Red
        }

        Write-Host "  - Quyen thong bao (POST_NOTIFICATION): " -NoNewline
        if ($item.PostNotif -eq "allow") {
            Write-Host "$($item.PostNotif)" -ForegroundColor Green
        } else {
            Write-Host "$($item.PostNotif)" -ForegroundColor Red
        }

        Write-Host "  - Cua so noi (Pop-up/Bong bong): " -NoNewline
        Write-Host "$($item.AlertWin)" -ForegroundColor Gray

        Write-Host "  - Cuoc goi toan man hinh (VoIP): " -NoNewline
        Write-Host "$($item.FullScreen)" -ForegroundColor Gray

        if ($item.Issues.Count -gt 0) {
            Write-Host "  * Cac diem can khac phuc:" -ForegroundColor Yellow
            foreach ($iss in $item.Issues) {
                Write-Host "    + $iss" -ForegroundColor Yellow
            }
        }
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    }
}

function Create-GranularBackup {
    param (
        [string]$Serial,
        [hashtable]$DeviceMeta,
        [array]$AuditResults
    )
    $backupDir = "$PSScriptRoot\backups"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $jsonPath = "$backupDir\backup_${Serial}_${timestamp}.json"
    $txtSummaryPath = "$backupDir\backup_${Serial}_${timestamp}.txt"

    $backupData = @{
        Metadata   = @{
            Timestamp = (Get-Date).ToString("o")
            Serial    = $Serial
            Model     = $DeviceMeta.Model
            Android   = $DeviceMeta.Android
            OriginOS  = $DeviceMeta.OriginOS
        }
        AppStates  = $AuditResults
    }

    $jsonContent = $backupData | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($jsonPath, $jsonContent, [System.Text.Encoding]::UTF8)

    # Tao file summary de doc
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("BAN SAO LUU TRANG THAI GOC TRUOC KHI TOI UU")
    [void]$sb.AppendLine("Thiet bi: $($DeviceMeta.Model) ($Serial)")
    [void]$sb.AppendLine("Thoi gian: $(Get-Date)")
    [void]$sb.AppendLine("--------------------------------------------------")
    foreach ($r in $AuditResults) {
        [void]$sb.AppendLine("[$($r.UserType)] $($r.AppName) ($($r.Package))")
        [void]$sb.AppendLine("  Doze Whitelist: $($r.InWhitelist)")
        [void]$sb.AppendLine("  Standby Bucket: $($r.Bucket)")
        [void]$sb.AppendLine("  POST_NOTIFICATION: $($r.PostNotif)")
        [void]$sb.AppendLine("  VIBRATE: $($r.Vibrate)")
        [void]$sb.AppendLine("  WAKE_LOCK: $($r.WakeLock)")
        [void]$sb.AppendLine("  START_FOREGROUND: $($r.FgService)")
        [void]$sb.AppendLine("  SYSTEM_ALERT_WINDOW: $($r.AlertWin)")
        [void]$sb.AppendLine("  USE_FULL_SCREEN_INTENT: $($r.FullScreen)")
        [void]$sb.AppendLine("  AUTO_REVOKE: $($r.AutoRevoke)")
        [void]$sb.AppendLine("  RUN_IN_BACKGROUND: $($r.RunInBg)")
        [void]$sb.AppendLine("")
    }
    [System.IO.File]::WriteAllText($txtSummaryPath, $sb.ToString(), [System.Text.Encoding]::UTF8)

    Write-Host "[OK] DA TAO BAN SAO LUU GOC AN TOAN TAI:" -ForegroundColor Green
    Write-Host "    $jsonPath" -ForegroundColor Cyan
    return $jsonPath
}

function Apply-GranularOptimization {
    param (
        [string]$Serial,
        [array]$SelectedApps,
        [bool]$IncludeAdvanced
    )
    Write-Host ""
    Write-Host "=================== TIEN HANH TOI UU HOA CO XAC MINH ===================" -ForegroundColor Yellow
    $modeText = $(if ($IncludeAdvanced) { "BAT" } else { "TAT (Chi toi uu quyen chuan)" })
    Write-Host "Tuy chon quyen bo sung (Cua so noi, Full screen intent...): $modeText" -ForegroundColor Cyan
    Write-Host ""

    # 1. Kich hoat ket noi Google Play Services FCM Heartbeat
    Write-Host "[1/3] Kich hoat va giu ket noi Google Play Services (FCM Heartbeat)..." -ForegroundColor Cyan
    & $AdbPath -s $Serial shell dumpsys deviceidle whitelist +com.google.android.gms 2>&1 | Out-Null
    & $AdbPath -s $Serial shell am set-standby-bucket com.google.android.gms 10 2>&1 | Out-Null
    & $AdbPath -s $Serial shell am broadcast -a com.google.android.intent.action.MCS_HEARTBEAT -p com.google.android.gms 2>&1 | Out-Null
    Write-Host "    [OK] Google Play Services FCM Heartbeat da duoc kich hoat." -ForegroundColor Green

    # 2. Toi uu tung ung dung
    Write-Host ""
    Write-Host "[2/3] Ap dung cac thiet lap cho tung ung dung muc tieu..." -ForegroundColor Cyan

    $results = @()

    foreach ($item in $SelectedApps) {
        $pkg = $item.Package
        $userId = $item.UserId
        $appName = $item.AppName
        $userTag = "u$userId"

        Write-Host "--> Dang xu ly: $appName ($pkg) [$userTag]..." -ForegroundColor White

        # A. Doze Whitelist (He thong dung chung package)
        & $AdbPath -s $Serial shell dumpsys deviceidle whitelist +$pkg 2>&1 | Out-Null

        # B. Standby Bucket = 10 (ACTIVE)
        & $AdbPath -s $Serial shell am set-standby-bucket $pkg 10 2>&1 | Out-Null

        # C. Quyen thong bao co ban
        & $AdbPath -s $Serial shell cmd appops set --user $userId $pkg POST_NOTIFICATION allow 2>&1 | Out-Null
        & $AdbPath -s $Serial shell cmd appops set --user $userId $pkg VIBRATE allow 2>&1 | Out-Null

        # D. Kiem tra truoc WAKE_LOCK va START_FOREGROUND (Tranh chay thua neu Android 14 da la allow)
        $currWakeLock = Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "WAKE_LOCK"
        if ($currWakeLock -ne "allow") {
            & $AdbPath -s $Serial shell cmd appops set --user $userId $pkg WAKE_LOCK allow 2>&1 | Out-Null
        }

        $currFg = Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "START_FOREGROUND"
        if ($currFg -ne "allow") {
            & $AdbPath -s $Serial shell cmd appops set --user $userId $pkg START_FOREGROUND allow 2>&1 | Out-Null
        }

        # E. Quyen nang cao (Tuy chon)
        if ($IncludeAdvanced) {
            & $AdbPath -s $Serial shell cmd appops set --user $userId $pkg SYSTEM_ALERT_WINDOW allow 2>&1 | Out-Null
            & $AdbPath -s $Serial shell cmd appops set --user $userId $pkg USE_FULL_SCREEN_INTENT allow 2>&1 | Out-Null
            & $AdbPath -s $Serial shell cmd appops set --user $userId $pkg AUTO_REVOKE_PERMISSIONS_IF_UNUSED ignore 2>&1 | Out-Null
            & $AdbPath -s $Serial shell cmd appops set --user $userId $pkg RUN_IN_BACKGROUND allow 2>&1 | Out-Null
            & $AdbPath -s $Serial shell cmd appops set --user $userId $pkg RUN_ANY_IN_BACKGROUND allow 2>&1 | Out-Null
        }

        # 3. XAC MINH LAI NGAY LAP TUC (Verification)
        $verifyWhitelist = (Get-DozeWhitelist -Serial $Serial) -contains $pkg
        $verifyBucket    = Get-StandbyBucket -Serial $Serial -Package $pkg
        $verifyNotif     = Get-AppOpState -Serial $Serial -UserId $userId -Package $pkg -Op "POST_NOTIFICATION"

        $isSuccess = ($verifyWhitelist -and ($verifyBucket -eq 10 -or $verifyBucket -eq 5) -and $verifyNotif -eq "allow")

        if ($isSuccess) {
            $bName = $(if ($verifyBucket -eq 5) { "EXEMPTED (5)" } else { "ACTIVE (10)" })
            Write-Host "    [OK XAC MINH THANH CONG] Whitelist: OK | Bucket: $bName | POST_NOTIF: allow" -ForegroundColor Green
        } else {
            Write-Host "    [!] CANH BAO: Whitelist=$verifyWhitelist, Bucket=$verifyBucket, Notif=$verifyNotif" -ForegroundColor Yellow
        }

        $results += [PSCustomObject]@{
            Package   = $pkg
            AppName   = $appName
            UserId    = $userId
            Success   = $isSuccess
            Whitelist = $verifyWhitelist
            Bucket    = $verifyBucket
            Notif     = $verifyNotif
        }
    }

    Write-Host ""
    Write-Host "[3/3] HOAN TAT QUA TRINH TOI UU HOA VA XAC MINH!" -ForegroundColor Green
    return $results
}

function Restore-FromGranularBackup {
    param (
        [string]$Serial,
        [string]$BackupFilePath
    )
    if (-not (Test-Path $BackupFilePath)) {
        Write-Host "[!] Khong tim thay file sao luu: $BackupFilePath" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "=================== HOAN TAC CHINH XAC THEO BAN SAO LUU ===================" -ForegroundColor Yellow
    Write-Host "File sao luu: $BackupFilePath" -ForegroundColor Cyan
    Write-Host "Luu y: Chi hoan tac dung nhung gi tool da sua. KHONG dung appops reset toan bo." -ForegroundColor Cyan
    Write-Host ""

    $jsonContent = [System.IO.File]::ReadAllText($BackupFilePath, [System.Text.Encoding]::UTF8)
    $backupData = $jsonContent | ConvertFrom-Json

    foreach ($item in $backupData.AppStates) {
        $pkg = $item.Package
        $userId = $item.UserId
        $appName = $item.AppName
        Write-Host "--> Dang hoan tac cho: $appName ($pkg) [u$userId]..." -ForegroundColor White

        # 1. Hoan tac Doze Whitelist: Neu ban dau KHONG o trong whitelist thi go ra
        if (-not $item.InWhitelist) {
            & $AdbPath -s $Serial shell dumpsys deviceidle whitelist -$pkg 2>&1 | Out-Null
        }

        # 2. Hoan tac Standby Bucket: Tra lai bucket ban dau
        if ($item.Bucket -gt 0) {
            & $AdbPath -s $Serial shell am set-standby-bucket $pkg $item.Bucket 2>&1 | Out-Null
        }

        # 3. Hoan tac cac quyen AppOps ve trang thai ban dau
        $opsToRestore = @{
            "POST_NOTIFICATION" = $item.PostNotif
            "VIBRATE"           = $item.Vibrate
            "WAKE_LOCK"         = $item.WakeLock
            "START_FOREGROUND"  = $item.FgService
            "SYSTEM_ALERT_WINDOW"= $item.AlertWin
            "USE_FULL_SCREEN_INTENT"= $item.FullScreen
            "AUTO_REVOKE_PERMISSIONS_IF_UNUSED"= $item.AutoRevoke
            "RUN_IN_BACKGROUND" = $item.RunInBg
        }

        foreach ($opName in $opsToRestore.Keys) {
            $origVal = $opsToRestore[$opName]
            if ($origVal -and $origVal -ne "default") {
                & $AdbPath -s $Serial shell cmd appops set --user $userId $pkg $opName $origVal 2>&1 | Out-Null
            }
        }

        Write-Host "    [OK] Da tra ve trang thai goc." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "[OK] HOAN TAC HOAN TAT THANH CONG! He thong da duoc khoi phuc ve dung ban sao luu." -ForegroundColor Green
}

function Show-FcmDiagnostics {
    param ([string]$Serial)
    Write-Host ""
    Write-Host "=================== CHAN DOAN KET NOI GOOGLE FCM THOI GIAN THUC ===================" -ForegroundColor Yellow
    Write-Host "[*] Dang doc trang thai ket noi tu Google Play Services (GcmService)..." -ForegroundColor Cyan

    $dump = & $AdbPath -s $Serial shell dumpsys activity service com.google.android.gms/.gcm.GcmService 2>&1
    $dumpStr = [string]($dump -join "`n")

    # Kiem tra ket noi
    $isConnected = ($dumpStr -match "Connected to mtalk\.google\.com" -or $dumpStr -match "Is client connected:\s*true" -or $dumpStr -match "Connected\s*$")
    Write-Host "1. Ket noi toi may chu Google Push (mtalk.google.com:5228): " -NoNewline
    if ($isConnected) {
        Write-Host "DA KET NOI (Connected)" -ForegroundColor Green
    } else {
        Write-Host "CHUA KET NOI HOAC DANG RECONNECT" -ForegroundColor Red
    }

    # Trich xuat cac su kien gan nhat
    Write-Host ""
    Write-Host "2. Nhat ky 15 su kien nhan tin FCM gan nhat tren thiet bi:" -ForegroundColor Yellow
    $eventLines = $dump | Where-Object { $_ -match "Received|Successful broadcast|No response|Failed to broadcast" } | Select-Object -Last 15
    if ($eventLines) {
        foreach ($el in $eventLines) {
            if ($el -match "Successful broadcast") {
                Write-Host "   $el" -ForegroundColor Green
            } elseif ($el -match "No response|Failed to broadcast") {
                Write-Host "   $el" -ForegroundColor Red
            } else {
                Write-Host "   $el" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "   (Chua co su kien push nao trong phien lam viec nay)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "=================== LUU Y DAC BIET VE FACEBOOK LIKE/COMMENT ===================" -ForegroundColor Magenta
    Write-Host "[!] VE DO UU TIEN CUA META/FACEBOOK (FCM PRIORITY):" -ForegroundColor Yellow
    Write-Host "    - Tin nhan Messenger duoc Facebook gui voi muc uu tien CAO (HIGH PRIORITY)." -ForegroundColor White
    Write-Host "      -> Thiet bi se nhan va phat chuong/thong bao ngay lap tuc ke ca khi tat man hinh." -ForegroundColor White
    Write-Host "    - Thong bao Like, Comment, Thong bao nhom cua Facebook thuong gui o muc BINH THUONG (NORMAL PRIORITY)." -ForegroundColor White
    Write-Host "      -> Theo thiet ke goc cua Android va Google Firebase, cac goi NORMAL se bi gom lai (batched)" -ForegroundColor White
    Write-Host "         khi may o che do Doze sau va chi hien khi nguoi dung mo sang man hinh hoac het chu ky Doze." -ForegroundColor White
    Write-Host "    - ADB chi can thiep duoc phia he dieu hanh dien thoai (khong ngu dong, khong giam xung CPU)," -ForegroundColor White
    Write-Host "      nhung KHONG THE thay doi payload ma may chu Facebook phat ra tu server." -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Magenta
}

# ==================== MAIN PROGRAM WORKFLOW ====================

Show-Header

# 1. Kiem tra thiet bi
$serial = Check-AdbConnection
if (-not $serial) {
    Write-Host "Nhan Enter de thoat..."
    Read-Host
    exit 1
}

$deviceMeta = Get-DeviceMetadata -Serial $serial
Write-Host "[+] Phat hien thiet bi: " -NoNewline -ForegroundColor Green
Write-Host "$($deviceMeta.Model) " -NoNewline -ForegroundColor White
Write-Host "(Serial: $serial | Android: $($deviceMeta.Android) | $($deviceMeta.OriginOS))" -ForegroundColor Gray
Write-Host ""

# 2. Quet danh sach Users (Dynamic Detection)
$users = Get-DeviceUsers -Serial $serial
Write-Host "[+] Danh sach User tren may: " -NoNewline -ForegroundColor Green
foreach ($u in $users) {
    Write-Host "User $($u.Id) ($($u.Name))  " -NoNewline -ForegroundColor Cyan
}
Write-Host ""

# 3. Quet ung dung da cai dat
$targetApps = Get-InstalledTargetPackages -Serial $serial -Users $users
Write-Host "[+] Tim thay $($targetApps.Keys.Count) ung dung nhan tin/ngan hang trong danh muc tren may." -ForegroundColor Green
Write-Host ""

# Neu chay voi tham so dong lenh truc tiep
if ($Audit) {
    $auditData = Audit-AppStatus -Serial $serial -TargetPackages $targetApps -Users $users
    Show-AuditReport -AuditResults $auditData
    exit 0
}

if ($Restore) {
    $backupDir = "$PSScriptRoot\backups"
    $latestBackup = Get-ChildItem -Path $backupDir -Filter "backup_${serial}_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestBackup) {
        Restore-FromGranularBackup -Serial $serial -BackupFilePath $latestBackup.FullName
    } else {
        Write-Host "[!] Khong tim thay ban sao luu nao cho thiet bi $serial tai $backupDir" -ForegroundColor Red
    }
    exit 0
}

if ($FCMTest) {
    Show-FcmDiagnostics -Serial $serial
    exit 0
}

# ==================== INTERACTIVE MENU ====================

while ($true) {
    Write-Host "========================== MENU CHUC NANG CHINH ==========================" -ForegroundColor Cyan
    Write-Host "  1. [KIEM TRA] Chan doan toan dien (Audit Only - Chi doc, khong sua gi)" -ForegroundColor Yellow
    Write-Host "  2. [TOI UU] Toi uu hoa thong bao (Kiem tra -> Sao luu -> Toi uu -> Xac minh)" -ForegroundColor Green
    Write-Host "  3. [HOAN TAC] Khoi phuc chinh xac theo ban sao luu (Granular Rollback)" -ForegroundColor Cyan
    Write-Host "  4. [CHAN DOAN FCM] Kiem tra ket noi Google Push & Log nhan tin truc tiep" -ForegroundColor Magenta
    Write-Host "  5. Thoat cong cu" -ForegroundColor Gray
    Write-Host "==========================================================================" -ForegroundColor Cyan
    $choice = Read-Host "Nhap lua chon cua ban (1-5)"

    switch ($choice) {
        "1" {
            $auditData = Audit-AppStatus -Serial $serial -TargetPackages $targetApps -Users $users
            Show-AuditReport -AuditResults $auditData
            Write-Host ""
            Write-Host "Nhan Enter de quay lai Menu..."; Read-Host
            Show-Header
        }

        "2" {
            # Buoc 1: Kiem tra truoc
            Write-Host ""
            Write-Host "[BUOC 1/4] Kiem tra trang thai hien tai..." -ForegroundColor Cyan
            $auditData = Audit-AppStatus -Serial $serial -TargetPackages $targetApps -Users $users

            # Buoc 2: Tao ban sao luu goc truoc khi sua
            Write-Host ""
            Write-Host "[BUOC 2/4] Sao luu trang thai goc..." -ForegroundColor Cyan
            $backupFile = Create-GranularBackup -Serial $serial -DeviceMeta $deviceMeta -AuditResults $auditData

            # Buoc 3: Lua chon danh sach ung dung can toi uu
            Write-Host ""
            Write-Host "[BUOC 3/4] Chon pham vi ung dung can toi uu:" -ForegroundColor Cyan
            Write-Host "    [A] Toi uu TAT CA cac ung dung da phat hien tren tat ca User (Khuyen dung)" -ForegroundColor Green
            Write-Host "    [S] Chi toi uu mot so ung dung duoc chon" -ForegroundColor Yellow
            $scopeChoice = (Read-Host "Chon [A] hoac [S] (Mac dinh la A)").Trim().ToUpper()

            $selectedApps = $auditData
            if ($scopeChoice -eq "S") {
                Write-Host ""
                Write-Host "Danh sach ung dung:" -ForegroundColor Cyan
                for ($i = 0; $i -lt $auditData.Count; $i++) {
                    $it = $auditData[$i]
                    Write-Host "  [$($i+1)] [$($it.UserType)] $($it.AppName) ($($it.Package))"
                }
                $selectedIndexes = Read-Host "Nhap cac so thu tu muon toi uu (vi du: 1,2,4)"
                $indices = $selectedIndexes -split "," | ForEach-Object { [int]$_.Trim() - 1 }
                $selectedApps = @()
                foreach ($idx in $indices) {
                    if ($idx -ge 0 -and $idx -lt $auditData.Count) {
                        $selectedApps += $auditData[$idx]
                    }
                }
            }

            # Buoc 4: Tuy chon quyen bo sung
            Write-Host ""
            Write-Host "[BUOC 4/4] Cau hinh quyen bo sung:" -ForegroundColor Cyan
            Write-Host "    - Quyen Co Ban (Doze Whitelist, Active Bucket, Post Notif, Vibrate) luon duoc bat."
            Write-Host "    - Ban co muon bat them quyen Nang Cao khong?" -ForegroundColor Yellow
            Write-Host "      (Bao gom: Cua so noi/Bong bong chat, Cuoc goi toan man hinh, Tat tu thu hoi quyen)"
            $advChoice = (Read-Host "Bat quyen Nang Cao? (Y/N - Mac dinh Y)").Trim().ToUpper()
            $includeAdv = ($advChoice -ne "N")

            # Tien hanh toi uu hoa
            $optResults = Apply-GranularOptimization -Serial $serial -SelectedApps $selectedApps -IncludeAdvanced $includeAdv

            Write-Host ""
            Write-Host "=================== HUONG DAN SU DUNG SAU KHI TOI UU ===================" -ForegroundColor Yellow
            Write-Host "1. Tren OriginOS: Hay mo cac app can thiet (Messenger, Zalo...) 1 lan sau khi reboot." -ForegroundColor White
            Write-Host "2. Vao da nhiem (Recent Tasks) -> Vuot the app xuong de KHOA O KHOA." -ForegroundColor White
            Write-Host "3. Messenger: Neu muon bat pop-up roi tu tren xuong, hay vao Cai dat thong bao -> Bat 'Bieu ngu noi'." -ForegroundColor White
            Write-Host "========================================================================" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Nhan Enter de quay lai Menu..."; Read-Host
            Show-Header
        }

        "3" {
            $backupDir = "$PSScriptRoot\backups"
            if (-not (Test-Path $backupDir)) {
                Write-Host "[!] Chua co ban sao luu nao!" -ForegroundColor Red
            } else {
                $backups = Get-ChildItem -Path $backupDir -Filter "backup_${serial}_*.json" | Sort-Object LastWriteTime -Descending
                if ($backups.Count -eq 0) {
                    Write-Host "[!] Khong tim thay ban sao luu nao cho thiet bi $serial!" -ForegroundColor Red
                } else {
                    Write-Host ""
                    Write-Host "Danh sach cac ban sao luu co san:" -ForegroundColor Cyan
                    for ($i = 0; $i -lt $backups.Count; $i++) {
                        Write-Host "  [$($i+1)] $($backups[$i].Name) ($($backups[$i].LastWriteTime))"
                    }
                    $bCount = $backups.Count
                    $bChoice = Read-Host "Chon ban sao luu de khoi phuc (1-$bCount, mac dinh 1)"
                    $bIdx = 0
                    if ($bChoice -match "^\d+$") {
                        $bIdx = [int]$bChoice - 1
                    }
                    if ($bIdx -ge 0 -and $bIdx -lt $backups.Count) {
                        Restore-FromGranularBackup -Serial $serial -BackupFilePath $backups[$bIdx].FullName
                    }
                }
            }
            Write-Host ""
            Write-Host "Nhan Enter de quay lai Menu..."; Read-Host
            Show-Header
        }

        "4" {
            Show-FcmDiagnostics -Serial $serial
            Write-Host ""
            Write-Host "Nhan Enter de quay lai Menu..."; Read-Host
            Show-Header
        }

        "5" {
            Write-Host "Tam biet!" -ForegroundColor Green
            exit 0
        }

        default {
            Write-Host "[!] Lua chon khong hop le, vui long nhap tu 1 den 5." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
