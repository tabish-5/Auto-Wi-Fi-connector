<#
 College WiFi Auto-Login (Fortinet captive portal) - PowerShell, no Python/Node needed

   .\wifi-login.ps1             run now (loops until online + grace period, then exits)
   .\wifi-login.ps1 -Install    auto-run at logon AND every time you connect to a network
   .\wifi-login.ps1 -Uninstall  remove the scheduled task

 Credentials are set in the script itself (edit the two lines under SETTINGS):
   $StudentId = 'YOUR_STUDENT_ID'   # ft_un
   $Password   = 'YOUR_PASSWORD'    # ft_pd
#>
param([switch]$Install, [switch]$Uninstall)

# ---------------- SETTINGS ----------------
$PortalBase   = 'http://10.2.0.10:8090'   # fallback if the redirect doesn't include a host
$ProbeUrl     = 'http://neverssl.com/'    # plain-HTTP site the firewall redirects
$Redir        = 'http://www.msftconnecttest.com/redirect'   # value for the 4Tredir field
$CheckEvery   = 5       # seconds between checks
$GraceSeconds = 5       # stay alive this long after Internet works, then exit
$GiveUpMin    = 5       # quit if never online after this many minutes
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
$StudentId = 'YOUR_STUDENT_ID'         # ft_un
$Password   = 'YOUR_PASSWORD'    # ft_pd
# ------------------------------------------

$TaskName = 'WiFi Auto-Login'
$Script   = $PSCommandPath
$Dir      = Split-Path -Parent $Script
$LogFile  = Join-Path $Dir 'wifi-login.log'

function Log($msg) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $msg
    Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    Write-Host $line
}

# ---------- install / uninstall ----------
if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed scheduled task '$TaskName'."
    return
}
if ($Install) {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Script`""
    $logon = New-ScheduledTaskTrigger -AtLogOn

    $cls = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $net = New-CimInstance -CimClass $cls -ClientOnly
    $net.Enabled = $true
    $net.Subscription = @'
<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[Provider[@Name='Microsoft-Windows-NetworkProfile'] and EventID=10000]]</Select></Query></QueryList>
'@
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logon, $net) `
        -Settings $settings -Force | Out-Null
    Write-Host 'Installed. Runs at logon and whenever you connect to a network.'
    Write-Host 'If you got an access error, re-run from an Administrator PowerShell.'
    return
}

# ---------- credentials ----------
if (-not $StudentId -or -not $Password) { Log 'Set $StudentId and $Password in the SETTINGS section'; exit 1 }
$cred = @{ ft_un = $StudentId; ft_pd = $Password }

# ---------- probe: online / portal / down ----------
# Requests neverssl.com WITHOUT following redirects. Fortinet answers with a 302 to
#   http://10.2.0.10:8090/fgtauth?<magic>
function Get-Probe {
    try {
        $req = [System.Net.HttpWebRequest]::Create($ProbeUrl)
        $req.AllowAutoRedirect = $false
        $req.Timeout = 5000
        $req.UserAgent = $UA
        $req.Proxy = $null
        $resp = $null
        try { $resp = $req.GetResponse() } catch { $resp = $_.Exception.Response }
        if (-not $resp) { return @{ State = 'down' } }

        $loc  = [string]$resp.Headers['Location']
        $code = [int]$resp.StatusCode
        $body = ''
        try {
            $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $body = $sr.ReadToEnd(); $sr.Close()
        } catch {}
        $resp.Close()

        $text = "$loc`n$body"
        if ($text -match 'fgtauth\?([0-9a-fA-F]+)') {
            $magic = $Matches[1]
            $base = $PortalBase
            if ($loc -match '^(https?://[^/]+)') { $base = $Matches[1] }
            elseif ($body -match '(https?://[^/"''\s]+)/fgtauth') { $base = $Matches[1] }
            return @{ State = 'portal'; Magic = $magic; Base = $base }
        }
        if ($code -eq 200) { return @{ State = 'online' } }
        return @{ State = 'down' }
    } catch {
        return @{ State = 'down' }
    }
}

