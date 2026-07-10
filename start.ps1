# Starts the game (like start.bat).
# Usage:  .\start.ps1            (play the game)
#         .\start.ps1 -Editor    (open the project in the Godot editor)
param(
    [switch]$Editor
)

$godotExe = "C:\dev\godot\Godot_v4.7-stable_win64.exe"
$projectDir = $PSScriptRoot

if (-not (Test-Path $godotExe)) {
    Write-Error "Godot was not found at '$godotExe'. Install it there or update `$godotExe in this script."
    exit 1
}

$godotArgs = @("--path", "`"$projectDir`"")
if ($Editor) {
    $godotArgs = @("--editor") + $godotArgs
}

Start-Process $godotExe -ArgumentList $godotArgs
