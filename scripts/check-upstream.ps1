param([string]$UpstreamPath = '')

$ErrorActionPreference = 'Stop'
$taskRepoRoot = Split-Path -Parent $PSScriptRoot
$taskBaseline = Get-Content -Raw -Encoding UTF8 (Join-Path $taskRepoRoot 'docs/upstream-baseline.json') | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($UpstreamPath)) {
    $UpstreamPath = Join-Path (Split-Path -Parent $taskRepoRoot) 'lxserver-mobile-upstream'
}
$taskUpstream = (Resolve-Path -LiteralPath $UpstreamPath).Path
$taskPackage = Get-Content -Raw -Encoding UTF8 (Join-Path $taskUpstream 'package.json') | ConvertFrom-Json
$taskCommit = & git -C $taskUpstream rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot read upstream commit.' }
$taskTagCommit = & git -C $taskUpstream rev-parse "$($taskBaseline.tag)^{commit}"
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the baseline tag; verify the checkout before relying on it.' }
$taskDirty = & git -C $taskUpstream status --porcelain
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect upstream working tree.' }
if ($taskPackage.version -ne $taskBaseline.version -or $taskCommit -ne $taskBaseline.commit -or $taskTagCommit -ne $taskBaseline.commit) {
    throw 'Upstream does not match docs/upstream-baseline.json. Review the target version and API differences; do not silently update the baseline.'
}
if ($taskDirty) { throw 'Upstream has local changes. Check relevant diffs before treating this checkout as baseline evidence.' }
Write-Output "Source baseline verified: $($taskBaseline.tag) / $taskCommit"
Write-Output 'Read-only check; this does not certify a deployed server or change any repository.'
