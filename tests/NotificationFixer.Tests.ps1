# Offline regression tests: no Pester install and no phone writes required.
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot 'tools\VivoNotificationFixer.ps1')
$script:ToolRoot=Join-Path ([System.IO.Path]::GetTempPath()) ('VivoFixerTests_' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($script:ToolRoot)
$script:Assertions=0
function Assert {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "ASSERT: $Message" }
    $script:Assertions++
}
function Assert-Throws {
    param([scriptblock]$Action,[string]$Message)
    $threw=$false
    try { & $Action | Out-Null } catch { $threw=$true }
    Assert $threw $Message
}

# Exercise startup itself: helper-only tests do not cover an omitted -UserId.
& {
    function Select-Device { return 'fake' }
    function Get-DeviceMetadata { return @{ Model='Fake'; Android='16'; OriginOS='Test'; ApiLevel=36 } }
    function Get-DeviceUsers { return @([PSCustomObject]@{ Id=0; Name='Owner' }, [PSCustomObject]@{ Id=999; Name='Clone' }) }
    function Get-InstalledTargets {
        param([string]$Serial, [array]$Users, [string[]]$Packages, [int[]]$RequestedUsers)
        Assert ($RequestedUsers.Count -eq 0) 'Omitted UserId must leave all device users available.'
        return @()
    }
    function Read-Host {
        param([string]$Prompt)
        Assert ($Prompt -eq 'Chon 1-7') 'Default startup must reach the main menu.'
        return '5'
    }
    Assert ((Invoke-Main 6>$null) -eq 0) 'Default menu must exit successfully without UserId.'
    function Read-Host { return $null }
    Assert ((Invoke-Main 6>$null) -eq 0) 'Closed terminal input must exit instead of repeating a null-input error forever.'
}

# Stop before any ADB call while checking startup validation in each CLI mode.
foreach ($mode in @('Audit','Fix','Restore','FCMTest','OpenSettings','Reapply')) {
    & {
        Set-Variable -Name $mode -Value $true -Scope Local
        function Select-Device { throw 'TEST_DEVICE_SELECTION' }
        $message=''
        try { Invoke-Main | Out-Null } catch { $message=$_.Exception.Message }
        Assert ($message -eq 'TEST_DEVICE_SELECTION') "$mode must accept an omitted UserId at startup."
    }
}
foreach ($case in @(
    @{ Value=@(); Valid=$true },
    @{ Value=@('0'); Valid=$true },
    @{ Value=@('999'); Valid=$true },
    @{ Value=@('0','999'); Valid=$true },
    @{ Value=@('0,999'); Valid=$true },
    @{ Value=@(' 0, 999 '); Valid=$true },
    @{ Value=@(''); Valid=$false },
    @{ Value=@(' '); Valid=$false },
    @{ Value=@(','); Valid=$false },
    @{ Value=@('0,'); Valid=$false },
    @{ Value=@('abc'); Valid=$false },
    @{ Value=@('-1'); Valid=$false },
    @{ Value=@('2147483648'); Valid=$false }
)) {
    & {
        $UserId=[string[]]$case.Value
        function Select-Device { throw 'TEST_DEVICE_SELECTION' }
        $message=''
        try { Invoke-Main | Out-Null } catch { $message=$_.Exception.Message }
        if ($case.Valid) { Assert ($message -eq 'TEST_DEVICE_SELECTION') "Valid UserId must pass startup validation: $($case.Value -join ';')" }
        else { Assert ($message.StartsWith('UserId khong hop le:')) "Explicit invalid UserId must still be rejected: $($case.Value -join ';')" }
    }
}

# Exercise the actual process runner's stderr, exit code and timeout handling.
$actualAdb=$script:AdbPath
$script:AdbPath=(Get-Command powershell.exe).Source
$result=Invoke-Adb '' @('-NoProfile','-Command','[Console]::Error.WriteLine("failure"); exit 7')
Assert ($result.ExitCode -eq 7 -and -not $result.Success -and $result.StdErr -match 'failure') 'Native exit/stderr must survive.'
$result=Invoke-Adb '' @('-NoProfile','-Command','Start-Sleep -Seconds 4') 1
Assert ($result.Status -eq 'Unknown' -and $result.Output -match 'timeout') 'Timeout must not look successful.'
$result=Invoke-Adb '' @('-NoProfile','-Command','Write-Output "Error: permission denied"; exit 0')
Assert (-not $result.Success) 'Exit zero with an explicit Android error must not be successful.'
$script:AdbPath=$actualAdb

$fixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures\fcm-connected.txt') -Raw
Assert ((Get-FcmConnectionState $fixture) -eq 'Connected') 'Client current boolean must be recognized.'
Assert ((Get-FcmConnectionState "  Client:`n    Is client connected: false`n    10-09 12:00:00 Connected") -eq 'Disconnected') 'Historical Connected must not override false.'
Assert ((Get-FcmConnectionState 'Disconnected') -eq 'Unknown') 'Disconnected substring without Client data must be unknown.'
Assert ((Get-FcmConnectionState "  Client:`n    Is client connected: false`n    connected=mtalk.google.com/1.2.3.4,port=5228") -eq 'Unknown') 'Conflicting current fields must be unknown.'
Assert ((Get-FcmConnectionState "  Client:`n    Is client connected: true`n    Is client connected: false") -eq 'Unknown') 'Conflicting booleans must be unknown.'
Assert ((Get-FcmConnectionState "  Client:`n    Is client connected: true`nOther:`n  Client:`n    Is client connected: false") -eq 'Unknown') 'Multiple contradictory clients must be unknown.'
Assert ((Get-FcmConnectionState "  Client:`n    10-09 Connected") -eq 'Unknown') 'History only must be unknown.'

# Fake Android state. All mutating commands below affect only these hashtables.
$script:Writes=@(); $script:Reads=@(); $script:UidOverrides=@{}; $script:Failures=@{}; $script:ReadFailures=@{}
$script:Doze=@{}; $script:Net=@{}; $script:Buckets=@{}; $script:Ops=@{}; $script:Grants=@{}; $script:FlagSets=@{}
$script:InstalledPackages=@{ '0'=@('com.example.chat'); '666'=@('com.example.chat'); '999'=@('com.example.chat') }
$script:ReplyOverride=$null; $script:JournalUnderTest=$null; $script:CheckDurableIntent=$false
function Invoke-Adb {
    param([string]$Serial,[string[]]$Arguments,[int]$TimeoutSeconds=25)
    $a=$Arguments; $key=$a -join ' '; $out=''; $code=0; $status='Known'; $write=$false
    if ($null -ne $script:ReplyOverride) { return $script:ReplyOverride }
    if ($key -eq 'shell pm list users') {
        $out="Users:`n  UserInfo{0:Owner:4c13} running`n  UserInfo{666:XSpace User:80001010} running`n  UserInfo{999:Clone:20001010} running"
    } elseif ($key -match '^shell pm list packages --user (\d+)$') {
        $out=(@($script:InstalledPackages[$matches[1]] | ForEach-Object { "package:$_" }) -join "`n")
    } elseif ($key -match '^shell pm list packages -U --user (\d+) (\S+)$') {
        $u=[int]$matches[1]; $pkg=$matches[2]; $uid=($u * 100000 + 10306)
        if ($script:UidOverrides.ContainsKey("$u/$pkg")) { $uid=$script:UidOverrides["$u/$pkg"] }
        if ($null -ne $uid) { $out="package:$pkg uid:$uid" }
    } elseif ($key -eq 'shell dumpsys deviceidle whitelist') {
        $out=(@($script:Doze.Keys | Where-Object { $script:Doze[$_] } | ForEach-Object { "user,$_,10306" }) -join "`n")
    } elseif ($key -match '^shell dumpsys deviceidle whitelist ([+-])(\S+)$') {
        $script:Doze[$matches[2]]=($matches[1] -eq '+'); $write=$true
    } elseif ($key -eq 'shell cmd netpolicy list restrict-background-whitelist') {
        $out='Restrict background whitelisted UIDs: ' + (@($script:Net.Keys | Where-Object { $script:Net[$_] }) -join ' ')
    } elseif ($key -eq 'shell cmd netpolicy get restrict-background') {
        $out='Restrict background status: disabled'
    } elseif ($key -eq 'shell settings get global zen_mode') {
        $out='0'
    } elseif ($key -match '^shell cmd netpolicy (add|remove) restrict-background-whitelist (\d+)$') {
        $script:Net[$matches[2]]=($matches[1] -eq 'add'); $write=$true
    } elseif ($key -match '^shell am get-standby-bucket --user (\d+) (\S+)$') {
        $k="$($matches[1])/$($matches[2])"; $out='30'
        if ($script:Buckets.ContainsKey($k)) { $out=[string]$script:Buckets[$k] }
    } elseif ($key -match '^shell am set-standby-bucket --user (\d+) (\S+) (\d+)$') {
        $script:Buckets["$($matches[1])/$($matches[2])"]=[int]$matches[3]; $write=$true
    } elseif ($key -match '^shell cmd appops get --user (\d+) (\S+) (\S+)$') {
        $op=$matches[3]; $k="$($matches[1])/$($matches[2])/$op"; $out='No operations.'
        if ($script:Ops.ContainsKey($k)) { $out="$op`: $($script:Ops[$k]); rejectTime=allow" }
    } elseif ($key -match '^shell cmd appops set --user (\d+) (\S+) (\S+) (\S+)$') {
        $script:Ops["$($matches[1])/$($matches[2])/$($matches[3])"]=$matches[4]; $write=$true
    } elseif ($key -match '^shell dumpsys package (\S+)$') {
        $pkg=$matches[1]
        $out="  Package [$pkg] (fake):`n    requested permissions:`n      android.permission.POST_NOTIFICATIONS`n    install permissions:`n"
        foreach ($u in @(0,999)) {
            $k="$u/$pkg"; $granted='false'; $flags='USER_SET|USER_SENSITIVE_WHEN_DENIED'
            if ($script:Grants.ContainsKey($k) -and $script:Grants[$k]) { $granted='true' }
            if ($script:FlagSets.ContainsKey($k)) { $flags=$script:FlagSets[$k] -join '|' }
            $out += "    User $u`: installed=true stopped=false enabled=0`n      runtime permissions:`n        android.permission.POST_NOTIFICATIONS: granted=$granted, flags=[ $flags ]`n"
        }
    } elseif ($key -match '^shell pm (grant|revoke) --user (\d+) (\S+) android.permission.POST_NOTIFICATIONS$') {
        $grant=($matches[1] -eq 'grant'); $k="$($matches[2])/$($matches[3])"
        $script:Grants[$k]=$grant
        $script:Ops["$k/POST_NOTIFICATION"]=if ($grant) { 'allow' } else { 'ignore' }
        $write=$true
    } elseif ($key -match '^shell pm (set|clear)-permission-flags --user (\d+) (\S+) android.permission.POST_NOTIFICATIONS (\S+)$') {
        $set=($matches[1] -eq 'set'); $k="$($matches[2])/$($matches[3])"; $flag=$matches[4].ToUpper().Replace('-','_')
        $flags=@($script:FlagSets[$k] | Where-Object { $_ -ne $flag }); if ($set) { $flags += $flag }; $script:FlagSets[$k]=$flags; $write=$true
    } else { throw "Unexpected fake command: $key" }
    if ($write) {
        if ($script:CheckDurableIntent) {
            $saved=Get-Content -LiteralPath $script:JournalUnderTest -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert (@($saved.Entries | Where-Object { $_.Attempted -and $_.Status -eq 'Applying' }).Count -gt 0) 'Intent must be on disk before mutation.'
        }
        $script:Writes += $key
        if ($script:Failures.ContainsKey($key)) { $code=1; $status='Failed'; $out=$script:Failures[$key] }
    } else {
        $script:Reads += $key
        if ($script:ReadFailures.ContainsKey($key)) { $code=1; $status='Failed'; $out=$script:ReadFailures[$key] }
    }
    [PSCustomObject]@{ Arguments=$a; ExitCode=$code; StdOut=$out; StdErr=''; Output=$out; Status=$status; Success=($status -eq 'Known') }
}

