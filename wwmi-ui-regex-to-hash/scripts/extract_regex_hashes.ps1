#requires -Version 5
<#
.SYNOPSIS
    Extract pixel shader hashes matched by [ShaderRegex*] sections of a regex ini
    from d3d11_log.txt, dedupe them, and insert [ShaderOverride_*] sections into
    the target hash ini (preserving UTF-8 BOM and line endings).

.EXAMPLE
    .\extract_regex_hashes.ps1 -RegexIni ...\HideUI_Regex.ini -LogPath ...\d3d11_log.txt -HashIni ...\HideUI_Hash.ini -DryRun
#>
param(
    [Parameter(Mandatory = $true)][string]$RegexIni,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [Parameter(Mandatory = $true)][string]$HashIni,
    [string]$RunCommand = "CommandListUI",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

foreach ($p in @($RegexIni, $LogPath, $HashIni)) {
    if (-not (Test-Path $p)) { throw "file not found: $p" }
}
$iniName = [System.IO.Path]::GetFileName($RegexIni)

# 1. Collect [ShaderRegexXxx] section names (exclude [ShaderRegexXxx.Pattern])
$sections = Select-String -Path $RegexIni -Pattern '^\[ShaderRegex([^\.\]]+)\]\s*$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value } |
    Sort-Object -Unique
if (-not $sections) { throw "no [ShaderRegex*] sections found in $RegexIni" }
Write-Host "regex sections ($($sections.Count)): $($sections -join ', ')"

# 2. Scan log: ShaderRegex: ps_5_0 <hash> matches [ShaderRegex\...\<iniName>\<section>]
$alt = ($sections | ForEach-Object { [regex]::Escape($_) }) -join "|"
$logPattern = "ShaderRegex: ps_5_0 ([0-9a-f]{16}) matches \[ShaderRegex\\.*?\\$([regex]::Escape($iniName))\\($alt)\]"
$logMatches = Select-String -Path $LogPath -Pattern $logPattern
$hashes = @($logMatches | ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
Write-Host "log match lines: $($logMatches.Count); unique ps hashes: $($hashes.Count)"
if ($hashes.Count -eq 0) { Write-Host "nothing to insert."; return }

# 3. Read target ini, detect BOM
$bytes = [System.IO.File]::ReadAllBytes($HashIni)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$content = [System.IO.File]::ReadAllText($HashIni)
$nl = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }

# 4. Dedupe against hashes already present anywhere in the target ini
$newHashes = @($hashes | Where-Object { -not $content.Contains($_) })
$skipped = $hashes.Count - $newHashes.Count
Write-Host "new hashes to insert: $($newHashes.Count) (skipped already present: $skipped)"
if ($newHashes.Count -eq 0) { Write-Host "nothing to insert."; return }

# 5. Build sections and insert after the existing "run = <RunCommand>" block
$block = ($newHashes | ForEach-Object {
    "[ShaderOverride_$($_)]${nl}hash = $_${nl}allow_duplicate_hash = overrule${nl}run = $RunCommand"
}) -join "${nl}${nl}"

if ($DryRun) {
    Write-Host "---- DRY RUN: preview of first sections ----"
    ($newHashes | Select-Object -First 3) | ForEach-Object {
        Write-Host "[ShaderOverride_$($_)]${nl}hash = $_${nl}allow_duplicate_hash = overrule${nl}run = $RunCommand${nl}"
    }
    return
}

$needle = "run = $RunCommand"
$idx = $content.IndexOf($needle)
if ($idx -ge 0) {
    $idx2 = $idx + $needle.Length
    $newContent = $content.Substring(0, $idx2) + $nl + $nl + $block + $content.Substring($idx2)
}
else {
    # No existing ShaderOverride block: append at end
    $newContent = $content.TrimEnd() + $nl + $nl + $block + $nl
}

[System.IO.File]::WriteAllText($HashIni, $newContent, [System.Text.UTF8Encoding]::new($hasBom))
Write-Host "inserted $($newHashes.Count) ShaderOverride sections into $HashIni (BOM kept: $hasBom, EOL: $(if ($nl -eq "`r`n") { 'CRLF' } else { 'LF' }))"
