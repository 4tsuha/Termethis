param([string]$Distro = 'Ubuntu')

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$existingPid = (& wsl.exe -d $Distro -u root -- cat /run/sshd-termethis-test.pid 2>$null)
if ($existingPid -match '^\d+$') {
    & wsl.exe -d $Distro -u root -- kill $existingPid 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to stop the isolated sshd.'
    }
}
$ErrorActionPreference = $previousErrorAction
