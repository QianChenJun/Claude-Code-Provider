#!/usr/bin/env pwsh
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ToolName)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Import-Core.ps1')
Import-ProviderCore
Sync-ToolShortcuts -ToolName $ToolName