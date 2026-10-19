$ErrorActionPreference = 'Stop'
$expected = @{
    'bounded-mobile-diffs.patch' = '98A815FC12EADEBBC7DE61381633D055572D5EA2D35B73CA57D7457F6385B5AB'
    'lock-local-versions.patch' = 'B01D56ED6F85F3ABB9CFEA19D9915EF43F0F22669DF68A305561C920695BFA12'
}
foreach ($entry in $expected.GetEnumerator()) {
    if ((Get-FileHash -LiteralPath "$PSScriptRoot\$($entry.Key)" -Algorithm SHA256).Hash -ne $entry.Value) {
        throw "Patch hash mismatch: $($entry.Key)"
    }
}
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted') {
    throw 'Run only on a GitHub-hosted runner, never on the local PC.'
}
New-Item -ItemType Directory -Path D:\codex-public,D:\codex-results,D:\codex-fixture-home | Out-Null
git -C D:\codex-public init
if ($LASTEXITCODE) { throw 'git init failed' }
git -C D:\codex-public -c core.longpaths=true fetch --depth=1 https://github.com/openai/codex.git 4ebc485ca321243727539187169425fcf972f2c4
if ($LASTEXITCODE) { throw 'Source fetch failed' }
git -C D:\codex-public -c core.longpaths=true -c core.autocrlf=false checkout --detach FETCH_HEAD
if ($LASTEXITCODE) { throw 'Source checkout failed' }
if ((git -C D:\codex-public rev-parse HEAD) -ne '4ebc485ca321243727539187169425fcf972f2c4') { throw 'Source revision mismatch' }
foreach ($file in @('bounded-mobile-diffs.patch','lock-local-versions.patch')) {
    git -C D:\codex-public apply --check "$PSScriptRoot\$file"
    if ($LASTEXITCODE) { throw "Patch check failed: $file" }
    git -C D:\codex-public apply "$PSScriptRoot\$file"
    if ($LASTEXITCODE) { throw "Patch application failed: $file" }
}
git -C D:\codex-public diff --check
if ($LASTEXITCODE) { throw 'Whitespace check failed' }
Copy-Item D:\codex-public\LICENSE,D:\codex-public\NOTICE -Destination D:\codex-results
@('Source: https://github.com/openai/codex','Commit: 4ebc485ca321243727539187169425fcf972f2c4','Unofficial patched test build. No installation or deployment.') | Set-Content D:\codex-results\PROVENANCE.txt
rustup toolchain install 1.95.0 --profile minimal --no-self-update
if ($LASTEXITCODE) { throw 'Rust installation failed' }
rustc +1.95.0 --version | Tee-Object D:\codex-results\rust-version.txt
if ($LASTEXITCODE) { throw 'Rust version check failed' }
Set-Location D:\codex-public\codex-rs
cargo +1.95.0 test --locked -p codex-git-utils -j 1 -- --test-threads=1 2>&1 | Tee-Object D:\codex-results\git-utils-tests.txt
if ($LASTEXITCODE) { throw 'Git utility tests failed' }
cargo +1.95.0 build --locked -p codex-cli --bin codex -j 1 2>&1 | Tee-Object D:\codex-results\build.txt
if ($LASTEXITCODE) { throw 'Complete CLI build failed' }
$binary = 'D:\codex-target\debug\codex.exe'
$version = & $binary --version
if ($LASTEXITCODE -or $version -notmatch '0\.163\.0-alpha\.10\.2') { throw 'Unexpected binary version' }
$version | Set-Content D:\codex-results\binary-version.txt
& $binary app-server --help | Set-Content D:\codex-results\app-server-help.txt
if ($LASTEXITCODE) { throw 'App-server startup smoke test failed' }
Copy-Item -LiteralPath $binary -Destination D:\codex-results\codex.exe
Get-FileHash D:\codex-results\codex.exe -Algorithm SHA256 | Format-List | Out-File D:\codex-results\SHA256.txt
'Tests, build, version and startup smoke test passed. Mobile end-to-end validation is still pending.' | Set-Content D:\codex-results\VALIDATED.txt
