# ============================================================
# RomRaiderTools.psm1
# Unified module for managing RomRaider XML definition packs
# ============================================================

# ------------------------------------------------------------
# Shared: Logging
# ------------------------------------------------------------
function Write-Log {
    param([string]$Message)

    $LogDir = Join-Path $HOME ".RomRaider"
    if (!(Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir | Out-Null
    }

    $LogFile = Join-Path $LogDir "module_$(Get-Date -Format yyyyMMdd).log"
    Add-Content -Path $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

# ------------------------------------------------------------
# Shared: Detect Type (ECU / Logger / Dyno)
# ------------------------------------------------------------
function Detect-DefinitionType {
    param([string]$XmlPath)

    $Name    = Split-Path $XmlPath -Leaf
    $Content = Get-Content $XmlPath -Raw

    if ($Name -match "ecu" -or $Content -match "<rom>" -or $Content -match "<ecu") { return "ecu" }
    if ($Name -match "logger" -or $Content -match "<logger") { return "logger" }
    if ($Name -match "dyno" -or $Content -match "<dyno") { return "dyno" }

    return $null
}

# ------------------------------------------------------------
# Shared: Detect Mode (Standard / Metric)
# ------------------------------------------------------------
function Detect-DefinitionMode {
    param([string]$XmlPath)

    $Name    = Split-Path $XmlPath -Leaf
    $Folder  = Split-Path $XmlPath -Parent
    $Content = Get-Content $XmlPath -Raw

    # 1. Filename-based detection
    if ($Name -match 'metric')   { return 'metric' }
    if ($Name -match 'standard') { return 'standard' }

    # 2. Content-based detection
    if ($Content -match 'metric')   { return 'metric' }
    if ($Content -match 'standard') { return 'standard' }

    # 3. Folder-based detection (handles "subaru metric", "metric", etc.)
    if ($Folder -match '(?i)metric')   { return 'metric' }
    if ($Folder -match '(?i)standard') { return 'standard' }

    # 4. No detection possible
    return $null
}

# ------------------------------------------------------------
# FUNCTION 1: Place-Definition
# ------------------------------------------------------------
function Place-Definition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$XmlPath,

        [switch]$Force,
        [switch]$DryRun,
        [switch]$SkipExisting
    )

    if (-not (Test-Path $XmlPath)) {
        Write-Host "File not found: $XmlPath"
        Write-Log "Place-Definition: File not found: $XmlPath"
        return [pscustomobject]@{
            Path         = $XmlPath
            Status       = 'Missing'
            Type         = $null
            Mode         = $null
            DestFile     = $null
            Skipped      = $true
            Reason       = 'Source file not found'
            Dependencies = @()
        }
    }

    $Type = Detect-DefinitionType $XmlPath
    if (-not $Type) {
        Write-Host "Unknown definition type for: $XmlPath"
        Write-Log "Place-Definition: Unknown type for $XmlPath"
        return [pscustomobject]@{
            Path         = $XmlPath
            Status       = 'UnknownType'
            Type         = $null
            Mode         = $null
            DestFile     = $null
            Skipped      = $true
            Reason       = 'Unknown definition type'
            Dependencies = @()
        }
    }

    $Mode = $null
    if ($Type -ne 'dyno') {
        $Mode = Detect-DefinitionMode $XmlPath
        if (-not $Mode) {
            Write-Host "Unable to detect mode for: $XmlPath"
            Write-Host "1) Standard"
            Write-Host "2) Metric"
            $choice = Read-Host "Select mode"
            if     ($choice -eq "1") { $Mode = "standard" }
            elseif ($choice -eq "2") { $Mode = "metric" }
            else {
                Write-Log "Place-Definition: Mode selection aborted for $XmlPath"
                return [pscustomobject]@{
                    Path         = $XmlPath
                    Status       = 'ModeUndetected'
                    Type         = $Type
                    Mode         = $null
                    DestFile     = $null
                    Skipped      = $true
                    Reason       = 'Mode not detected / user aborted'
                    Dependencies = @()
                }
            }
        }
    }

    # Base + destination directory
    $Base = Join-Path $PSScriptRoot "..\..\definitions"
    if ($Type -eq 'dyno') {
        $DestDir = Join-Path $Base $Type
    } else {
        $DestDir = Join-Path $Base "$Type\$Mode"
    }

    if (-not (Test-Path $DestDir)) {
        if ($DryRun) {
            Write-Host "[DRY-RUN] Would create directory: $DestDir"
            Write-Log  "DRY-RUN: Would create directory $DestDir"
        } else {
            New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
            Write-Log "Created directory: $DestDir"
        }
    }

    # Collision-proof destination naming: start with original filename
    $BaseName = Split-Path $XmlPath -Leaf
    $DestFile = Join-Path $DestDir $BaseName

    if (Test-Path $DestFile) {
        if ($SkipExisting -and -not $Force) {
            Write-Host "Skipping existing: $DestFile"
            Write-Log  "Skipping existing (SkipExisting): $DestFile"
            $deps = @()
            try {
                $deps = Get-DefinitionDependencyMap -Path $XmlPath -ErrorAction SilentlyContinue
            } catch { }

            return [pscustomobject]@{
                Path         = $XmlPath
                Status       = 'SkippedExisting'
                Type         = $Type
                Mode         = $Mode
                DestFile     = $DestFile
                Skipped      = $true
                Reason       = 'SkipExisting set and destination exists'
                Dependencies = $deps
            }
        }

        if (-not $Force) {
            # Collision-proof: increment suffix until free
            $name    = [System.IO.Path]::GetFileNameWithoutExtension($BaseName)
            $ext     = [System.IO.Path]::GetExtension($BaseName)
            $index   = 1
            $newDest = $DestFile

            while (Test-Path $newDest) {
                $newDest = Join-Path $DestDir ("{0}_{1}{2}" -f $name, $index, $ext)
                $index++
            }

            Write-Host "Collision detected for $DestFile"
            Write-Host "Using: $newDest"
            Write-Log  "Collision: $DestFile -> using $newDest"
            $DestFile = $newDest
        }
        elseif ($Force) {
            Write-Host "Overwriting: $DestFile"
            Write-Log  "Overwriting existing: $DestFile (Force)"
        }
    }

    # Dependency mapping (best-effort, per-file)
    $Dependencies = @()
    try {
        $Dependencies = Get-DefinitionDependencyMap -Path $XmlPath -ErrorAction Stop
    } catch {
        Write-Log ("Place-Definition: Dependency mapping failed for {0}: {1}" -f $XmlPath, $_.Exception.Message)
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would copy: $XmlPath -> $DestFile"
        Write-Log  "DRY-RUN: Would place $XmlPath -> $DestFile"
        return [pscustomobject]@{
            Path         = $XmlPath
            Status       = 'DryRun'
            Type         = $Type
            Mode         = $Mode
            DestFile     = $DestFile
            Skipped      = $false
            Reason       = 'Dry-run only'
            Dependencies = $Dependencies
        }
    }

    Copy-Item $XmlPath $DestFile -Force
    Write-Host "Placed: $DestFile"
    Write-Log  "Placed $XmlPath -> $DestFile"

    return [pscustomobject]@{
        Path         = $XmlPath
        Status       = 'Placed'
        Type         = $Type
        Mode         = $Mode
        DestFile     = $DestFile
        Skipped      = $false
        Reason       = $null
        Dependencies = $Dependencies
    }
}

