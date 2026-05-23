#!/usr/bin/env pwsh
# Generic sync script — dot-sourced by tool-specific wrappers.
# The wrapper must set $ToolName before dot-sourcing.

$ErrorActionPreference = 'Stop'

if (-not $ToolName) { throw 'Internal error: $ToolName not set by wrapper script.' }

. (Join-Path $PSScriptRoot 'Import-Core.ps1')
Import-ProviderCore
Sync-ToolShortcuts -ToolName $ToolName