$script:ReplyOverride=[PSCustomObject]@{ Success=$false; Status='Failed'; Output='SecurityException: allow denied'; StdOut=''; ExitCode=1 }
Assert ((Get-AppOpState 'fake' 0 'com.example.chat' 'POST_NOTIFICATION').Status -eq 'Failed') 'Failed AppOps query must not become default/allow.'
$script:ReplyOverride=[PSCustomObject]@{ Success=$true; Status='Known'; Output=''; StdOut='POST_NOTIFICATION: ignore; rejectTime=allow'; ExitCode=0 }
Assert ((Get-AppOpState 'fake' 0 'com.example.chat' 'POST_NOTIFICATION').Value -eq 'ignore') 'Mode parser must ignore words in timing/history.'
$script:ReplyOverride=[PSCustomObject]@{ Success=$true; Status='Known'; Output=''; StdOut='Uid mode: RUN_IN_BACKGROUND: allow'; ExitCode=0 }
Assert ((Get-AppOpState 'fake' 0 'com.example.chat' 'RUN_IN_BACKGROUND').Status -eq 'Unsupported') 'UID-level AppOp must not be overwritten as a package mode.'
$script:ReplyOverride=[PSCustomObject]@{ Success=$true; Status='Known'; Output=''; StdOut='system-excidle,com.example.chat,10306'; ExitCode=0 }
Assert ((Get-DozeWhitelist 'fake').Value -notcontains 'com.example.chat') 'Light idle exemption is not full Doze exemption.'
$script:ReplyOverride=[PSCustomObject]@{ Success=$true; Status='Known'; Output=''; StdOut='unexpected'; ExitCode=0 }
Assert ((Get-NetpolicyWhitelist 'fake').Status -eq 'Unknown') 'Malformed NetPolicy must not be an empty known whitelist.'
$script:ReplyOverride=$null