# ------------------------------------------------------------
# FUNCTION 2: Bulk-PlaceDefinitions
# ------------------------------------------------------------
function Bulk-PlaceDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceDir,

        [switch]$Force,
        [switch]$DryRun,
        [switch]$SkipExisting,
        [switch]$Summary
    )

    if (-not (Test-Path $SourceDir)) {
        Write-Host "Directory not found: $SourceDir"
        Write-Log  "Bulk-PlaceDefinitions: Directory not found: $SourceDir"
        return
    }

    $Files = Get-ChildItem -Path $SourceDir -Filter *.xml -Recurse
    if (-not $Files) {
        Write-Host "No XML files found in: $SourceDir"
        Write-Log  "Bulk-PlaceDefinitions: No XML files in $SourceDir"
        return
    }

    Write-Host "Found $($Files.Count) XML files under $SourceDir"
    Write-Log  "Bulk-PlaceDefinitions: Found $($Files.Count) XML files under $SourceDir"

    $results = @()

    foreach ($file in $Files) {
        Write-Host "Processing: $($file.FullName)"
        Write-Log  "Processing: $($file.FullName)"

        $result = Place-Definition -XmlPath $file.FullName -Force:$Force -DryRun:$DryRun -SkipExisting:$SkipExisting
        if ($null -ne $result) {
            $results += $result
        }
    }

    Write-Host "Bulk import complete."
    Write-Log  "Bulk-PlaceDefinitions: Completed for $SourceDir"

    if ($Summary) {
        $total   = $results.Count
        $placed  = ($results | Where-Object { $_.Status -eq 'Placed' }).Count
        $dry     = ($results | Where-Object { $_.Status -eq 'DryRun' }).Count
        $skipped = ($results | Where-Object { $_.Skipped }).Count
        $missing = ($results | Where-Object { $_.Status -eq 'Missing' }).Count
        $unknown = ($results | Where-Object { $_.Status -eq 'UnknownType' -or $_.Status -eq 'ModeUndetected' }).Count

        Write-Host ""
        Write-Host "===== Bulk-PlaceDefinitions Summary ====="
        Write-Host "Total files:        $total"
        Write-Host "Placed:             $placed"
        Write-Host "Dry-run only:       $dry"
        Write-Host "Skipped:            $skipped"
        Write-Host "Missing:            $missing"
        Write-Host "Unknown type/mode:  $unknown"

        Write-Log "Summary: Total=$total Placed=$placed DryRun=$dry Skipped=$skipped Missing=$missing Unknown=$unknown"

        # Optional: dependency aggregation
        $allDeps = $results |
            Where-Object { $_.Dependencies -and $_.Dependencies.Count -gt 0 } |
            ForEach-Object { $_.Dependencies } |
            Sort-Object -Unique

        if ($allDeps) {
            Write-Host ""
            Write-Host "Referenced dependencies (unique):"
            $allDeps | ForEach-Object { Write-Host " - $_" }
        }

        return $results
    }

    return $results
}

