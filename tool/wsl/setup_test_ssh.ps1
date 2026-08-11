param(
    [string]$Distro = 'Ubuntu',
    [string]$TestUser = 'termethis-test',
    [Parameter(Mandatory = $true)]
    [string]$Password
)

$ErrorActionPreference = 'Stop'
$configPath = (Resolve-Path (Join-Path $PSScriptRoot 'sshd_config')).Path
$drive = $configPath.Substring(0, 1).ToLowerInvariant()
$relativePath = $configPath.Substring(2).Replace('\', '/')
$wslConfigPath = "/mnt/$drive$relativePath"

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& wsl.exe -d $Distro -u root -- test -x /usr/sbin/sshd 2>$null
$packageStatus = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
if ($packageStatus -ne 0) {
    & wsl.exe -d $Distro -u root -- apt-get update
    if ($LASTEXITCODE -ne 0) { throw 'apt-get update failed.' }
    & wsl.exe -d $Distro -u root -- env DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install openssh-server.' }
}

$userEntry = & wsl.exe -d $Distro -u root -- getent passwd $TestUser
if ([string]::IsNullOrWhiteSpace($userEntry)) {
    & wsl.exe -d $Distro -u root -- useradd --create-home --shell /bin/bash $TestUser
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the test user.' }
}

$credential = "${TestUser}:$Password"
$encodedCredential = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($credential)
)
& wsl.exe -d $Distro -u root -- sh -c "printf '%s' '$encodedCredential' | base64 -d | chpasswd"
if ($LASTEXITCODE -ne 0) { throw 'Failed to set the test user password.' }

& wsl.exe -d $Distro -u root -- ssh-keygen -A
& wsl.exe -d $Distro -u root -- install -m 600 $wslConfigPath /etc/ssh/sshd_config_termethis_test
& wsl.exe -d $Distro -u root -- mkdir -p /run/sshd
& wsl.exe -d $Distro -u root -- /usr/sbin/sshd -t -f /etc/ssh/sshd_config_termethis_test
if ($LASTEXITCODE -ne 0) { throw 'The isolated sshd config is invalid.' }

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$existingPid = (& wsl.exe -d $Distro -u root -- cat /run/sshd-termethis-test.pid 2>$null)
if ($existingPid -match '^\d+$') {
    & wsl.exe -d $Distro -u root -- kill $existingPid 2>$null
}
$ErrorActionPreference = $previousErrorAction
& wsl.exe -d $Distro -u root -- /usr/sbin/sshd -f /etc/ssh/sshd_config_termethis_test
if ($LASTEXITCODE -ne 0) { throw 'Failed to start the isolated sshd.' }

Write-Output 'WSL SSH test server: 127.0.0.1:22222'
Write-Output "User: $TestUser"