# Reproduce the device's inaccessible XSpace user without losing owner/clone apps.
$testUsers=@(Get-DeviceUsers 'fake')
Assert ($testUsers.Count -eq 3 -and $testUsers[1].Name -eq 'XSpace User') 'User discovery must retain protected users and their real names.'
$script:ReadFailures['shell pm list packages --user 666']='Error: Shell does not have permission to access user 666'
$scanOutput=@(Get-InstalledTargets 'fake' $testUsers @('com.example.chat') @() 3>&1)
$warnings=@($scanOutput | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
$discovered=@($scanOutput | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })
Assert ($discovered.Count -eq 2 -and $discovered.UserId -contains 0 -and $discovered.UserId -contains 999) 'Automatic scanning must continue past a denied user to the clone.'
Assert ($discovered.UserId -notcontains 666) 'Denied user must not supply targets or inherit owner apps.'
Assert ($warnings.Count -eq 1 -and "$($warnings[0])" -match '666.*XSpace User') 'Skipped user must produce an actionable warning with ID and name.'
$denied=@($script:LastUserScanResults | Where-Object { $_.Status -eq 'AccessDenied' })
Assert ($denied.Count -eq 1 -and $denied[0].UserId -eq 666 -and $denied[0].Query.ExitCode -eq 1) 'Scan result must retain denial and original command failure.'
Assert (@($script:LastUserScanResults | Where-Object { $_.Status -eq 'Accessible' }).Count -eq 2) 'Scan result must distinguish accessible users from a denied user.'
$partial=Audit-AppStatus 'fake' $discovered @{ ApiLevel=36 }
Assert (-not $partial.UserScanComplete -and $partial.UserScan.Count -eq 3 -and $partial.Apps.Count -eq 2) 'Audit must record partial coverage while auditing accessible apps.'
Save-Report 'fake' 'partial-scan-test' $partial 6>$null
$savedPartial=Get-ChildItem -LiteralPath (Join-Path $script:ToolRoot 'reports') -Filter 'partial-scan-test_*.json' | Select-Object -First 1 | Get-Content -Raw -Encoding UTF8 | ConvertFrom-Json
Assert (-not $savedPartial.UserScanComplete -and $savedPartial.UserScan[1].Status -eq 'AccessDenied') 'Saved Audit JSON must retain the skipped scope.'

