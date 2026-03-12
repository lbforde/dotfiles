$consoleProfilePath = Join-Path $PSScriptRoot "Microsoft.PowerShell_profile.ps1"
if (Test-Path -LiteralPath $consoleProfilePath) {
    . $consoleProfilePath
}
else {
    Write-Warning "Managed PowerShell profile not found at $consoleProfilePath"
}
