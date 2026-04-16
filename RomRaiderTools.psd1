@{
    RootModule        = 'RomRaiderTools.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '5a3d4e25-0cb4-4b8d-9d34-b96b9c6cc637'
    Author            = 'samsquanch01'
    CompanyName       = 'Unknown'
    Copyright         = '(c) samsquanch01. All rights reserved.'
    Description       = 'RomRaiderTools module for managing RomRaider XML definition packs.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Place-Definition'
        'Bulk-PlaceDefinitions'
        'Validate-DefinitionPack'
        'Version-DefinitionPack'
        'Update-RomRaiderToolsModule'
        'Sync-DefinitionRepo'
        'Get-DefinitionDependencyMap'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