$script:Reads=@()
$explicit=@(Get-InstalledTargets 'fake' $testUsers @('com.example.chat') @(0,999))
Assert ($explicit.Count -eq 2 -and $script:Reads -notcontains 'shell pm list packages --user 666') 'Explicit accessible users must never query an unrelated protected user.'
Assert (@($script:LastUserScanResults | Where-Object { $_.Status -ne 'Accessible' }).Count -eq 0) 'Each scan must clear stale denial results.'
Assert ((Audit-AppStatus 'fake' $explicit @{ ApiLevel=36 }).UserScanComplete) 'Explicit accessible scope must be complete despite an unselected denied user.'
Assert-Throws { Get-InstalledTargets 'fake' $testUsers @('com.example.chat') @(666) } 'Explicit denied user must fail instead of falling back.'
Assert-Throws { Get-InstalledTargets 'fake' $testUsers @('com.example.chat') @(0,666) } 'An explicit mixed scope must fail as a whole before any fix.'
Assert-Throws { Get-InstalledTargets 'fake' @($testUsers[1]) @() @() 3>$null } 'All users denied must fail rather than return a successful empty scan.'
$missingMessage=''
try { Get-InstalledTargets 'fake' $testUsers @('com.example.absent') @() 3>$null | Out-Null } catch { $missingMessage=$_.Exception.Message }
Assert ($missingMessage -match 'User chua quet.*666') 'Missing package error must distinguish unscanned users from absent apps.'

# Denial handling depends on the actual response, not special user numbers.
$script:ReadFailures.Clear()
$script:ReadFailures['shell pm list packages --user 999']='Error: Shell does not have permission to access user 999'
$otherDenied=@(Get-InstalledTargets 'fake' $testUsers @('com.example.chat') @() 3>$null)
Assert ($otherDenied.UserId -contains 666 -and $otherDenied.UserId -notcontains 999) 'User 666 must be scanned when allowed; any actually denied user may be skipped.'
$script:ReadFailures.Clear()
foreach ($failure in @('adb: error: device offline','ADB timeout','SecurityException: unrelated failure','Error: Shell does not have permission to access user 6660')) {
    $script:ReadFailures['shell pm list packages --user 666']=$failure
    Assert-Throws { Get-InstalledTargets 'fake' $testUsers @() @() } "Unexpected failure must not be silently skipped: $failure"
}
$script:ReadFailures.Clear()

# Exercise the same startup path as the BAT, plus CLI Audit/Fix/Reapply safety.
& {
    function Select-Device { return 'fake' }
    function Get-DeviceMetadata { return @{ Serial='fake'; Model='Fake'; Android='16'; OriginOS='Test'; ApiLevel=36 } }
    function Read-Host { return '5' }
    $TargetPackage=@('com.example.chat')
    $script:ReadFailures['shell pm list packages --user 666']='Error: Shell does not have permission to access user 666'
    Assert ((Invoke-Main 3>$null 6>$null) -eq 0) 'Default launcher must reach the menu and exit despite a denied XSpace user.'
    $Audit=$true
    Assert ((Invoke-Main 3>$null 6>$null) -eq 2) 'CLI Audit must return partial status when a user was skipped.'
    $UserId=@('0,999')
    Assert ((Invoke-Main 6>$null) -eq 0) 'CLI Audit must succeed for explicitly accessible users.'
    $Audit=$false; $Fix=$true; $NoPrompt=$true; $UserId=@('0,666')
    Assert-Throws { Invoke-Main 6>$null } 'CLI Fix must reject a requested inaccessible user before writing.'
    $Fix=$false; $Reapply=$true; $TargetPackage=@(); $UserId=@()
    Save-TargetProfile 'fake' @([PSCustomObject]@{ Package='com.example.chat'; UserId=0 }, [PSCustomObject]@{ Package='com.example.chat'; UserId=666 }) $false $false $false $false ''
    Assert-Throws { Invoke-Main 6>$null } 'Reapply must reject a saved inaccessible user before writing any accessible target.'
    $script:ReadFailures.Clear()
}
Assert ($script:Writes.Count -eq 0) 'Discovery, Audit and denied Fix/Reapply must never mutate Android state.'

