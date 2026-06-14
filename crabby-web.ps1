<#
.SYNOPSIS
    Start Crabby AI Web UI
.DESCRIPTION
    Launch the Crabby web server and open the chat interface in your browser.
#>

param(
    [int]$Port = 8420
)

$RootDir = $PSScriptRoot
. "$RootDir\src\Server.ps1" -RootDir $RootDir -Port $Port
