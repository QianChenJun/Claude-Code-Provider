#!/usr/bin/env pwsh
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Import-Core.ps1')
Import-ProviderCore
Sync-ToolShortcuts -ToolName 'claude'