$targets=@([PSCustomObject]@{ Package='com.example.chat'; AppName='Chat'; UserId=999; Uid=99910306; GoogleOnly=$false })
$meta=@{ Serial='fake'; Model='Fake'; Android='16'; ApiLevel=36; OriginOS='Test' }
$script:Buckets['0/com.example.chat']=40
$plan=@(New-ChangePlan 'fake' $targets 36 $false $false $false $true)
Assert (@($plan | Where-Object { $_.Op -in @('SYSTEM_ALERT_WINDOW','USE_FULL_SCREEN_INTENT','AUTO_REVOKE_PERMISSIONS_IF_UNUSED') }).Count -eq 0) 'Advanced settings must be opt-in.'
Assert (@($plan | Where-Object { $_.Package -eq 'com.google.android.gms' }).Count -eq 2) 'Opt-in GMS changes must be journaled.'
Assert (@($plan | Where-Object { $_.Op -eq 'RUN_ANY_IN_BACKGROUND' }).Count -eq 1) 'Second background AppOp must be tracked.'
Assert ($script:Writes.Count -eq 0) 'Planning must not mutate.'
$journal=New-ChangeJournal $meta $targets $plan
$script:JournalUnderTest=$journal.Path; $script:CheckDurableIntent=$true
Invoke-ChangeJournal 'fake' $journal.Data $journal.Path 36
$script:CheckDurableIntent=$false
Assert (@($journal.Data.Entries | Where-Object { $_.Status -ne 'Verified' }).Count -eq 0) 'All fake changes must verify.'
Assert ($script:Buckets['0/com.example.chat'] -eq 40) 'Clone fix must leave user 0 bucket alone.'
Assert ($script:Grants['999/com.example.chat']) 'Runtime notification grant must apply to clone.'
$beforeReapply=$script:Writes.Count
$again=@(New-ChangePlan 'fake' $targets 36 $false $false $false $true)
Assert (@($again | Where-Object { $_.Status -ne 'AlreadySatisfied' }).Count -eq 0) 'Reapply should contain no writes when already satisfied.'
Assert ($script:Writes.Count -eq $beforeReapply) 'Reapply planning is read-only.'
Assert (Restore-FromGranularBackup 'fake' $journal.Path 36) 'Exact rollback should succeed.'
Assert (-not $script:Grants['999/com.example.chat']) 'Runtime grant must return to denied.'
Assert ($script:Ops['999/com.example.chat/POST_NOTIFICATION'] -eq 'default') 'Runtime companion AppOp must return to default.'
Assert ($script:Ops['999/com.example.chat/RUN_ANY_IN_BACKGROUND'] -eq 'default') 'Default background AppOp must be restored explicitly.'
Assert (-not $script:Doze['com.google.android.gms']) 'GMS Doze change must be restored.'
Assert ($script:Buckets['999/com.google.android.gms'] -eq 30) 'GMS bucket must restore for correct user.'
$writesBefore=$script:Writes.Count
Assert (Restore-FromGranularBackup 'fake' $journal.Path 36) 'Repeated restore is idempotent.'
Assert ($script:Writes.Count -eq $writesBefore) 'Repeated restore must issue no writes.'
Assert-Throws { Restore-FromGranularBackup 'other-phone' $journal.Path 36 } 'Wrong serial must be rejected.'

# Shared package Doze must be applied once even when both users are selected.
$both=@($targets[0], [PSCustomObject]@{ Package='com.example.chat'; AppName='Chat'; UserId=0; Uid=10306; GoogleOnly=$false })
$plan=@(New-ChangePlan 'fake' $both 36 $false $false $false $false)
Assert (@($plan | Where-Object { $_.Kind -eq 'Doze' }).Count -eq 1) 'Global package setting must be deduplicated.'
Assert (@($plan | Where-Object { $_.Kind -eq 'Bucket' }).Count -eq 2) 'Buckets must remain per user.'
$legacyAndroidPlan=@(New-ChangePlan 'fake' $targets 32 $false $false $false $false)
Assert (@($legacyAndroidPlan | Where-Object { $_.Kind -eq 'Permission' }).Count -eq 0) 'Pre-Android 13 must not attempt runtime notification grant.'
Assert (@($legacyAndroidPlan | Where-Object { $_.Op -eq 'POST_NOTIFICATION' }).Count -eq 1) 'Pre-Android 13 must still handle notification AppOp.'

