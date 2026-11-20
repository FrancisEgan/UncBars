# Packaging implementation; run ./make from Git Bash.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$addonName = 'UncBars'
$tocName = "$addonName.toc"
$toc = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot $tocName))
$versions = @($toc | ForEach-Object {
    if ($_ -match '^\s*##\s*Version:\s*(.*?)\s*$') { $Matches[1] }
})
if ($versions.Count -ne 1 -or $versions[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
    throw "$tocName must contain one valid ## Version: value."
}

# The TOC is the allowlist: repository files and tests never enter the archive.
$files = @($tocName) + @($toc | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#')) { $line }
})
$root = [IO.Path]::GetFullPath($PSScriptRoot) + [IO.Path]::DirectorySeparatorChar
$entries = @(foreach ($file in ($files | Select-Object -Unique)) {
    $source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $file))
    if (-not $source.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "TOC entry must stay inside the addon directory: $file"
    }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing addon file: $file"
    }
    [PSCustomObject]@{
        Source = $source
        Name = "$addonName/" + $source.Substring($root.Length).Replace('\', '/')
    }
})

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$outputDirectory = Join-Path $PSScriptRoot 'dist'
$null = New-Item -ItemType Directory -Path $outputDirectory -Force
$destination = Join-Path $outputDirectory "$addonName $($versions[0]).zip"
$temporary = Join-Path $outputDirectory ('.package-' + [Guid]::NewGuid().ToString('N') + '.zip')
$archive = $null
try {
    $archive = [IO.Compression.ZipFile]::Open($temporary, [IO.Compression.ZipArchiveMode]::Create)
    foreach ($entry in $entries) {
        $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $entry.Source, $entry.Name, [IO.Compression.CompressionLevel]::Optimal)
    }
    $archive.Dispose()
    $archive = $null
    Move-Item -LiteralPath $temporary -Destination $destination -Force
}
finally {
    if ($null -ne $archive) { $archive.Dispose() }
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}

Write-Output "Created $destination ($($entries.Count) files)"