# ------------------------------------------------------------
# FUNCTION 3: Validate-DefinitionPack
# ------------------------------------------------------------
function Validate-DefinitionPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$XmlPath
    )

    if (-not (Test-Path $XmlPath)) {
        Write-Host "File not found."
        return
    }

    try {
        [xml]$xml = Get-Content $XmlPath -Raw
        Write-Host "OK: XML is well-formed."
    }
    catch {
        Write-Host "ERROR: XML is NOT well-formed."
        return
    }

    $root = $xml.DocumentElement.LocalName
    Write-Host "Root tag: $root"
}

# ------------------------------------------------------------
# FUNCTION 4: Version-DefinitionPack
# ------------------------------------------------------------
function Version-DefinitionPack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$XmlPath,

        [string]$Version = $(Get-Date -Format "yyyy.MM.dd")
    )

    $Type = Detect-DefinitionType $XmlPath
    $Mode = $null

    $Base = Join-Path $PSScriptRoot "..\..\definitions"
    if ($Type -eq 'dyno') {
        $VersionDir = Join-Path (Join-Path $Base $Type) $Version
    } else {
        $Mode = Detect-DefinitionMode $XmlPath
        if (-not $Mode) { $Mode = "standard" }
        $VersionDir = Join-Path $Base "$Type\$Mode\$Version"
    }

    if (!(Test-Path $VersionDir)) {
        New-Item -ItemType Directory -Path $VersionDir -Force | Out-Null
    }

    $Dest = Join-Path $VersionDir (Split-Path $XmlPath -Leaf)
    Copy-Item $XmlPath $Dest -Force

    Write-Host "Versioned pack stored at:"
    Write-Host "  $Dest"
    Write-Log "Versioned $XmlPath -> $Dest"
}

