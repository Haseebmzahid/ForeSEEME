param([string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $repo 'pubspec.yaml'))) { throw 'RepositoryRoot must point to the ForeSeeMe repository.' }
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$runDir = Join-Path $repo "evaluation_60/demo_runs/$stamp"
New-Item -ItemType Directory -Path $runDir | Out-Null
Push-Location -LiteralPath $repo
try {
    Write-Host 'Running existing dose and recovery Flutter tests...'
    & flutter test --no-pub test/features/medication/dose_state_boundaries_test.dart test/features/auth/forgot_password_screen_test.dart --reporter expanded 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'flutter.log')
    $flutterExit = $LASTEXITCODE
    Push-Location -LiteralPath (Join-Path $repo 'backend')
    try {
        Write-Host 'Running existing API validation tests...'
        & python -m pytest tests/test_api_validation_boundary.py -q "--basetemp=$runDir/pytest-temp" "--junitxml=$runDir/backend.xml" 2>&1 | Tee-Object -FilePath (Join-Path $runDir 'backend.log')
        $backendExit = $LASTEXITCODE
    } finally { Pop-Location }
    [ordered]@{startedUtc=$stamp;flutterExit=$flutterExit;backendExit=$backendExit;scope='Targeted host tests, not device or full regression'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runDir 'run-summary.json')
    Write-Host "Evidence saved to $runDir"
    if ($flutterExit -ne 0 -or $backendExit -ne 0) { throw "Tests failed: Flutter exit $flutterExit, backend exit $backendExit. Preserve the logs and report the failure." }
} finally { Pop-Location }
