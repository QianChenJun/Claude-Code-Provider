#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [ValidateSet('utf8', 'utf8bom', 'unicode', 'bigendianunicode', 'utf32', 'ascii', 'default')]
    [string]$Encoding = 'utf8'
)

$ErrorActionPreference = 'Stop'

$resolvedPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
$bytes = [System.IO.File]::ReadAllBytes($resolvedPath)

$textEncoding = switch ($Encoding) {
    'utf8' { [System.Text.Encoding]::UTF8; break }
    'utf8bom' { [System.Text.UTF8Encoding]::new($true); break }
    'unicode' { [System.Text.Encoding]::Unicode; break }
    'bigendianunicode' { [System.Text.Encoding]::BigEndianUnicode; break }
    'utf32' { [System.Text.Encoding]::UTF32; break }
    'ascii' { [System.Text.Encoding]::ASCII; break }
    default { [System.Text.Encoding]::Default; break }
}

$textEncoding.GetString($bytes)
