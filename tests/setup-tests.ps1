#!/usr/bin/env pwsh
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("provider-profile-tests-" + [guid]::NewGuid().ToString('N'))
$originalUserProfile = $env:USERPROFILE

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

try {
    New-Item -ItemType Directory -Force -Path $tempHome | Out-Null
    $env:USERPROFILE = $tempHome

    Import-Module (Join-Path $repoRoot 'src\core\ProviderCore.psm1') -Force -DisableNameChecking

    Assert-Equal `
        -Actual (Get-DefaultApiKeyEnvName -ToolName 'claude' -ProfileId 'mi-test') `
        -Expected 'MI_TEST_CLAUDE_API_KEY' `
        -Message 'Claude 默认环境变量名应由配置 ID 和工具名组成'

    Assert-Equal `
        -Actual (Get-DefaultApiKeyEnvName -ToolName 'codex' -ProfileId 'ds') `
        -Expected 'DS_CODEX_API_KEY' `
        -Message 'Codex 默认环境变量名应由配置 ID 和工具名组成'

    $result = Upsert-ProviderProfile `
        -ToolName 'claude' `
        -ProfileId 'mi-test' `
        -DisplayName '测试供应商' `
        -BaseUrl 'https://example.test/anthropic' `
        -Model 'test-model' `
        -ApiKey 'secret-value' `
        -EnvironmentTarget 'Process' `
        -Sync:$false

    Assert-True -Condition ($null -eq $result.ApiKeyEnv) -Message '未传 -ApiKeyEnv 时返回结果不应含 apiKeyEnv'
    Assert-True -Condition (-not $env:MI_TEST_CLAUDE_API_KEY) -Message '未传 -ApiKeyEnv 时不应写环境变量'

    $configPath = Join-Path $tempHome '.claude\provider-profiles\providers.json'
    Assert-True -Condition (Test-Path -LiteralPath $configPath) -Message '应写入 Claude providers.json'

    $config = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($configPath)) | ConvertFrom-Json
    $profile = $config.profiles.'mi-test'

    Assert-Equal -Actual $profile.displayName -Expected '测试供应商' -Message '应保存显示名称'
    Assert-Equal -Actual $profile.baseUrl -Expected 'https://example.test/anthropic' -Message '应保存 baseUrl'
    Assert-Equal -Actual $profile.authEnv -Expected 'ANTHROPIC_AUTH_TOKEN' -Message 'Claude 应写入默认 authEnv'
    Assert-True -Condition (-not ($profile.PSObject.Properties.Name -contains 'apiKeyEnv')) -Message '未传 -ApiKeyEnv 时不应写 apiKeyEnv 字段'
    Assert-Equal -Actual $profile.model -Expected 'test-model' -Message '应保存模型'
    Assert-Equal -Actual $profile.apiKey -Expected 'secret-value' -Message '应把 API Key 直接保存到 providers.json'

    Upsert-ProviderProfile `
        -ToolName 'claude' `
        -ProfileId 'mi-test' `
        -DisplayName '测试供应商更新' `
        -BaseUrl 'https://example.test/anthropic-updated' `
        -ApiKeyEnv 'CUSTOM_CLAUDE_API_KEY' `
        -EnvironmentTarget 'Process' `
        -Sync:$false | Out-Null

    Upsert-ProviderProfile `
        -ToolName 'claude' `
        -ProfileId 'mi-test' `
        -BaseUrl 'https://example.test/anthropic-updated-again' `
        -EnvironmentTarget 'Process' `
        -Sync:$false | Out-Null

    $updatedConfig = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($configPath)) | ConvertFrom-Json
    $updatedProfile = $updatedConfig.profiles.'mi-test'
    Assert-Equal -Actual $updatedProfile.displayName -Expected '测试供应商更新' -Message '未输入显示名称时应保留已有显示名称'
    Assert-Equal -Actual $updatedProfile.baseUrl -Expected 'https://example.test/anthropic-updated-again' -Message '应更新 baseUrl'
    Assert-Equal -Actual $updatedProfile.apiKeyEnv -Expected 'CUSTOM_CLAUDE_API_KEY' -Message '未输入 apiKeyEnv 时应保留已有环境变量名'
    Assert-Equal -Actual $updatedProfile.model -Expected 'test-model' -Message '未输入模型时应保留已有模型'
    Assert-Equal -Actual $updatedProfile.apiKey -Expected 'secret-value' -Message '未输入 ApiKey 时应保留已有 apiKey 字段'

    $reservedCommandProfileFailed = $false
    try {
        Upsert-ProviderProfile `
            -ToolName 'claude' `
            -ProfileId 'ccp-setup' `
            -BaseUrl 'https://example.test/anthropic' `
            -EnvironmentTarget 'Process' `
            -Sync:$false | Out-Null
    } catch {
        $reservedCommandProfileFailed = $true
    }
    Assert-True -Condition $reservedCommandProfileFailed -Message 'Upsert 阶段应拒绝会覆盖内置命令的配置 ID'

    Sync-ToolShortcuts -ToolName 'claude' | Out-Null
    $binDir = Join-Path $tempHome '.claude\bin'
    $setupShim = Join-Path $binDir 'ccp-setup.ps1'
    $profileShim = Join-Path $binDir 'ccp-mi-test.ps1'

    Assert-True -Condition (Test-Path -LiteralPath $setupShim) -Message '应生成 ccp-setup 快捷命令'
    Assert-True -Condition (Test-Path -LiteralPath $profileShim) -Message '应生成 ccp-<profile> 快捷命令'

    $setupShimText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($setupShim))
    Assert-True -Condition ($setupShimText -match '\bsetup\b') -Message 'ccp-setup 应调用 setup 子命令'

    $badShortcutConfig = Read-JsonFile -Path $configPath
    $badShortcutConfig.profiles.Remove('badshortcut')
    $badShortcutConfig.profiles['badshortcut'] = [ordered]@{
        displayName = '冲突快捷命令'
        baseUrl     = 'https://example.test/anthropic'
        apiKeyEnv   = 'BAD_SHORTCUT_CLAUDE_API_KEY'
        authEnv     = 'ANTHROPIC_AUTH_TOKEN'
        shortcut    = 'ccp-setup'
    }
    Write-Utf8NoBomJson -Path $configPath -Value $badShortcutConfig

    $shortcutConflictFailed = $false
    try {
        Sync-ToolShortcuts -ToolName 'claude' | Out-Null
    } catch {
        $shortcutConflictFailed = $true
    }
    Assert-True -Condition $shortcutConflictFailed -Message '自定义 shortcut 不应覆盖 ccp-setup 等内置命令'

    $badShortcutConfig.profiles.Remove('badshortcut')
    $badShortcutConfig.profiles['ccp-setup'] = [ordered]@{
        displayName = '冲突配置 ID'
        baseUrl     = 'https://example.test/anthropic'
        apiKeyEnv   = 'BAD_ID_CLAUDE_API_KEY'
        authEnv     = 'ANTHROPIC_AUTH_TOKEN'
    }
    Write-Utf8NoBomJson -Path $configPath -Value $badShortcutConfig

    $profileIdConflictFailed = $false
    try {
        Sync-ToolShortcuts -ToolName 'claude' | Out-Null
    } catch {
        $profileIdConflictFailed = $true
    }
    Assert-True -Condition $profileIdConflictFailed -Message '配置 ID 不应覆盖 ccp-setup 等内置命令'

    # === Advanced: 显式传 -ApiKey + -ApiKeyEnv 应写 env 变量（高级用法）===
    Upsert-ProviderProfile `
        -ToolName 'claude' `
        -ProfileId 'env-test' `
        -BaseUrl 'https://example.test/anthropic' `
        -ApiKey 'env-secret' `
        -ApiKeyEnv 'ENV_TEST_CLAUDE_API_KEY' `
        -EnvironmentTarget 'Process' `
        -Sync:$false | Out-Null
    Assert-Equal -Actual $env:ENV_TEST_CLAUDE_API_KEY -Expected 'env-secret' -Message '同时传 -ApiKey + -ApiKeyEnv 时应写 env 变量'
    $envTestConfig = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($configPath)) | ConvertFrom-Json
    Assert-Equal -Actual $envTestConfig.profiles.'env-test'.apiKeyEnv -Expected 'ENV_TEST_CLAUDE_API_KEY' -Message '显式 -ApiKeyEnv 应写入 apiKeyEnv 字段'
    Assert-Equal -Actual $envTestConfig.profiles.'env-test'.apiKey -Expected 'env-secret' -Message '显式 -ApiKey 同时也应写入 apiKey 字段（明文回退）'
    Remove-Item Env:\ENV_TEST_CLAUDE_API_KEY -ErrorAction SilentlyContinue

    # === Regression: mi / ds 作为普通配置 ID（不再被内置占用）===
    foreach ($profileId in @('mi', 'ds')) {
        Upsert-ProviderProfile `
            -ToolName 'codex' `
            -ProfileId $profileId `
            -DisplayName "供应商 $profileId" `
            -BaseUrl "https://example.test/$profileId" `
            -Model 'test-model' `
            -ApiKey "sk-$profileId" `
            -EnvironmentTarget 'Process' `
            -Sync:$false | Out-Null
    }
    Sync-ToolShortcuts -ToolName 'codex' | Out-Null
    $codexBin = Join-Path $tempHome '.codex\bin'
    $codexConfigPath = Join-Path $tempHome '.codex\provider-profiles\providers.json'
    $codexConfig = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($codexConfigPath)) | ConvertFrom-Json
    foreach ($profileId in @('mi', 'ds')) {
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $codexBin "$profileId.ps1")) -Message "应生成 $profileId.ps1（配置 ID 直呼）"
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $codexBin "$profileId-codex.ps1")) -Message "应生成 $profileId-codex.ps1（默认 shortcut）"
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $codexBin "cdp-$profileId.ps1")) -Message "应生成 cdp-$profileId.ps1（前缀形式）"
        Assert-Equal -Actual $codexConfig.profiles.$profileId.apiKey -Expected "sk-$profileId" -Message "$profileId 应把 apiKey 直接写入 providers.json"
    }
    Remove-Item Env:\MI_CODEX_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\DS_CODEX_API_KEY -ErrorAction SilentlyContinue

    $invalidUrlFailed = $false
    try {
        Upsert-ProviderProfile `
            -ToolName 'codex' `
            -ProfileId 'bad' `
            -BaseUrl 'not-a-url' `
            -EnvironmentTarget 'Process' `
            -Sync:$false | Out-Null
    } catch {
        $invalidUrlFailed = $true
    }
    Assert-True -Condition $invalidUrlFailed -Message '无效 baseUrl 应被拒绝'

    Write-Output 'setup-tests: PASS'
}
finally {
    $env:USERPROFILE = $originalUserProfile
    Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\MI_TEST_CLAUDE_API_KEY -ErrorAction SilentlyContinue
}
