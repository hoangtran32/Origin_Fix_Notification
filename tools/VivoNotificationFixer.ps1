<#
.SYNOPSIS
    Vivo OriginOS: kiem tra, toi uu co chon loc, xac minh va hoan tac theo nhat ky.
.DESCRIPTION
    PowerShell 5.1+. Audit/FCM/PlanOnly chi doc dien thoai. Fix/Reapply/Restore
    chi ghi khi co trang thai goc va UID hop le. Khong cam ket sua moi loi thong bao.
#>
[CmdletBinding()]
param(
    [switch]$Audit, [switch]$Fix, [switch]$Restore, [switch]$FCMTest,
    [string[]]$TargetPackage, [string[]]$UserId, [string]$Serial,
    [switch]$AdvancedPermissions, [switch]$Calls, [switch]$Overlay,
    [switch]$IncludeGoogleServices, [switch]$NoPrompt, [switch]$PlanOnly,
    [switch]$OpenSettings, [switch]$Reapply, [string]$BackupFile
)
$script:ToolRoot = $PSScriptRoot
$script:AdbPath = 'adb'
$script:LastUserScanResults = @()
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'adb.exe')) { $script:AdbPath = Join-Path $PSScriptRoot 'adb.exe' }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot 'NotificationState.ps1')
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
    Write-Host "`n=== VIVO ORIGINOS - KIEM TRA / TOI UU / HOAN TAC ===" -ForegroundColor Cyan
}

function Select-Device {
    param([string]$RequestedSerial, [bool]$NonInteractive)
    $r = Invoke-Adb '' @('devices','-l')
    if (-not $r.Success) { throw "ADB: $($r.Output)" }
    $devices = @([regex]::Matches($r.StdOut, '(?m)^(\S+)\s+device(?:\s.*)?$') | ForEach-Object { $_.Groups[1].Value })
    if ($RequestedSerial) {
        if ($devices -cnotcontains $RequestedSerial) { throw 'Serial khong ket noi/khong duoc cap phep.' }
        return $RequestedSerial
    }
    if ($devices.Count -eq 0) { throw 'Khong co thiet bi ADB. Kiem tra cap/driver, USB debugging va popup Cho phep (unauthorized).' }
    if ($devices.Count -eq 1) { return $devices[0] }
    if ($NonInteractive) { throw 'Co nhieu dien thoai. Chi dinh -Serial.' }
    for ($i=0; $i -lt $devices.Count; $i++) { Write-Host "[$($i+1)] $($devices[$i])" }
    $answer = Read-Host 'Chon dien thoai'
    $index = 0
    if (-not [int]::TryParse($answer, [ref]$index) -or $index -lt 1 -or $index -gt $devices.Count) { throw 'Lua chon dien thoai khong hop le.' }
    return $devices[$index-1]
}

function Get-DeviceMetadata {
    param([string]$Serial)
    $values = @{}
    foreach ($pair in @(@('Model','ro.product.model'), @('Android','ro.build.version.release'), @('OriginOS','ro.vivo.os.build.display.id'), @('ApiLevel','ro.build.version.sdk'))) {
        $r = Invoke-Adb $Serial @('shell','getprop',$pair[1])
        if (-not $r.Success) { throw "Khong doc duoc $($pair[1]): $($r.Output)" }
        $values[$pair[0]]=$r.StdOut.Trim()
    }
    if ($values.ApiLevel -notmatch '^\d+$') { throw 'Khong doc duoc Android API level.' }
    $values.ApiLevel=[int]$values.ApiLevel; $values.Serial=$Serial
    return $values
}

function Get-DeviceUsers {
    param([string]$Serial)
    $r = Invoke-Adb $Serial @('shell','pm','list','users')
    if (-not $r.Success) { throw "Khong doc duoc user: $($r.Output)" }
    $users = @([regex]::Matches($r.StdOut, 'UserInfo\{(\d+):([^:]+):') | ForEach-Object { [PSCustomObject]@{ Id=[int]$_.Groups[1].Value; Name=$_.Groups[2].Value } })
    if ($users.Count -eq 0) { throw 'Danh sach user khong xac dinh; khong tu gia dinh user 0.' }
    return $users
}

