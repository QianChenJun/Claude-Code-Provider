#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("provider-core-function-tests-" + [guid]::NewGuid().ToString('N'))
$originalUserProfile = $env:USERPROFILE
$testEnvName = "PROVIDER_CORE_TEST_KEY_$([guid]::NewGuid().ToString('N'))"

function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Message
    )
    if ("$Actual" -ne "$Expected") {
        throw "$Message。期望：$Expected，实际：$Actual"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Write-Utf8Text {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Text
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

try {
    New-Item -ItemType Directory -Force -Path $tempHome | Out-Null
    $env:USERPROFILE = $tempHome

    Import-Module (Join-Path $repoRoot 'src\core\ProviderCore.psm1') -Force -DisableNameChecking

    $jsonPath = Join-Path $tempHome 'json\nested.json'
    Write-Utf8Text -Path $jsonPath -Text @'
{
  "emptyObject": {},
  "emptyArray": [],
  "singleArray": ["only"],
  "nested": {
    "items": [
      { "name": "first", "enabled": true },
      [1, 2]
    ],
    "count": 2
  }
}
'@

    $config = Read-JsonFile -Path $jsonPath
    Assert-True -Condition ($config -is [System.Collections.IDictionary]) -Message 'Read-JsonFile 应把顶层 JSON 对象转成字典'
    Assert-True -Condition ($config.emptyObject -is [System.Collections.IDictionary]) -Message '空 JSON 对象应转成空字典'
    Assert-Equal -Actual $config.emptyObject.Count -Expected 0 -Message '空 JSON 对象不应保留为 PSCustomObject'
    Assert-True -Condition ($config.emptyArray -is [object[]]) -Message '空 JSON 数组应保留为数组'
    Assert-Equal -Actual $config.emptyArray.Count -Expected 0 -Message '空 JSON 数组不应被转换成 null'
    Assert-True -Condition ($config.singleArray -is [object[]]) -Message '单元素 JSON 数组应保留为数组'
    Assert-Equal -Actual $config.singleArray.Count -Expected 1 -Message '单元素 JSON 数组应保留元素数量'
    Assert-True -Condition ($config.nested.items[0] -is [System.Collections.IDictionary]) -Message '数组内对象应递归转成字典'
    Assert-True -Condition ($config.nested.items[1] -is [object[]]) -Message '嵌套数组应保留为数组'
    Assert-Equal -Actual $config.nested.items[1][1] -Expected 2 -Message '嵌套数组元素应可按索引读取'

    $emptyJsonPath = Join-Path $tempHome 'json\empty.json'
    Write-Utf8Text -Path $emptyJsonPath -Text '   '
    $emptyConfig = Read-JsonFile -Path $emptyJsonPath
    Assert-True -Condition ($emptyConfig -is [System.Collections.IDictionary]) -Message '空白 JSON 文件应返回空字典'
    Assert-Equal -Actual $emptyConfig.Count -Expected 0 -Message '空白 JSON 文件返回的字典应为空'

    $directKey = Resolve-ApiKey -Profile @{ apiKey = 'direct-secret' } -ProfileId 'direct'
    Assert-Equal -Actual $directKey -Expected 'direct-secret' -Message 'Resolve-ApiKey 应读取明文 apiKey'

    [Environment]::SetEnvironmentVariable($testEnvName, 'env-secret', 'Process')
    $envKey = Resolve-ApiKey -Profile @{ apiKey = 'direct-secret'; apiKeyEnv = $testEnvName } -ProfileId 'env'
    Assert-Equal -Actual $envKey -Expected 'env-secret' -Message 'Resolve-ApiKey 应优先使用已设置的 apiKeyEnv'

    $keyFile = Join-Path $tempHome 'keys\api-key.txt'
    Write-Utf8Text -Path $keyFile -Text " file-secret `r`n"
    $fileKey = Resolve-ApiKey -Profile @{ apiKey = 'direct-secret'; apiKeyEnv = $testEnvName; apiKeyFile = $keyFile } -ProfileId 'file'
    Assert-Equal -Actual $fileKey -Expected 'file-secret' -Message 'Resolve-ApiKey 应用 apiKeyFile 覆盖 env/direct 并裁剪空白'

    $missingFailed = $false
    try {
        Resolve-ApiKey -Profile @{} -ProfileId 'missing' | Out-Null
    }
    catch {
        $missingFailed = ($_.Exception.Message -match "配置 'missing' 缺少 apiKey")
    }
    Assert-True -Condition $missingFailed -Message 'Resolve-ApiKey 缺少密钥时应抛出可读错误'

    Write-Output 'core-function-tests: PASS'
}
finally {
    [Environment]::SetEnvironmentVariable($testEnvName, $null, 'Process')
    $env:USERPROFILE = $originalUserProfile
    Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}