# Missing UID, query failures, partial command failures, interrupted writes, conflicts.
$missing=@([PSCustomObject]@{ Package='com.example.missing'; AppName='Missing'; UserId=999; Uid=$null; GoogleOnly=$false })
$plan=@(New-ChangePlan 'fake' $missing 36 $false $false $false $false)
Assert (@($plan | Where-Object { $_.Status -ne 'Skipped' }).Count -eq 0) 'Missing UID cannot pass verification.'
$script:ReadFailures['shell cmd appops get --user 999 com.example.chat VIBRATE']='SecurityException'
$plan=@(New-ChangePlan 'fake' $targets 36 $false $false $false $false)
$journal=New-ChangeJournal $meta $targets $plan
Invoke-ChangeJournal 'fake' $journal.Data $journal.Path 36
$script:ReadFailures.Clear()
Assert (Restore-FromGranularBackup 'fake' $journal.Path 36) 'Skipped unknown AppOp must not prevent restoring known writes.'

$plan=@(New-ChangePlan 'fake' $targets 36 $false $false $false $false)
$journal=New-ChangeJournal $meta $targets $plan
$script:Failures['shell cmd appops set --user 999 com.example.chat RUN_ANY_IN_BACKGROUND allow']='Error: denied after partial change'
Invoke-ChangeJournal 'fake' $journal.Data $journal.Path 36
$failed=@($journal.Data.Entries | Where-Object { $_.Op -eq 'RUN_ANY_IN_BACKGROUND' })[0]
Assert ($failed.Status -eq 'Failed' -and $failed.Attempted -and $failed.AfterKnown) 'Nonzero command must stay failed even if state changed.'
$script:Failures.Clear()
Assert (Restore-FromGranularBackup 'fake' $journal.Path 36) 'Partial failed mutation must remain recoverable.'

$plan=@(New-ChangePlan 'fake' $targets 36 $false $false $false $false)
$journal=New-ChangeJournal $meta $targets $plan
$bucket=@($journal.Data.Entries | Where-Object { $_.Kind -eq 'Bucket' })[0]
$bucket.Status='Applying'; $bucket.Attempted=$true
Save-JsonAtomic $journal.Path $journal.Data
$script:Buckets['999/com.example.chat']=10
Assert (Restore-FromGranularBackup 'fake' $journal.Path 36) 'Crash between command and verification must be restorable.'

$plan=@(New-ChangePlan 'fake' $targets 36 $false $false $false $false)
$journal=New-ChangeJournal $meta $targets $plan
Invoke-ChangeJournal 'fake' $journal.Data $journal.Path 36
$script:Ops['999/com.example.chat/RUN_IN_BACKGROUND']='deny'
Assert (-not (Restore-FromGranularBackup 'fake' $journal.Path 36)) 'External change must cause a restore conflict.'
Assert ($script:Ops['999/com.example.chat/RUN_IN_BACKGROUND'] -eq 'deny') 'Conflict must not overwrite user setting.'
$script:UidOverrides['999/com.example.chat']=99910400
$writesBefore=$script:Writes.Count
Assert (-not (Restore-FromGranularBackup 'fake' $journal.Path 36)) 'UID drift must prevent restore.'
Assert ($script:Writes.Count -eq $writesBefore) 'UID mismatch must cause no writes.'
$script:UidOverrides.Clear()

# Preflight drift between preview and apply must never overwrite a new value.
$script:Ops['999/com.example.chat/RUN_IN_BACKGROUND']='default'
$plan=@(New-ChangePlan 'fake' $targets 36 $false $false $false $false)
$journal=New-ChangeJournal $meta $targets $plan
$script:Ops['999/com.example.chat/RUN_IN_BACKGROUND']='deny'
Invoke-ChangeJournal 'fake' $journal.Data $journal.Path 36
Assert (@($journal.Data.Entries | Where-Object { $_.Op -eq 'RUN_IN_BACKGROUND' -and $_.Status -eq 'Conflict' -and -not $_.Attempted }).Count -eq 1) 'Apply must reject drift after preview.'
Assert ($script:Ops['999/com.example.chat/RUN_IN_BACKGROUND'] -eq 'deny') 'Apply conflict must preserve changed setting.'
Assert (Restore-FromGranularBackup 'fake' $journal.Path 36) 'Restore must ignore a non-attempted apply conflict.'

