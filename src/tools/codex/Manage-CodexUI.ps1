#!/usr/bin/env pwsh
[CmdletBinding()]
param([int]$Port = 0, [switch]$Foreground)
$ToolName = 'codex'
. "$PSScriptRoot\..\Manage-ProviderUI.ps1"