function Get-InstalledTargets {
    param([string]$Serial, [array]$Users, [string[]]$Packages, [int[]]$RequestedUsers)
    $script:LastUserScanResults = @()
    $hadPackageFilter=($Packages.Count -gt 0)
    $Packages=@($Packages | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($hadPackageFilter -and $Packages.Count -eq 0) { throw 'Danh sach package rong/khong hop le.' }
    foreach ($pkg in $Packages) { if ($pkg -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$') { throw "Package khong hop le: $pkg" } }
    foreach ($id in $RequestedUsers) { if ($id -lt 0 -or $Users.Id -notcontains $id) { throw "User khong ton tai: $id" } }
    $targets = @()
    $scannedUsers = 0
    foreach ($u in $Users) {
        if ($RequestedUsers.Count -gt 0 -and $RequestedUsers -notcontains $u.Id) { continue }
        $r = Invoke-Adb $Serial @('shell','pm','list','packages','--user',"$($u.Id)")
        if (-not $r.Success) {
            # Detect the actual denial, not a hard-coded OEM user ID. Other ADB
            # failures (disconnects, timeouts, unknown errors) must still stop.
            $denied = $r.Status -eq 'Failed' -and $r.Output -match ('(?im)^\s*(?:Error:\s*)?Shell does not have permission to access user\s+' + $u.Id + '\b')
            $scanStatus = $r.Status
            if ($denied) { $scanStatus = 'AccessDenied' }
            $script:LastUserScanResults += [PSCustomObject]@{ UserId=$u.Id; UserName=$u.Name; Status=$scanStatus; Detail=$r.Output; Query=$r }
            if ($denied -and $RequestedUsers.Count -eq 0) {
                Write-Warning "Bo qua user $($u.Id) ($($u.Name)): ADB khong co quyen truy cap. App cua user nay chua duoc kiem tra/toi uu; tiep tuc voi user truy cap duoc."
                continue
            }
            throw "Khong quet duoc app user $($u.Id) ($($u.Name)): $($r.Output)"
        }
        $scannedUsers++
        $script:LastUserScanResults += [PSCustomObject]@{ UserId=$u.Id; UserName=$u.Name; Status='Accessible'; Detail=''; Query=$r }
        foreach ($line in ($r.StdOut -split '\r?\n')) {
            if ($line -notmatch '^package:([\w.]+)\s*$') { continue }
            $pkg=$matches[1]
            if (($Packages.Count -gt 0 -and $Packages -contains $pkg) -or ($Packages.Count -eq 0 -and $KnownAppCatalog.ContainsKey($pkg))) {
                $name=$pkg
                if ($KnownAppCatalog.ContainsKey($pkg)) { $name=$KnownAppCatalog[$pkg].Name }
                $uid = Get-PackageUid $Serial $u.Id $pkg
                $targets += [PSCustomObject]@{ Package=$pkg; AppName=$name; UserId=$u.Id; UserName=$u.Name; Uid=$uid.Value; UidStatus=$uid.Status; GoogleOnly=$false }
            }
        }
    }
    if ($scannedUsers -eq 0) { throw 'Khong co user nao cho phep ADB quet ung dung. Khong the kiem tra/toi uu app; kiem tra cai dat tren dien thoai.' }
    foreach ($pkg in $Packages) {
        if ($targets.Package -notcontains $pkg) {
            $skipped = @($script:LastUserScanResults | Where-Object { $_.Status -eq 'AccessDenied' } | ForEach-Object { $_.UserId })
            if ($skipped.Count -gt 0) { throw "Khong tim thay app trong cac user da quet: $pkg. User chua quet do thieu quyen ADB: $($skipped -join ',')." }
            throw "Khong tim thay app trong pham vi user: $pkg"
        }
    }
    return @($targets | Sort-Object Package,UserId -Unique)
}

function Select-Targets {
    param([array]$Targets)
    for ($i=0; $i -lt $Targets.Count; $i++) { $t=$Targets[$i]; Write-Host "[$($i+1)] $($t.AppName) [u$($t.UserId): $($t.UserName)] $($t.Package)" }
    $answer = (Read-Host 'Chon so, vi du 1,3 (A = tat ca; Enter = huy)').Trim()
    if (-not $answer) { return @() }
    if ($answer -eq 'A') { return $Targets }
    $selected=@()
    foreach ($token in ($answer -split ',')) {
        $number=0
        if (-not [int]::TryParse($token.Trim(), [ref]$number) -or $number -lt 1 -or $number -gt $Targets.Count) { throw "So thu tu khong hop le: $token" }
        $selected += $Targets[$number-1]
    }
    return @($selected | Sort-Object Package,UserId -Unique)
}

function Format-State {
    param($State)
    if ($State.Status -eq 'Known') { return ($State.Value | ConvertTo-Json -Compress -Depth 4) }
    return "[$($State.Status)] $($State.Detail)"
}

function Audit-AppStatus {
    param([string]$Serial, [array]$Targets, [hashtable]$Metadata)
    $rows=@()
    $doze=Get-DozeWhitelist $Serial; $net=Get-NetpolicyWhitelist $Serial
    $saver=Invoke-Adb $Serial @('shell','cmd','netpolicy','get','restrict-background')
    $dnd=Invoke-Adb $Serial @('shell','settings','get','global','zen_mode')
    foreach ($t in $Targets) {
        $bucket=Get-StandbyBucket $Serial $t.UserId $t.Package
        $details=Get-PackageDetails $Serial $t.UserId $t.Package $Metadata.ApiLevel
        $ops=[ordered]@{}
        foreach ($op in @('POST_NOTIFICATION','RUN_IN_BACKGROUND','RUN_ANY_IN_BACKGROUND','VIBRATE','WAKE_LOCK','START_FOREGROUND','SYSTEM_ALERT_WINDOW','USE_FULL_SCREEN_INTENT','AUTO_REVOKE_PERMISSIONS_IF_UNUSED')) { $ops[$op]=Get-AppOpState $Serial $t.UserId $t.Package $op }
        $issues=@()
        if ($details.Status -ne 'Known') { $issues += 'Khong doc duoc trang thai Package/User.' }
        elseif ($details.Value.Stopped) { $issues += 'APP DANG STOPPED: mo app nay mot lan tren dung user, roi thu nhan tin lai.' }
        if ($details.Status -eq 'Known' -and $details.Value.Enabled -in @(2,3,4)) { $issues += 'App dang bi tat (disabled); kiem tra tren dien thoai.' }
        if ($details.Status -eq 'Known' -and $details.Value.Permission.Status -eq 'Known' -and -not $details.Value.Permission.Value.Granted) { $issues += 'Chua cap quyen runtime POST_NOTIFICATIONS.' }
        if ($ops.POST_NOTIFICATION.Status -eq 'Known' -and $ops.POST_NOTIFICATION.Value -in @('deny','ignore','errored')) { $issues += 'AppOp thong bao dang chan.' }
        if ($bucket.Status -eq 'Known' -and $bucket.Value -gt 20) { $issues += "Standby bucket dang han che: $($bucket.Value)." }
        if ($doze.Status -eq 'Known' -and $doze.Value -notcontains $t.Package) { $issues += 'Chua mien tru full Doze.' }
        $netState=New-State $net.Status ($net.Value -contains $t.Uid) $net.Detail
        if ($null -eq $t.Uid) { $netState=New-State 'Unknown' $null 'Thieu UID; khong the xac minh.' }
        $rows += [PSCustomObject]@{ Package=$t.Package; AppName=$t.AppName; UserId=$t.UserId; UserName=$t.UserName; Uid=$t.Uid; Bucket=$bucket; Doze=(New-State $doze.Status ($doze.Value -contains $t.Package) $doze.Detail); NetPolicy=$netState; Details=$details; AppOps=$ops; Issues=$issues }
    }
    [PSCustomObject]@{ Metadata=$Metadata; CapturedAt=(Get-Date).ToString('o'); UserScan=@($script:LastUserScanResults); UserScanComplete=(@($script:LastUserScanResults | Where-Object { $_.Status -ne 'Accessible' }).Count -eq 0); DataSaver=$saver; Dnd=$dnd; Apps=$rows; DeliveryTest='Chua kiem chung nhan tin nen'; ManualChecks=@('Tu khoi dong/khoi dong lien ket','Pin nen cao/khong han che','Kenh thong bao, man hinh khoa, bieu ngu','Thong bao trong app/tung cuoc tro chuyen','Thu Wi-Fi, di dong, chuyen mang va sau reboot') }
}

function Show-AuditReport {
    param($Report)
    foreach ($scan in $Report.UserScan) {
        if ($scan.Status -ne 'Accessible') { Write-Host "[CHUA KIEM TRA] User $($scan.UserId) ($($scan.UserName)): $($scan.Detail)" -ForegroundColor Yellow }
    }
    Write-Host "Data Saver: $($Report.DataSaver.Output) | Khong lam phien (zen_mode): $($Report.Dnd.Output)"
    Write-Host 'NetPolicy la mien tru Data Saver tren mang tinh phi; chua chung minh sua duoc socket MQTT.' -ForegroundColor Yellow
    foreach ($r in $Report.Apps) {
        Write-Host "`n$($r.AppName) [u$($r.UserId): $($r.UserName)] UID=$($r.Uid)" -ForegroundColor Cyan
        Write-Host "  Doze: $(Format-State $r.Doze) | Bucket: $(Format-State $r.Bucket) | NetPolicy: $(Format-State $r.NetPolicy)"
        if ($r.Details.Status -eq 'Known') { Write-Host "  POST_NOTIFICATIONS: $(Format-State $r.Details.Value.Permission) | Stopped=$($r.Details.Value.Stopped)" }
        foreach ($op in $r.AppOps.Keys) { Write-Host "  $op : $(Format-State $r.AppOps[$op])" }
        foreach ($issue in $r.Issues) { Write-Host "  [CAN KIEM TRA] $issue" -ForegroundColor Yellow }
    }
    Write-Host "`nNhan tin nen: $($Report.DeliveryTest). Kenh thong bao va cai dat OriginOS can kiem tra tren may."
}

function Save-Report {
    param([string]$Serial, [string]$Kind, $Data)
    $safeSerial=$Serial -replace '[^\w.-]', '_'
    $path=Join-Path $script:ToolRoot ('reports\' + $Kind + '_' + $safeSerial + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.json')
    Save-JsonAtomic $path $Data
    Write-Host "Bao cao: $path" -ForegroundColor Cyan
}

function Show-ChangePlan {
    param([array]$Plan)
    Write-Host "`n=== THAY DOI DE XUAT ===" -ForegroundColor Cyan
    foreach ($e in $Plan) {
        Write-Host "[$($e.Status)] $($e.Package) [u$($e.UserId)] $($e.Kind) $($e.Op): $($e.Before | ConvertTo-Json -Compress) -> $($e.Desired | ConvertTo-Json -Compress) $($e.Detail)"
    }
    Write-Host 'Doze dung chung package cho cac user; NetPolicy dung chung UID. Quyen bo sung chi ap dung khi da chon.' -ForegroundColor Yellow
}

function Show-ManualGuidance {
    Write-Host "`nTren OriginOS: bat Tu khoi dong/Khoi dong lien ket, cho phep pin nen cao, khoa the da nhiem neu may ho tro."
    Write-Host 'Kiem tra kenh thong bao, man hinh khoa, bieu ngu, Khong lam phien va cai dat thong bao ben trong app.'
    Write-Host 'Sau reboot: kiem tra lai, mo app can nhan tin mot lan neu dang stopped; dung muc 7 de ap dung lai phan bi doi.'
    Write-Host 'Thu truoc/sau: tat man hinh 15-30 phut; Wi-Fi, di dong, chuyen mang; tung tai khoan goc/nhan ban.'
    Write-Host 'Ghi gio gui va gio thong bao xuat hien; lay Audit/FCM truoc khi mo app. Thoi gian broadcast FCM khong phai do tre nhan tin.'
}

function Invoke-FixFlow {
    param([string]$Serial, [array]$Targets, [hashtable]$Metadata, [bool]$NonInteractive, [bool]$PreviewOnly, [bool]$EnableCalls, [bool]$EnableOverlay, [bool]$Advanced, [bool]$GoogleServices)
    if ($Targets.Count -eq 0) { throw 'Chua chon app/user.' }
    foreach ($target in $Targets) {
        $details=Get-PackageDetails $Serial $target.UserId $target.Package $Metadata.ApiLevel
        if ($details.Status -ne 'Known') { Write-Host "[CAN KIEM TRA] $($target.Package) [u$($target.UserId)]: khong doc duoc trang thai app." -ForegroundColor Yellow }
        elseif ($details.Value.Stopped) { Write-Host "[CAN THAO TAC] $($target.Package) [u$($target.UserId)] dang stopped. Mo dung app nay mot lan tren dien thoai, roi thu nhan tin." -ForegroundColor Yellow }
        if ($details.Status -eq 'Known' -and $details.Value.Enabled -in @(2,3,4)) { Write-Host "[CAN THAO TAC] $($target.Package) [u$($target.UserId)] dang disabled; kiem tra cai dat app." -ForegroundColor Yellow }
    }
    $plan=@(New-ChangePlan $Serial $Targets $Metadata.ApiLevel $EnableCalls $EnableOverlay $Advanced $GoogleServices)
    Show-ChangePlan $plan
    if ($PreviewOnly) { Save-Report $Serial 'plan' $plan; return $true }
    if (@($plan | Where-Object { $_.Status -eq 'Planned' }).Count -eq 0) {
        Write-Host 'Khong co thay doi can ap dung; khong tao backup rong.'
        Save-TargetProfile $Serial $Targets $EnableCalls $EnableOverlay $Advanced $GoogleServices ''
        Save-Report $Serial 'plan' $plan
        Show-ManualGuidance
        return (@($plan | Where-Object { $_.Status -eq 'Skipped' }).Count -eq 0)
    }
    if (-not $NonInteractive -and (Read-Host 'Ap dung cac thay doi tren? (Y/N, mac dinh N)').Trim() -ne 'Y') { Write-Host 'Da huy.'; return $true }
    $journal=New-ChangeJournal $Metadata $Targets $plan
    Write-Host "Sao luu/nhat ky: $($journal.Path)" -ForegroundColor Cyan
    Invoke-ChangeJournal $Serial $journal.Data $journal.Path $Metadata.ApiLevel
    Save-TargetProfile $Serial $Targets $EnableCalls $EnableOverlay $Advanced $GoogleServices $journal.Path
    $verified=@($plan | Where-Object { $_.Status -eq 'Verified' }).Count
    $bad=@($plan | Where-Object { $_.Status -in @('Skipped','Failed','Uncertain','Conflict') }).Count
    Write-Host "Da xac minh $verified thay doi; $bad muc chua dat/chua xac dinh."
    Save-Report $Serial 'fix' $journal.Data
    Show-ManualGuidance
    return ($bad -eq 0)
}

function Save-TargetProfile {
    param([string]$Serial, [array]$Targets, [bool]$EnableCalls, [bool]$EnableOverlay, [bool]$Advanced, [bool]$GoogleServices, [string]$JournalPath)
    $path=Join-Path $script:ToolRoot ('backups\profile_' + ($Serial -replace '[^\w.-]', '_') + '.json')
    $history=@(); $original=$JournalPath
    if (Test-Path -LiteralPath $path) {
        $old=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($old.Serial -ceq $Serial) {
            $history=@($old.JournalHistory | Where-Object { $_ })
            if ($old.OriginalJournal) { $original=$old.OriginalJournal }
        }
    }
    if ($JournalPath) { $history += $JournalPath }
    Save-JsonAtomic $path ([PSCustomObject]@{ Serial=$Serial; Targets=@($Targets | Select-Object Package,UserId); Calls=$EnableCalls; Overlay=$EnableOverlay; Advanced=$Advanced; GoogleServices=$GoogleServices; OriginalJournal=$original; JournalHistory=@($history | Select-Object -Unique) })
}

function Get-Backups {
    param([string]$Serial)
    $dir=Join-Path $script:ToolRoot 'backups'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $files=@(Get-ChildItem -LiteralPath $dir -Filter 'backup_*.json' -File | Sort-Object LastWriteTime -Descending)
    foreach ($file in $files) {
        try {
            $data=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($data.SchemaVersion -eq 2 -and $data.Metadata.Serial -ceq $Serial -and @($data.Entries | Where-Object { $_.Attempted -and $_.RestoreStatus -ne 'Restored' }).Count -gt 0) { $file }
        } catch { Write-Warning "Bo qua backup khong doc duoc: $($file.Name)" }
    }
}

function Show-FcmDiagnostics {
    param([string]$Serial)
    $r=Invoke-Adb $Serial @('shell','dumpsys','activity','service','com.google.android.gms/.gcm.GcmService')
    $state='Unknown'
    if ($r.Success) { $state=Get-FcmConnectionState $r.StdOut }
    Write-Host "FCM hien tai (khoi Client): $state" -ForegroundColor Cyan
    $events=@($r.StdOut -split '\r?\n' | Where-Object { $_ -match 'Received|Successful broadcast|No response|Failed to broadcast' } | Select-Object -Last 15)
    foreach ($line in $events) { Write-Host $line }
    if (-not $r.Success) { Write-Host "[$($r.Status)] $($r.Output)" -ForegroundColor Yellow }
    Write-Host 'Connected chi la trang thai luc doc. Thoi gian broadcast khong do do tre tu luc gui den luc hien thong bao.'
    Write-Host 'Failed to broadcast to stopped app: mo dung app/user mot lan va thu lai. Chua du du lieu de ket luan loi MQTT.'
    Save-Report $Serial 'fcm' ([PSCustomObject]@{ CapturedAt=(Get-Date).ToString('o'); State=$state; Command=$r; Events=$events })
    return ($state -ne 'Unknown')
}

function Open-AppSettings {
    param([string]$Serial, $Target)
    $r=Invoke-Adb $Serial @('shell','am','start','--user',"$($Target.UserId)",'-a','android.settings.APP_NOTIFICATION_SETTINGS','--es','android.provider.extra.APP_PACKAGE',$Target.Package)
    if (-not $r.Success) { $r=Invoke-Adb $Serial @('shell','am','start','--user',"$($Target.UserId)",'-a','android.settings.APPLICATION_DETAILS_SETTINGS','-d',('package:' + $Target.Package)) }
    if (-not $r.Success) { Write-Host "Khong mo duoc man hinh cai dat [u$($Target.UserId)]: $($r.Output). Mo Cai dat -> Ung dung -> $($Target.AppName) thu cong." -ForegroundColor Yellow }
    else { Write-Host "Da gui yeu cau mo cai dat $($Target.AppName) [u$($Target.UserId)]. Kiem tra dung user va cac kenh tren dien thoai." }
    return $r.Success
}

function Invoke-Reapply {
    param([string]$Serial, [array]$Users, [hashtable]$Metadata, [bool]$NonInteractive, [bool]$PreviewOnly)
    $path=Join-Path $script:ToolRoot ('backups\profile_' + ($Serial -replace '[^\w.-]', '_') + '.json')
    if (-not (Test-Path -LiteralPath $path)) { throw 'Chua co ho so ap dung. Hay chon app/user va toi uu truoc.' }
    $p=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($p.Serial -cne $Serial) { throw 'Ho so khong dung serial.' }
    $targets=@()
    foreach ($pair in $p.Targets) { $targets += @(Get-InstalledTargets $Serial $Users @($pair.Package) @([int]$pair.UserId)) }
    return Invoke-FixFlow $Serial $targets $Metadata $NonInteractive $PreviewOnly $p.Calls $p.Overlay $p.Advanced $p.GoogleServices
}

function Invoke-Main {
    $modes=@($Audit,$Fix,$Restore,$FCMTest,$OpenSettings,$Reapply | Where-Object { $_ })
    if ($modes.Count -gt 1) { throw 'Chi chon mot che do Audit/Fix/Restore/FCMTest/OpenSettings/Reapply.' }
    if ($PlanOnly -and -not ($Fix -or $Reapply)) { throw '-PlanOnly can -Fix hoac -Reapply.' }
    if ($NoPrompt -and $modes.Count -eq 0) { throw '-NoPrompt can mot che do cu the.' }
    if ($BackupFile -and -not $Restore) { throw '-BackupFile can -Restore.' }
    if (($Restore -or $FCMTest -or $Reapply) -and ($TargetPackage -or $UserId.Count -gt 0)) { throw 'Che do nay khong nhan bo loc app/user. Dung -Fix de chon pham vi moi.' }
    if ($modes.Count -gt 0 -and -not $Fix -and ($Calls -or $Overlay -or $AdvancedPermissions -or $IncludeGoogleServices)) { throw 'Tuy chon quyen/GoogleServices can -Fix; Reapply dung tuy chon da luu trong ho so.' }
    $resolvedUsers=@()
    # Enumerate directly: piping an omitted ($null) UserId creates an empty token.
    foreach ($value in $UserId) {
        foreach ($token in ($value -split ',')) {
            $number=0
            if (-not [int]::TryParse($token.Trim(),[ref]$number) -or $number -lt 0) { throw "UserId khong hop le: $token" }
            $resolvedUsers += $number
        }
    }
    $deviceSerial=Select-Device $Serial ([bool]$NoPrompt)
    $meta=Get-DeviceMetadata $deviceSerial
    Show-Header
    Write-Host "$($meta.Model) / Android $($meta.Android) / $($meta.OriginOS) / $deviceSerial"
    if ($FCMTest) { if (Show-FcmDiagnostics $deviceSerial) { return 0 }; return 2 }
    if ($Restore) {
        $path=$BackupFile
        if (-not $path) { $backups=@(Get-Backups $deviceSerial); if ($backups.Count -eq 0) { throw 'Khong co nhat ky schema 2 chua hoan tac cho dien thoai nay. Backup cu van duoc giu nguyen.' }; $path=$backups[0].FullName }
        if (Restore-FromGranularBackup $deviceSerial $path $meta.ApiLevel) { return 0 }; return 2
    }
    $users=@(Get-DeviceUsers $deviceSerial)
    if ($Reapply) { if (Invoke-Reapply $deviceSerial $users $meta ([bool]$NoPrompt) ([bool]$PlanOnly)) { return 0 }; return 2 }
    $targets=@(Get-InstalledTargets $deviceSerial $users $TargetPackage $resolvedUsers)
    if ($Audit) { $report=Audit-AppStatus $deviceSerial $targets $meta; Show-AuditReport $report; Save-Report $deviceSerial 'audit' $report; if (-not $report.UserScanComplete) { return 2 }; return 0 }
    if ($OpenSettings) { if ($targets.Count -ne 1) { throw 'Mo cai dat can dung mot -TargetPackage va mot -UserId.' }; if (Open-AppSettings $deviceSerial $targets[0]) { return 0 }; return 2 }
    if ($Fix) {
        if (-not $TargetPackage -or $resolvedUsers.Count -eq 0) {
            if ($NoPrompt) { throw '-Fix -NoPrompt can -TargetPackage va -UserId de chon ro pham vi.' }
            $targets=@(Select-Targets $targets)
        }
        if ($targets.Count -eq 0) { Write-Host 'Da huy.'; return 0 }
        if (Invoke-FixFlow $deviceSerial $targets $meta ([bool]$NoPrompt) ([bool]$PlanOnly) ([bool]$Calls) ([bool]$Overlay) ([bool]$AdvancedPermissions) ([bool]$IncludeGoogleServices)) { return 0 }; return 2
    }
    while ($true) {
        Write-Host "`n1. Kiem tra (chi doc) | 2. Chon app/user va toi uu | 3. Hoan tac"
        Write-Host '4. Chan doan FCM | 5. Thoat | 6. Mo cai dat app | 7. Kiem tra/ap dung lai'
        try {
            $choice=Read-Host 'Chon 1-7'
            if ($null -eq $choice) { Write-Host 'Dau vao da dong; thoat menu.'; return 0 }
            switch ($choice.Trim()) {
                '1' { $targets=@(Get-InstalledTargets $deviceSerial $users $TargetPackage $resolvedUsers); $report=Audit-AppStatus $deviceSerial $targets $meta; Show-AuditReport $report; Save-Report $deviceSerial 'audit' $report }
                '2' {
                    $targets=@(Get-InstalledTargets $deviceSerial $users $TargetPackage $resolvedUsers)
                    $selected=@(Select-Targets $targets)
                    if ($selected.Count -eq 0) { continue }
                    $enableCalls=((Read-Host 'Them cuoc goi toan man hinh? (Y/N, mac dinh N)').Trim() -eq 'Y')
                    $enableOverlay=((Read-Host 'Them cua so noi/bong bong chat? (Y/N, mac dinh N)').Trim() -eq 'Y')
                    $enableGoogle=((Read-Host 'Toi uu them Google Play Services? (Y/N, mac dinh N)').Trim() -eq 'Y')
                    [void](Invoke-FixFlow $deviceSerial $selected $meta $false $false $enableCalls $enableOverlay $false $enableGoogle)
                }
                '3' {
                    $backups=@(Get-Backups $deviceSerial)
                    if ($backups.Count -eq 0) { Write-Host 'Chua co nhat ky schema 2 can hoan tac.'; continue }
                    for ($i=0; $i -lt $backups.Count; $i++) { Write-Host "[$($i+1)] $($backups[$i].Name)" }
                    $answer=(Read-Host 'Chon backup (Enter = huy)').Trim(); $n=0
                    if (-not $answer) { continue }
                    if (-not [int]::TryParse($answer,[ref]$n) -or $n -lt 1 -or $n -gt $backups.Count) { throw 'So backup khong hop le.' }
                    [void](Restore-FromGranularBackup $deviceSerial $backups[$n-1].FullName $meta.ApiLevel)
                }
                '4' { [void](Show-FcmDiagnostics $deviceSerial) }
                '5' { return 0 }
                '6' { $targets=@(Get-InstalledTargets $deviceSerial $users $TargetPackage $resolvedUsers); $selected=@(Select-Targets $targets); foreach ($item in $selected) { [void](Open-AppSettings $deviceSerial $item) } }
                '7' { [void](Invoke-Reapply $deviceSerial $users $meta $false $false) }
                default { Write-Host 'Lua chon khong hop le.' }
            }
        } catch { Write-Host "[LOI] $($_.Exception.Message)" -ForegroundColor Red }
    }
}

# Dot sourcing exposes the functions to offline tests without connecting to ADB.
if ($MyInvocation.InvocationName -ne '.') {
    try { exit (Invoke-Main) }
    catch { Write-Host "[LOI] $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
}