# ---------- login ----------
$script:attempt = 0
function Invoke-PortalLogin($probe) {
    $script:attempt++
    $magic   = $probe.Magic
    $base    = $probe.Base
    $authUrl = "$base/fgtauth?$magic"
    Log "Portal found. magic=$magic  url=$authUrl  (attempt $($script:attempt))"

    $sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $fields = @{}
    $formAction = $null

    # Load the login page first (sets cookies, shows the real form fields)
    try {
        $page = Invoke-WebRequest -Uri $authUrl -UseBasicParsing -WebSession $sess `
            -UserAgent $UA -TimeoutSec 6
        $html = $page.Content
        foreach ($m in [regex]::Matches($html, '<input\b[^>]*>', 'IgnoreCase')) {
            $tag = $m.Value
            if ($tag -notmatch 'type\s*=\s*["'']?hidden') { continue }
            if ($tag -notmatch 'name\s*=\s*["'']?([^"''\s>]+)') { continue }
            $n = $Matches[1]; $v = ''
            if ($tag -match 'value\s*=\s*["'']([^"'']*)["'']') { $v = $Matches[1] }
            $fields[$n] = $v
        }
        if ($html -match '<form[^>]*action\s*=\s*["'']([^"'']*)["'']') {
            $formAction = ([Uri]::new([Uri]$authUrl, $Matches[1])).AbsoluteUri
        }
    } catch {
        Log "GET login page failed (continuing anyway): $($_.Exception.Message)"
    }

    if (-not $fields.ContainsKey('magic'))   { $fields['magic']   = $magic }
    if (-not $fields.ContainsKey('4Tredir')) { $fields['4Tredir'] = $Redir }
    $fields['username'] = $cred['ft_un']
    $fields['password'] = $cred['ft_pd']

    # Odd attempts: POST to /fgtauth?magic.  Even attempts: POST to the form's own action.
    $target = $authUrl
    if (($script:attempt % 2 -eq 0) -and $formAction) { $target = $formAction }

    Log "POST $target"
    try {
        $resp = Invoke-WebRequest -Uri $target -Method Post -Body $fields -WebSession $sess `
            -UseBasicParsing -UserAgent $UA -TimeoutSec 8 `
            -Headers @{ Referer = $authUrl; Origin = $base }
        Log "POST status $($resp.StatusCode)"
        if ($resp.Content -match '(https?://[^"''\s<>]*keepalive[^"''\s<>]*)') {
            $ka = $Matches[1]
            Log "Keepalive: $ka"
            try { Invoke-WebRequest -Uri $ka -UseBasicParsing -WebSession $sess -UserAgent $UA -TimeoutSec 6 | Out-Null } catch {}
        }
    } catch {
        Log "POST failed: $($_.Exception.Message)"
    }
}

# ---------- main loop ----------
Log 'Started'
$start = Get-Date
$onlineSince = $null
while ($true) {
    $p = Get-Probe
    switch ($p.State) {
        'online' {
            if (-not $onlineSince) { $onlineSince = Get-Date; Log 'Internet OK, grace period started' }
            if (((Get-Date) - $onlineSince).TotalSeconds -ge $GraceSeconds) { Log 'Grace period done, exiting'; exit 0 }
        }
        'portal' {
            $onlineSince = $null
            if (((Get-Date) - $start).TotalMinutes -ge $GiveUpMin) { Log 'Giving up (login never worked)'; exit 1 }
            Invoke-PortalLogin $p
            Start-Sleep -Seconds 2
            continue
        }
        default {
            $onlineSince = $null
            if (((Get-Date) - $start).TotalMinutes -ge $GiveUpMin) { Log 'Giving up (never got a connection)'; exit 1 }
        }
    }
    Start-Sleep -Seconds $CheckEvery
}
