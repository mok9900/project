$ErrorActionPreference = 'Stop'
$root = Join-Path $env:RUNNER_TEMP 'windows-test'
New-Item -ItemType Directory -Path $root -Force | Out-Null

function Download-Checked($Url, $Path, $Sha256) {
    Invoke-WebRequest -Uri $Url -OutFile $Path
    if ((Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha256) {
        throw "Download checksum mismatch: $Path"
    }
}

$password = 'Aa1!' + [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(20))
$pathKey = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).ToLowerInvariant()
Write-Output "::add-mask::$password"
Write-Output "::add-mask::$pathKey"
New-LocalUser -Name kasmtest -Password (ConvertTo-SecureString $password -AsPlainText -Force) -Description 'Temporary repository test desktop' | Out-Null
Add-LocalGroupMember -Group Administrators -Member kasmtest
Add-LocalGroupMember -Group 'Remote Desktop Users' -Member kasmtest
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1
Start-Service TermService
# RDP is reached through loopback only; do not open the Windows firewall.

Download-Checked 'https://github.com/erebe/wstunnel/releases/download/v10.7.1/wstunnel_10.7.1_windows_amd64.tar.gz' "$root\wstunnel.tar.gz" 'deb3c8b8d9fecf5428f7e0caabbc13aeb3b1edbfba49e1724a7a065c027bd0f2'
tar -xzf "$root\wstunnel.tar.gz" -C $root
if ($LASTEXITCODE -ne 0) { throw 'wstunnel extraction failed' }
Download-Checked 'https://github.com/cloudflare/cloudflared/releases/download/2026.9.1/cloudflared-windows-amd64.exe' "$root\cloudflared.exe" '2837888cc0f5d58f15b6dc478376de90b4d3ba5241c7947455d1e0a0df429712'

Start-Process "$root\wstunnel.exe" -ArgumentList @('server', '--restrict-to', '127.0.0.1:3389', '--restrict-http-upgrade-path-prefix', $pathKey, 'ws://127.0.0.1:8080') -RedirectStandardOutput "$root\wstunnel.out.log" -RedirectStandardError "$root\wstunnel.err.log" | Out-Null
Start-Process "$root\cloudflared.exe" -ArgumentList @('tunnel', '--url', 'http://127.0.0.1:8080', '--no-autoupdate', '--protocol', 'http2') -RedirectStandardOutput "$root\cloudflared.out.log" -RedirectStandardError "$root\cloudflared.err.log" | Out-Null
$url = $null
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 2
    $log = Get-Content "$root\cloudflared.err.log" -Raw -ErrorAction SilentlyContinue
    $match = [regex]::Match([string]$log, 'https://[a-z0-9-]+\.trycloudflare\.com')
    if ($match.Success) { $url = $match.Value; break }
}
if (-not $url) { throw 'Cloudflare test tunnel did not start' }

# Only the Codespaces private key can decrypt this public-repository artifact.
$connection = @{ url = $url; path = $pathKey; user = 'kasmtest'; password = $password; run = $env:GITHUB_RUN_ID } | ConvertTo-Json -Compress
$rsa = [Security.Cryptography.RSA]::Create()
try {
    $rsa.ImportFromPem((Get-Content "$PSScriptRoot/session-public.pem" -Raw))
    $cipher = $rsa.Encrypt([Text.Encoding]::UTF8.GetBytes($connection), [Security.Cryptography.RSAEncryptionPadding]::OaepSHA256)
    [IO.File]::WriteAllBytes("$root\connection.enc", $cipher)
} finally { $rsa.Dispose() }

# Make the checked-out project available to the interactive test user.
Copy-Item $env:GITHUB_WORKSPACE 'C:\Users\Public\Desktop\project' -Recurse -Force
Write-Output 'Windows test account and encrypted connection artifact are ready.'
