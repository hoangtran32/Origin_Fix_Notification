# State readers never turn a failed query into a default value.
function Invoke-Adb {
    param([string]$Serial, [string[]]$Arguments, [int]$TimeoutSeconds = 25)
    $allArgs = @()
    if ($Serial) { $allArgs += @('-s', $Serial) }
    $allArgs += $Arguments
    $quoted = @($allArgs | ForEach-Object {
        '"' + ([regex]::Replace(([regex]::Replace([string]$_, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"'
    })
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $process.StartInfo.FileName = $script:AdbPath
    $process.StartInfo.Arguments = $quoted -join ' '
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $code = -1; $stdout = ''; $stderr = ''; $timedOut = $false
    try {
        [void]$process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            $process.Kill()
            $process.WaitForExit()
        }
        $stdout = $outTask.GetAwaiter().GetResult()
        $stderr = $errTask.GetAwaiter().GetResult()
        $code = $process.ExitCode
    } catch { $stderr = $_.Exception.Message } finally { $process.Dispose() }
    $output = ($stdout + "`n" + $stderr).Trim()
    $status = 'Known'
    if ($timedOut) { $status = 'Unknown'; $code = -1; $output += "`nADB timeout" }
    elseif ($output -match '(?im)^\s*(Unknown (?:command|operation)|Error:.*(?:not supported|unknown op)|No shell command implementation|Can.t find service)') { $status = 'Unsupported' }
    elseif ($code -ne 0 -or $output -match '(?im)^\s*(Error[: ]|Exception|SecurityException|java\.[\w.]+Exception|Permission denial|Failure\b|adb: error)') { $status = 'Failed' }
    [PSCustomObject]@{ Arguments = $allArgs; ExitCode = $code; StdOut = $stdout; StdErr = $stderr; Output = $output; Status = $status; Success = ($status -eq 'Known') }
}

function New-State {
    param([string]$Status = 'Known', $Value = $null, [string]$Detail = '', $Command = $null)
    [PSCustomObject]@{ Status = $Status; Value = $Value; Detail = $Detail; Command = $Command }
}

function Get-AppOpState {
    param([string]$Serial, [int]$UserId, [string]$Package, [string]$Op)
    $r = Invoke-Adb $Serial @('shell','cmd','appops','get','--user',"$UserId",$Package,$Op)
    if (-not $r.Success) { return New-State $r.Status $null $r.Output $r }
    $modes = @([regex]::Matches($r.StdOut, '(?m)^\s*' + [regex]::Escape($Op) + ':\s*(allow|ignore|deny|default|foreground|errored)\b') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    # UID-level modes have no scope-safe inverse through appops set PACKAGE.
    if ($r.StdOut -match '(?im)^\s*Uid mode:') { return New-State 'Unsupported' $null 'AppOp o cap UID; can xu ly thu cong de tranh doi app dung chung UID.' $r }
    if ($modes.Count -eq 1) { return New-State 'Known' $modes[0] '' $r }
    if ($r.StdOut -match '(?im)^\s*No operations\.?\s*$') { return New-State 'Known' 'default' '' $r }
    New-State 'Unknown' $null $r.Output $r
}

function Get-StandbyBucket {
    param([string]$Serial, [int]$UserId, [string]$Package)
    $r = Invoke-Adb $Serial @('shell','am','get-standby-bucket','--user',"$UserId",$Package)
    if (-not $r.Success) { return New-State $r.Status $null $r.Output $r }
    if ($r.StdOut.Trim() -match '^\d+$') { return New-State 'Known' ([int]$r.StdOut.Trim()) '' $r }
    New-State 'Unknown' $null $r.Output $r
}

function Get-PackageUid {
    param([string]$Serial, [int]$UserId, [string]$Package)
    $r = Invoke-Adb $Serial @('shell','pm','list','packages','-U','--user',"$UserId",$Package)
    if (-not $r.Success) { return New-State $r.Status $null $r.Output $r }
    $uids = @([regex]::Matches($r.StdOut, '(?m)^package:' + [regex]::Escape($Package) + '\s+uid:(\d+)\s*$') | ForEach-Object { [int]$_.Groups[1].Value } | Select-Object -Unique)
    if ($uids.Count -eq 1) { return New-State 'Known' $uids[0] '' $r }
    New-State 'Unknown' $null 'Khong doc duoc UID chinh xac cua app/user.' $r
}

function Get-DozeWhitelist {
    param([string]$Serial)
    $r = Invoke-Adb $Serial @('shell','dumpsys','deviceidle','whitelist')
    if (-not $r.Success) { return New-State $r.Status $null $r.Output $r }
    $packages = @()
    foreach ($line in ($r.StdOut -split '\r?\n')) {
        if (-not $line.Trim()) { continue }
        # system-excidle only exempts light idle; it is not the full Doze list.
        if ($line -match '^(system|user),([\w.]+),\d+\s*$') { $packages += $matches[2] }
        elseif ($line -notmatch '^system-excidle,[\w.]+,\d+\s*$') { return New-State 'Unknown' $null $r.Output $r }
    }
    New-State 'Known' @($packages | Select-Object -Unique) '' $r
}

function Get-NetpolicyWhitelist {
    param([string]$Serial)
    $r = Invoke-Adb $Serial @('shell','cmd','netpolicy','list','restrict-background-whitelist')
    if (-not $r.Success) { return New-State $r.Status $null $r.Output $r }
    if ($r.StdOut.Trim() -match '^Restrict background whitelisted UIDs:\s*([\d\s]*)$') {
        $uids = @($matches[1] -split '\s+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
        return New-State 'Known' $uids '' $r
    }
    New-State 'Unknown' $null $r.Output $r
}

function Get-PackageDetails {
    param([string]$Serial, [int]$UserId, [string]$Package, [int]$ApiLevel)
    $r = Invoke-Adb $Serial @('shell','dumpsys','package',$Package)
    if (-not $r.Success) { return New-State $r.Status $null $r.Output $r }
    $block = [regex]::Match($r.StdOut, '(?ms)^\s{2}Package \[' + [regex]::Escape($Package) + '\].*?(?=^\s{2}Package \[|\z)').Value
    if (-not $block) { return New-State 'Unknown' $null 'Khong tim thay khoi Package.' $r }
    $user = [regex]::Match($block, '(?ms)^    User ' + $UserId + ':.*?(?=^    User \d+:|^\S|\z)').Value
    $header = ($user -split '\r?\n')[0]
    if ($header -notmatch '\binstalled=true\b') { return New-State 'Unknown' $null 'App khong cai cho user nay hoac thieu khoi User.' $r }
    $stopped = $null; $enabled = $null
    if ($header -match '\bstopped=(true|false)\b') { $stopped = ($matches[1] -eq 'true') }
    if ($header -match '\benabled=(\d+)\b') { $enabled = [int]$matches[1] }
    $requested = [regex]::Match($block, '(?ms)^    requested permissions:\s*\r?\n(.*?)(?=^    \S|\z)').Groups[1].Value
    $declared = ($requested -match '(?m)^\s+android\.permission\.POST_NOTIFICATIONS\s*$')
    $permission = New-State 'Unsupported' $null 'API < 33 hoac app khong khai bao POST_NOTIFICATIONS.'
    if ($ApiLevel -ge 33 -and $declared) {
        $pm = [regex]::Match($user, 'android\.permission\.POST_NOTIFICATIONS:\s*granted=(true|false),\s*flags=\[([^\]]*)\]')
        if ($pm.Success) {
            $flags = @($pm.Groups[2].Value -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
            $permission = New-State 'Known' ([PSCustomObject]@{ Granted = ($pm.Groups[1].Value -eq 'true'); Flags = $flags })
        } else { $permission = New-State 'Unknown' $null 'Thieu trang thai/flags quyen thong bao theo user.' }
    }
    New-State 'Known' ([PSCustomObject]@{ Stopped = $stopped; Enabled = $enabled; Declared = $declared; Permission = $permission }) '' $r
}

function Get-SettingState {
    param([string]$Serial, $Entry, [int]$ApiLevel)
    switch ($Entry.Kind) {
        'AppOp' { return Get-AppOpState $Serial $Entry.UserId $Entry.Package $Entry.Op }
        'Bucket' { return Get-StandbyBucket $Serial $Entry.UserId $Entry.Package }
        'Doze' {
            $r = Get-DozeWhitelist $Serial
            return New-State $r.Status ($r.Value -contains $Entry.Package) $r.Detail $r.Command
        }
        'NetPolicy' {
            if ($null -eq $Entry.Uid) { return New-State 'Unknown' $null 'Thieu UID; khong the xac minh NetPolicy.' }
            $r = Get-NetpolicyWhitelist $Serial
            return New-State $r.Status ($r.Value -contains [int]$Entry.Uid) $r.Detail $r.Command
        }
        'Permission' {
            $d = Get-PackageDetails $Serial $Entry.UserId $Entry.Package $ApiLevel
            if ($d.Status -ne 'Known') { return $d }
            $p = $d.Value.Permission
            if ($p.Status -ne 'Known') { return $p }
            $op = Get-AppOpState $Serial $Entry.UserId $Entry.Package 'POST_NOTIFICATION'
            if ($op.Status -ne 'Known') { return $op }
            return New-State 'Known' ([PSCustomObject]@{ Granted = $p.Value.Granted; Flags = @($p.Value.Flags); AppOp = $op.Value }) '' @($d.Command, $op.Command)
        }
        default { return New-State 'Unsupported' $null 'Loai cai dat khong ho tro.' }
    }
}

function Test-StateEqual {
    param($Left, $Right)
    if ($null -eq $Left -or $null -eq $Right) { return ($null -eq $Left -and $null -eq $Right) }
    if ($null -ne $Left.PSObject.Properties['Granted']) {
        return ($Left.Granted -eq $Right.Granted -and $Left.AppOp -eq $Right.AppOp -and ((@($Left.Flags | Sort-Object) -join '|') -ceq (@($Right.Flags | Sort-Object) -join '|')))
    }
    ($Left -ceq $Right)
}

function Set-SettingState {
    param([string]$Serial, $Entry, $Value, [int]$ApiLevel)
    $argsList = @()
    switch ($Entry.Kind) {
        'Doze' { $prefix = if ($Value) { '+' } else { '-' }; $argsList = @('shell','dumpsys','deviceidle','whitelist',($prefix + $Entry.Package)) }
        'Bucket' { $argsList = @('shell','am','set-standby-bucket','--user',"$($Entry.UserId)",$Entry.Package,"$Value") }
        'NetPolicy' { $action = if ($Value) { 'add' } else { 'remove' }; $argsList = @('shell','cmd','netpolicy',$action,'restrict-background-whitelist',"$($Entry.Uid)") }
        'AppOp' { $argsList = @('shell','cmd','appops','set','--user',"$($Entry.UserId)",$Entry.Package,$Entry.Op,"$Value") }
        'Permission' {
            $commands = @()
            $current = Get-SettingState $Serial $Entry $ApiLevel
            if ($current.Status -ne 'Known') { return [PSCustomObject]@{ Success = $false; Status = $current.Status; Commands = @(); Output = $current.Detail } }
            if ($current.Value.Granted -ne $Value.Granted) {
                $action = if ($Value.Granted) { 'grant' } else { 'revoke' }
                $r = Invoke-Adb $Serial @('shell','pm',$action,'--user',"$($Entry.UserId)",$Entry.Package,'android.permission.POST_NOTIFICATIONS')
                $commands += $r
                if (-not $r.Success) { return [PSCustomObject]@{ Success = $false; Status = $r.Status; Commands = $commands; Output = $r.Output } }
            }
            $now = Get-SettingState $Serial $Entry $ApiLevel
            if ($now.Status -ne 'Known') { return [PSCustomObject]@{ Success = $false; Status = $now.Status; Commands = $commands; Output = $now.Detail } }
            $flagMap = @{ USER_SET='user-set'; USER_FIXED='user-fixed'; REVOKE_ON_UPGRADE='revoke-on-upgrade'; REVIEW_REQUIRED='review-required'; REVOKED_COMPAT='revoked-compat'; ONE_TIME='one-time' }
            $diffFlags = @(@($now.Value.Flags) + @($Value.Flags) | Sort-Object -Unique | Where-Object { (@($now.Value.Flags) -contains $_) -ne (@($Value.Flags) -contains $_) })
            foreach ($flag in $diffFlags) {
                if (-not $flagMap.ContainsKey($flag)) { return [PSCustomObject]@{ Success=$false; Status='Unsupported'; Commands=$commands; Output="Khong the hoan nguyen flag $flag tu dong." } }
                $action = if (@($Value.Flags) -contains $flag) { 'set-permission-flags' } else { 'clear-permission-flags' }
                $r = Invoke-Adb $Serial @('shell','pm',$action,'--user',"$($Entry.UserId)",$Entry.Package,'android.permission.POST_NOTIFICATIONS',$flagMap[$flag])
                $commands += $r
                if (-not $r.Success) { return [PSCustomObject]@{ Success=$false; Status=$r.Status; Commands=$commands; Output=$r.Output } }
            }
            if ($now.Value.AppOp -ne $Value.AppOp) {
                $r = Invoke-Adb $Serial @('shell','cmd','appops','set','--user',"$($Entry.UserId)",$Entry.Package,'POST_NOTIFICATION',$Value.AppOp)
                $commands += $r
                if (-not $r.Success) { return [PSCustomObject]@{ Success=$false; Status=$r.Status; Commands=$commands; Output=$r.Output } }
            }
            return [PSCustomObject]@{ Success=$true; Status='Known'; Commands=$commands; Output=(@($commands | ForEach-Object { $_.Output }) -join "`n") }
        }
        default { throw "Loai thay doi khong hop le: $($Entry.Kind)" }
    }
    $r = Invoke-Adb $Serial $argsList
    [PSCustomObject]@{ Success=$r.Success; Status=$r.Status; Commands=@($r); Output=$r.Output }
}

function Save-JsonAtomic {
    param([string]$Path, $Data)
    $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
    [void][System.IO.Directory]::CreateDirectory($directory)
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [System.IO.File]::WriteAllText($temp, ($Data | ConvertTo-Json -Depth 18), (New-Object System.Text.UTF8Encoding($true)))
    if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Replace($temp, $Path, [System.Management.Automation.Language.NullString]::Value) }
    else { [System.IO.File]::Move($temp, $Path) }
}

function New-ChangePlan {
    param([string]$Serial, [array]$SelectedApps, [int]$ApiLevel, [bool]$Calls, [bool]$Overlay, [bool]$Advanced, [bool]$GoogleServices)
    $entries = @(); $seen = @{}
    $targets = @($SelectedApps)
    if ($GoogleServices) {
        foreach ($id in @($SelectedApps.UserId | Sort-Object -Unique)) {
            $uid = Get-PackageUid $Serial $id 'com.google.android.gms'
            $targets += [PSCustomObject]@{ Package='com.google.android.gms'; UserId=$id; Uid=$uid.Value; AppName='Google Play Services'; GoogleOnly=$true }
        }
    }
    foreach ($item in $targets) {
        $specs = @(@{ Kind='Doze'; Desired=$true }, @{ Kind='Bucket'; Desired=10 })
        if (-not $item.GoogleOnly) {
            $specs += @{ Kind='NetPolicy'; Desired=$true }
            if ($ApiLevel -ge 33) { $specs += @{ Kind='Permission'; Desired=$null } }
            foreach ($op in @('VIBRATE','WAKE_LOCK','START_FOREGROUND','RUN_IN_BACKGROUND','RUN_ANY_IN_BACKGROUND')) { $specs += @{ Kind='AppOp'; Op=$op; Desired='allow' } }
            if ($ApiLevel -lt 33) { $specs += @{ Kind='AppOp'; Op='POST_NOTIFICATION'; Desired='allow' } }
            if ($Calls -or $Advanced) { $specs += @{ Kind='AppOp'; Op='USE_FULL_SCREEN_INTENT'; Desired='allow' } }
            if ($Overlay -or $Advanced) { $specs += @{ Kind='AppOp'; Op='SYSTEM_ALERT_WINDOW'; Desired='allow' } }
            if ($Advanced) { $specs += @{ Kind='AppOp'; Op='AUTO_REVOKE_PERMISSIONS_IF_UNUSED'; Desired='ignore' } }
        }
        foreach ($spec in $specs) {
            $key = "$($spec.Kind):$($item.UserId):$($item.Package):$($spec.Op)"
            if ($spec.Kind -eq 'Doze') { $key = "Doze:$($item.Package)" }
            if ($spec.Kind -eq 'NetPolicy' -and $null -ne $item.Uid) { $key = "NetPolicy:$($item.Uid)" }
            if ($seen.ContainsKey($key)) { continue }; $seen[$key] = $true
            $entry = [PSCustomObject]@{ Id=[guid]::NewGuid().ToString('N'); Kind=$spec.Kind; Package=$item.Package; AppName=$item.AppName; UserId=[int]$item.UserId; Uid=$item.Uid; Op=$spec.Op; Before=$null; BeforeQuery=$null; Desired=$spec.Desired; ReadStatus='Unknown'; Status='Skipped'; Detail=''; Attempted=$false; CommandResult=$null; ObservedAfter=$null; AfterKnown=$false; AfterQuery=$null; RestoreStatus=''; RestoreResult=$null; RestoreObserved=$null }
            $before = Get-SettingState $Serial $entry $ApiLevel
            $entry.ReadStatus = $before.Status; $entry.Before = $before.Value; $entry.BeforeQuery=$before; $entry.Detail = $before.Detail
            if ($before.Status -eq 'Known') {
                if ($entry.Kind -eq 'Permission') {
                    $entry.Desired = [PSCustomObject]@{ Granted=$true; Flags=@($before.Value.Flags); AppOp='allow' }
                    if ((@($before.Value.Flags) -match '^(SYSTEM_FIXED|POLICY_FIXED)$') -and -not (Test-StateEqual $entry.Before $entry.Desired)) {
                        $entry.ReadStatus='Unsupported'; $entry.Detail='Quyen bi khoa boi he thong/chinh sach; mo cai dat de kiem tra.'
                    }
                }
                if ($entry.Kind -eq 'Bucket' -and [int]$before.Value -eq 5) { $entry.Desired=5 }
                if ($null -eq $item.Uid) { $entry.ReadStatus='Unknown'; $entry.Detail='Thieu UID; bo qua thay doi de tranh nham app/user.' }
                if ($entry.ReadStatus -eq 'Known') {
                    $entry.Status = if (Test-StateEqual $entry.Before $entry.Desired) { 'AlreadySatisfied' } else { 'Planned' }
                }
            }
            $entries += $entry
        }
    }
    return $entries
}

function New-ChangeJournal {
    param([hashtable]$Metadata, [array]$SelectedApps, [array]$Plan)
    $safeSerial = $Metadata.Serial -replace '[^\w.-]', '_'
    $name = 'backup_' + $safeSerial + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $path = Join-Path $script:ToolRoot "backups\$name.json"
    $journal = [PSCustomObject]@{ SchemaVersion=2; Metadata=$Metadata; CreatedAt=(Get-Date).ToString('o'); AppStates=@($SelectedApps); Entries=@($Plan); DeliveryTest='Chua kiem chung nhan tin nen'; CompletedAt=$null }
    Save-JsonAtomic $path $journal
    $summary = @('NHAT KY THAY DOI - schema 2', "Thiet bi: $($Metadata.Model) / $($Metadata.Serial)", 'Doze ap dung chung package; NetPolicy ap dung chung UID.', 'Nhan tin nen: chua kiem chung.', '')
    $summary += @($Plan | ForEach-Object { "$($_.Package) [u$($_.UserId)] $($_.Kind) $($_.Op): $($_.Before | ConvertTo-Json -Compress) -> $($_.Desired | ConvertTo-Json -Compress) [$($_.Status)]" })
    [System.IO.File]::WriteAllLines((Join-Path $script:ToolRoot "backups\$name.txt"), [string[]]$summary, [System.Text.Encoding]::UTF8)
    [PSCustomObject]@{ Path=$path; Data=$journal }
}

function Invoke-ChangeJournal {
    param([string]$Serial, $Journal, [string]$Path, [int]$ApiLevel)
    foreach ($e in $Journal.Entries) {
        if ($e.Status -ne 'Planned') { continue }
        $uid = Get-PackageUid $Serial $e.UserId $e.Package
        $current = Get-SettingState $Serial $e $ApiLevel
        if ($uid.Status -ne 'Known' -or $uid.Value -ne $e.Uid) { $e.Status='Conflict'; $e.Detail='UID thay doi/khong doc duoc; khong sua.' }
        elseif ($current.Status -ne 'Known') { $e.Status='Skipped'; $e.Detail=$current.Detail }
        elseif (Test-StateEqual $current.Value $e.Desired) { $e.Status='AlreadySatisfied' }
        elseif (-not (Test-StateEqual $current.Value $e.Before)) { $e.Status='Conflict'; $e.Detail='Gia tri da doi sau khi lap ke hoach; khong ghi de.' }
        else {
            # Persist the intent BEFORE sending any mutating command, including partial failures.
            $e.Status='Applying'; $e.Attempted=$true
            Save-JsonAtomic $Path $Journal
            $e.CommandResult = Set-SettingState $Serial $e $e.Desired $ApiLevel
            $after = Get-SettingState $Serial $e $ApiLevel
            $e.AfterKnown = ($after.Status -eq 'Known'); $e.ObservedAfter=$after.Value; $e.AfterQuery=$after
            if ($e.CommandResult.Success -and $e.AfterKnown -and (Test-StateEqual $after.Value $e.Desired)) { $e.Status='Verified' }
            elseif (-not $e.AfterKnown) { $e.Status='Uncertain'; $e.Detail=$after.Detail }
            else { $e.Status='Failed'; $e.Detail=$e.CommandResult.Output }
        }
        Save-JsonAtomic $Path $Journal
        Write-Host "[$($e.Status)] $($e.Package) [u$($e.UserId)] $($e.Kind) $($e.Op) $($e.Detail)"
    }
    $Journal.CompletedAt=(Get-Date).ToString('o')
    Save-JsonAtomic $Path $Journal
}

function Restore-FromGranularBackup {
    param([string]$Serial, [string]$BackupFilePath, [int]$ApiLevel)
    $journal = Get-Content -LiteralPath $BackupFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($journal.SchemaVersion -ne 2) { throw 'Backup cu thieu nhat ky thay doi; khong the hoan tac chinh xac. Giu file de doi chieu thu cong.' }
    if ($journal.Metadata.Serial -cne $Serial) { throw 'Serial backup khong trung dien thoai dang chon.' }
    # Validate every entry before allowing the first write.
    foreach ($e in $journal.Entries) {
        if ($e.Package -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$' -or $e.UserId -lt 0 -or $e.Kind -notin @('Doze','Bucket','NetPolicy','AppOp','Permission')) { throw 'Backup co entry khong hop le.' }
        if ($e.Kind -eq 'AppOp' -and ($e.Op -notin @('POST_NOTIFICATION','VIBRATE','WAKE_LOCK','START_FOREGROUND','RUN_IN_BACKGROUND','RUN_ANY_IN_BACKGROUND','USE_FULL_SCREEN_INTENT','SYSTEM_ALERT_WINDOW','AUTO_REVOKE_PERMISSIONS_IF_UNUSED') -or ($e.Attempted -and $e.Before -notin @('allow','ignore','deny','default','foreground','errored')))) { throw 'Backup co AppOp khong hop le.' }
        if ($e.Kind -in @('Doze','NetPolicy') -and $e.Attempted -and $e.Before -isnot [bool]) { throw 'Backup co trang thai whitelist khong hop le.' }
        if ($e.Kind -eq 'Bucket' -and $e.Attempted -and $e.Before -notin @(5,10,20,30,40,45,50)) { throw 'Backup co bucket khong hop le.' }
        if ($e.Kind -eq 'Permission' -and $e.Attempted -and ($e.Before.Granted -isnot [bool] -or $e.Before.AppOp -notin @('allow','ignore','deny','default','foreground','errored'))) { throw 'Backup co quyen thong bao khong hop le.' }
    }
    $entries = @($journal.Entries)
    [array]::Reverse($entries)
    foreach ($e in $entries) {
        if (-not $e.Attempted -or $e.RestoreStatus -eq 'Restored') { continue }
        $uid = Get-PackageUid $Serial $e.UserId $e.Package
        $current = Get-SettingState $Serial $e $ApiLevel
        if ($uid.Status -ne 'Known' -or $uid.Value -ne $e.Uid) { $e.RestoreStatus='Conflict' }
        elseif ($current.Status -ne 'Known') { $e.RestoreStatus='Unknown' }
        elseif (Test-StateEqual $current.Value $e.Before) { $e.RestoreStatus='Restored' }
        elseif ((Test-StateEqual $current.Value $e.Desired) -or ($e.AfterKnown -and (Test-StateEqual $current.Value $e.ObservedAfter)) -or ($e.RestoreObserved.Status -eq 'Known' -and (Test-StateEqual $current.Value $e.RestoreObserved.Value))) {
            $e.RestoreStatus='Restoring'
            Save-JsonAtomic $BackupFilePath $journal
            $e.RestoreResult = Set-SettingState $Serial $e $e.Before $ApiLevel
            $after = Get-SettingState $Serial $e $ApiLevel
            $e.RestoreObserved = $after
            $e.RestoreStatus = if ($e.RestoreResult.Success -and $after.Status -eq 'Known' -and (Test-StateEqual $after.Value $e.Before)) { 'Restored' } else { 'Failed' }
        } else { $e.RestoreStatus='Conflict' }
        Save-JsonAtomic $BackupFilePath $journal
        Write-Host "[$($e.RestoreStatus)] $($e.Package) [u$($e.UserId)] $($e.Kind) $($e.Op)"
    }
    $pending = @($journal.Entries | Where-Object { $_.Attempted -and $_.RestoreStatus -ne 'Restored' })
    Write-Host "Hoan tac: $(@($journal.Entries | Where-Object { $_.RestoreStatus -eq 'Restored' }).Count) muc; con $($pending.Count) muc chua khoi phuc."
    return ($pending.Count -eq 0)
}

function Get-FcmConnectionState {
    param([string]$Dump)
    $blocks = [regex]::Matches($Dump, '(?ms)^([ \t]*)Client:[ \t]*\r?\n(.*?)(?=^\1\S|\z)')
    $states = @()
    foreach ($block in $blocks) {
        $text = $block.Groups[2].Value
        $bools = @([regex]::Matches($text, '(?im)^\s*Is client connected:\s*(true|false)\s*$') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Select-Object -Unique)
        $endpoint = ($text -match '(?im)^\s*connected=mtalk\.google\.com[/,:]')
        $disconnected = ($text -match '(?im)^\s*(?:disconnected\s*|connected=(?:null|false|none)\s*|state:\s*disconnected\s*)$')
        if ($bools.Count -ne 1 -or ($bools[0] -eq 'false' -and $endpoint) -or ($bools[0] -eq 'true' -and $disconnected)) { $states += 'Unknown' }
        elseif ($bools[0] -eq 'true') { $states += 'Connected' } else { $states += 'Disconnected' }
    }
    $unique = @($states | Select-Object -Unique)
    if ($unique.Count -eq 1) { return $unique[0] }
    return 'Unknown'
}