# Permission flags that changed with a native grant/revoke are restored too.
$permissionEntry=[PSCustomObject]@{ Kind='Permission'; UserId=999; Package='com.example.chat' }
$script:FlagSets['999/com.example.chat']=@('USER_SENSITIVE_WHEN_DENIED')
$expectedPermission=[PSCustomObject]@{ Granted=$false; Flags=@('USER_SET','USER_SENSITIVE_WHEN_DENIED'); AppOp='default' }
$flagResult=Set-SettingState 'fake' $permissionEntry $expectedPermission 36
Assert ($flagResult.Success -and (Test-StateEqual (Get-SettingState 'fake' $permissionEntry 36).Value $expectedPermission)) 'Mutable permission flags must restore exactly.'

Assert-Throws { Get-InstalledTargets 'fake' @([PSCustomObject]@{Id=0;Name='Owner'}) @(',') @(0) } 'Empty package filter must never expand to all apps.'
Assert-Throws { Get-InstalledTargets 'fake' @([PSCustomObject]@{Id=0;Name='Owner'}) @('com.example;reboot') @(0) } 'Unsafe package input must be rejected.'
Assert-Throws { Get-InstalledTargets 'fake' @([PSCustomObject]@{Id=0;Name='Owner'}) @('com.example.chat') @(999) } 'Unknown user must be rejected.'

$legacy=Join-Path $script:ToolRoot 'legacy.json'
Save-JsonAtomic $legacy @{ Metadata=@{ Serial='fake' }; AppStates=@() }
Assert-Throws { Restore-FromGranularBackup 'fake' $legacy 36 } 'Legacy backup must not pretend to have a change journal.'

Save-TargetProfile 'fake' $targets $false $false $false $false 'original.json'
Save-TargetProfile 'fake' $targets $false $false $false $false 'reapply.json'
$profile=Get-Content -LiteralPath (Join-Path $script:ToolRoot 'backups\profile_fake.json') -Raw | ConvertFrom-Json
Assert ($profile.OriginalJournal -eq 'original.json' -and $profile.JournalHistory.Count -eq 2) 'Reapply must preserve original journal and history.'

# Updating the installed release must not destroy rollback data created by users.
$releaseFixture=Join-Path $script:ToolRoot 'release-fixture'
$fixtureTools=Join-Path $releaseFixture 'tools'
[void][System.IO.Directory]::CreateDirectory($fixtureTools)
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools') -File | Where-Object { $_.Extension -in @('.ps1','.bat') } | Copy-Item -Destination $fixtureTools
foreach ($name in @('README.md','HUONG_DAN_SU_DUNG.txt')) { Copy-Item -LiteralPath (Join-Path $projectRoot $name) -Destination $releaseFixture }
$preservedFiles=@()
foreach ($folder in @('backups','logs','reports')) {
    $fixtureDir=Join-Path $releaseFixture "Fix_ThongBao_Vivo_OriginOS\$folder"
    [void][System.IO.Directory]::CreateDirectory($fixtureDir)
    $fixtureFile=Join-Path $fixtureDir 'existing-user-data.txt'
    Set-Content -LiteralPath $fixtureFile -Value "Existing $folder must survive an upgrade." -Encoding UTF8
    $preservedFiles += [PSCustomObject]@{ Path=$fixtureFile; Hash=(Get-FileHash -LiteralPath $fixtureFile).Hash }
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureTools 'Build-Release.ps1') | Out-Null
Assert ($LASTEXITCODE -eq 0) 'Release build must succeed in an existing install containing runtime data.'
foreach ($existing in $preservedFiles) {
    Assert ((Test-Path -LiteralPath $existing.Path) -and (Get-FileHash -LiteralPath $existing.Path).Hash -eq $existing.Hash) 'Release sync must preserve existing runtime files byte for byte.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fixtureZip=[System.IO.Compression.ZipFile]::OpenRead((Join-Path $releaseFixture 'Fix_ThongBao_Vivo_OriginOS.zip'))
try { Assert (@($fixtureZip.Entries | Where-Object { $_.FullName -match '(^|[/\\])(backups|logs|reports)([/\\]|$)' }).Count -eq 0) 'Release ZIP must exclude runtime data even when the installed folder contains it.' }
finally { $fixtureZip.Dispose() }
Write-Host "PASS: $script:Assertions assertions; all Android writes were simulated. Artifacts: $script:ToolRoot" -ForegroundColor Green
