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
    if (!(Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

    $LogFile = Join-Path $LogDir "module_$(Get-Date -Format yyyyMMdd).log"
    Add-Content -Path $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

# ------------------------------------------------------------
# Shared: Detect Type (ECU / Logger / Dyno)
# ------------------------------------------------------------
function Detect-DefinitionType {
    param([string]$XmlPath)

    $Name = Split-Path $XmlPath -Leaf
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

    $Name = Split-Path $XmlPath -Leaf
    $Content = Get-Content $XmlPath -Raw

    if ($Name -match "metric" -or $Content -match "metric") { return "metric" }
    if ($Name -match "standard" -or $Content -match "standard") { return "standard" }

    return $null
}

# ------------------------------------------------------------
# Shared: Canonical filename
# ------------------------------------------------------------
function Get-CanonicalName {
    param([string]$Type)

    switch ($Type) {
        "ecu"    { return "ecu_defs.xml" }
        "logger" { return "logger_defs.xml" }
        "dyno"   { return "dyno_defs.xml" }
    }
}

# ------------------------------------------------------------
# FUNCTION 1: Place-Definition
# ------------------------------------------------------------
function Place-Definition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$XmlPath,

        [switch]$Force
    )

    if (-not (Test-Path $XmlPath)) {
        Write-Host "File not found: $XmlPath"
        return
    }

    $Type = Detect-DefinitionType $XmlPath
    if (-not $Type) {
        Write-Host "Unknown definition type."
        return
    }

    $Mode = Detect-DefinitionMode $XmlPath
    if (-not $Mode) {
        Write-Host "Unable to detect mode."
        Write-Host "1) Standard"
        Write-Host "2) Metric"
        $choice = Read-Host "Select mode"
        if ($choice -eq "1") { $Mode = "standard" }
        elseif ($choice -eq "2") { $Mode = "metric" }
        else { return }
    }

    $DestName = Get-CanonicalName $Type
    $Base = Join-Path $PSScriptRoot "..\..\definitions"
    $DestDir = Join-Path $Base "$Type\$Mode"

    if (!(Test-Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }

    $DestFile = Join-Path $DestDir $DestName

    if ((Test-Path $DestFile) -and -not $Force) {
        $ow = Read-Host "Overwrite $DestFile? (y/n)"
        if ($ow -ne "y") { return }
    }

    Copy-Item $XmlPath $DestFile -Force
    Write-Host "Placed: $DestFile"
    Write-Log "Placed $XmlPath → $DestFile"
}

# ------------------------------------------------------------
# FUNCTION 2: Bulk-PlaceDefinitions
# ------------------------------------------------------------
function Bulk-PlaceDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceDir,

        [switch]$Force
    )

    if (-not (Test-Path $SourceDir)) {
        Write-Host "Directory not found: $SourceDir"
        return
    }

    $Files = Get-ChildItem -Path $SourceDir -Filter *.xml -Recurse

    foreach ($file in $Files) {
        Write-Host "Processing: $($file.FullName)"
        Place-Definition -XmlPath $file.FullName @($Force)
    }

    Write-Host "Bulk import complete."
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
        Write-Host "✔ XML is well-formed."
    }
    catch {
        Write-Host "❌ XML is NOT well-formed."
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
    $Mode = Detect-DefinitionMode $XmlPath
    if (-not $Mode) { $Mode = "standard" }

    $Base = Join-Path $PSScriptRoot "..\..\definitions"
    $VersionDir = Join-Path $Base "$Type\$Mode\$Version"

    if (!(Test-Path $VersionDir)) {
        New-Item -ItemType Directory -Path $VersionDir -Force | Out-Null
    }

    $Dest = Join-Path $VersionDir (Split-Path $XmlPath -Leaf)
    Copy-Item $XmlPath $Dest -Force

    Write-Host "Versioned pack stored at:"
    Write-Host "  $Dest"
    Write-Log "Versioned $XmlPath → $Dest"
}

# ------------------------------------------------------------
# Update-Tools Module
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

        Write-Host "✔ Module updated."
        Write-Host "Backup:"
        Write-Host "  $backupPath"
        Write-Log "Module updated from $SourceUrl"
    }
    catch {
        Write-Host "❌ Update failed: $($_.Exception.Message)"
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
    if (!(Test-Path $RepoRoot)) { New-Item -ItemType Directory -Path $RepoRoot | Out-Null }

    $TargetDir = Join-Path $RepoRoot $Name
    if (!(Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir | Out-Null }

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

    Write-Host "✔ Repo synced to:"
    Write-Host "  $TargetDir"
    Write-Log "Repo synced: $ZipUrl → $TargetDir"
}


# ------------------------------------------------------------
#  Get-DefinitionDependencyMap
# ------------------------------------------------------------
function Get-DefinitionDependencyMap {
    [CmdletBinding()]
    param(
        [string]$Root = $(Join-Path $PSScriptRoot "..\..\definitions")
    )

    if (-not (Test-Path $Root)) {
        Write-Host "Root not found: $Root"
        return
    }

    $files = Get-ChildItem -Path $Root -Filter *.xml -Recurse
    $deps  = @()

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
                        File       = $f.FullName
                        DependsOn  = $g.Value
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
