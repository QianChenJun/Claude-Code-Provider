#!/usr/bin/env pwsh
[CmdletBinding()]
param([int]$Port = 0, [switch]$Foreground)
$ToolName = 'claude'
. "$PSScriptRoot\..\Manage-ProviderUI.ps1"