# ------------------------------------------------------------
# Update-RomRaiderToolsModule
# ------------------------------------------------------------
function Update-RomRaiderToolsModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceUrl  # e.g. raw GitHub URL to RomRaiderTools.psm1
    )

    $modulePath = $PSCommandPath
    $backupPath = "$modulePath.bak_$(Get-Date -Format yyyyMMdd_HHmmss)"

    Write-Host "Updating module from:"
    Write-Host "  $SourceUrl"
    Write-Host "Current module:"
    Write-Host "  $modulePath"
    Write-Host ""

    try {
        Copy-Item $modulePath $backupPath -Force
        Write-Log "Module backup created: $backupPath"

        $tmp = New-TemporaryFile
        Invoke-WebRequest -Uri $SourceUrl -OutFile $tmp -UseBasicParsing

        Copy-Item $tmp $modulePath -Force
        Remove-Item $tmp -Force

        Write-Host "OK: Module updated."
        Write-Host "Backup:"
        Write-Host "  $backupPath"
        Write-Log "Module updated from $SourceUrl"
    }
    catch {
        Write-Host "ERROR: Update failed: $($_.Exception.Message)"
        Write-Log "Module update FAILED: $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------
# Sync-DefinitionRepo
# ------------------------------------------------------------
function Sync-DefinitionRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ZipUrl,      # e.g. GitHub repo zip URL

        [Parameter(Mandatory=$true)]
        [string]$Name         # logical name, e.g. "SubaruMain"
    )

    $BaseDefs = Join-Path $PSScriptRoot "..\..\definitions"
    $RepoRoot = Join-Path $BaseDefs "_repos"
    if (!(Test-Path $RepoRoot)) {
        New-Item -ItemType Directory -Path $RepoRoot | Out-Null
    }

    $TargetDir = Join-Path $RepoRoot $Name
    if (!(Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir | Out-Null
    }

    $tmpZip = New-TemporaryFile
    Write-Host "Downloading repo zip:"
    Write-Host "  $ZipUrl"
    Invoke-WebRequest -Uri $ZipUrl -OutFile $tmpZip -UseBasicParsing

    # Extract to temp, then replace target
    $tmpExtract = Join-Path ([IO.Path]::GetTempPath()) ("rr_defs_" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tmpExtract | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force
    Remove-Item $tmpZip -Force

    # Most GitHub zips have a single top-level folder
    $inner = Get-ChildItem $tmpExtract | Where-Object { $_.PSIsContainer } | Select-Object -First 1
    if ($inner) {
        Remove-Item $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item $inner.FullName $TargetDir
    }

    Remove-Item $tmpExtract -Recurse -Force

    Write-Host "OK: Repo synced to:"
    Write-Host "  $TargetDir"
    Write-Log "Repo synced: $ZipUrl -> $TargetDir"
}

# ------------------------------------------------------------
# Get-DefinitionDependencyMap
# ------------------------------------------------------------
function Get-DefinitionDependencyMap {
    [CmdletBinding()]
    param(
        [string]$Root = $(Join-Path $PSScriptRoot "..\..\definitions"),
        [string]$Path
    )

    $files = @()

    if ($Path) {
        if (-not (Test-Path $Path)) {
            Write-Host "File not found for dependency map: $Path"
            return @()
        }
        $files = ,(Get-Item $Path)
    } else {
        if (-not (Test-Path $Root)) {
            Write-Host "Root not found: $Root"
            return @()
        }
        $files = Get-ChildItem -Path $Root -Filter *.xml -Recurse
    }

    $deps = @()

    foreach ($f in $files) {
        try {
            [xml]$xml = Get-Content $f.FullName -Raw
        }
        catch {
            continue
        }

        $text = $xml.OuterXml

        # Heuristic: look for attributes that imply dependency
        $matches = Select-String -InputObject $text -Pattern 'baseRom="([^"]+)"','inherits="([^"]+)"','extends="([^"]+)"' -AllMatches

        foreach ($m in $matches) {
            foreach ($g in $m.Matches.Groups) {
                if ($g.Name -eq "1" -and $g.Value) {
                    $deps += [pscustomobject]@{
                        File      = $f.FullName
                        DependsOn = $g.Value
                    }
                }
            }
        }
    }

    $deps | Sort-Object File, DependsOn
}

# ------------------------------------------------------------
# Export functions
# ------------------------------------------------------------
Export-ModuleMember -Function `
    Place-Definition, `
    Bulk-PlaceDefinitions, `
    Validate-DefinitionPack, `
    Version-DefinitionPack, `
    Update-RomRaiderToolsModule, `
    Sync-DefinitionRepo, `
    Get-DefinitionDependencyMap
