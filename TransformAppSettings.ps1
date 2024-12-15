<#
  .SYNOPSIS
  Transform a settings .json file using logic similar to that used to transform .xml configuration files.

  .DESCRIPTION
  .Net Core uses .json files for external app configuration (typically appsettings.json). The standard means to transform a settings file
  deploying to various environments is to overlay some or all of a base settings file with a file matched to an environment. 

  For various reasons, an organization may need to employ logic more similar to that used for transforming XML configuration files. This script 
  fulfills that goal, producing a single file that can be copied to the server before application startup. It is specifically created for use in
  Azure DevOps release pipelines and is constructed to be called by a PowerShell pipeline task.

  The script uses a pipe character in the json property name to indicate the transformation action. The available actions are defined in the 
  TransformType enum.

  .PARAMETER FileSource
  A directory containing a base json settings file and files to be used for its transformation. Defaults to an environment vairable of the same 
  name.

  .PARAMETER BaseFileName
  The base file that needs to be transformed, typically 'appsettings.json'. Files to be used to alter that base file must have the name pattern 
  'appsettings.SOMENAME.json'. Typically, the tranformation file would be named for an environment: 'appsettings.QA.json'. ANY file matching the
  pattern will be used to transform the base file. The transform files are collected by Get-ChildItem using the default, alphabetical order. The 
  'Merge' tranform action can be used to prevent multiple files from overwriting certain settings, and the file names can be used to control the 
  order of transformations.

  .PARAMETER OutputDirectory
  The output location for the transformed file, which will have the same name as the base file. If the FileSource and OutputDirectory are the same,
  the original file will be overwritten.
#>

$debug = $DebugPreference -eq "SilentlyContinue"

if ($debug -eq $true){
    $env:FILESOURCE = "tests\basic_tests\alter_child_object"
    $env:BASEFILENAME = 
    $env:OUTPUTDIRECTORY = "tests\basic_tests\alter_child_object\output"
}
param (
    $FileSource = $env:FILESOURCE, 
    $BaseFileName = $env:BASEFILENAME, 
    $OutputDirectory = $env:OUTPUTDIRECTORY
)

if ($host.Version.Major -eq 7) {
    $PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText;
}

<#
.DESCRIPTION
Holds values used in a tranformation file that indicate the changes to the base file. The available actions are:
REPLACE: replace a property completely, including nested properties
MERGE: for arrays and objects; merges new values into an exisiting object
ADD: adds a property not present in the base file
REMOVE: removes a property from the base file
#>
enum TransformType {
    REPLACE
    MERGE
    ADD
    REMOVE
}

#https://www.powershellgallery.com/packages/pspm/1.1.3/Content/functions%5CFormat-Json.ps1
function Format-Json {
    param
    (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $json,

        [int]
        $indentSize = 4
    ) 

    $indent = 0;
    $result = ($json -Split '\n' |
        ForEach-Object {
            if ($_ -match '[\}\]]') {
                # This line contains ] or }, decrement the indentation level
                $indent--
            }
            $line = (' ' * $indent * $indentSize) + $_.TrimStart().Replace(': ', ': ')
            if ($_ -match '[\{\[]') {
                # This line contains [ or {, increment the indentation level
                $indent++
            }
            $line
        }) -Join "`n"
    
    # Unescape Html characters (<>&') (and remove extra space after colons)
    $result.Replace('\u0027', "'").Replace('\u003c', "<").Replace('\u003e', ">").Replace('\u0026', "&").Replace(":  ", ": ")
    
}
class TransformationData {
    [string]$FileName
    [PSCustomObject]$TransformObject
    TransformationData([string]$fileName, [PSCustomObject]$TransformObject){
        $this.Init($fileName, $transformObject)
    }
    hidden [void] Init([string]$fileName, [PSCustomObject]$transformObject){
        $this.FileName = $fileName
        $this.TransformObject = $transformObject
    }
}

function Edit-SettingsObject{
    param(
        [PSObject]
        #the base settings object created by reading a settings content file
        $baseObject, 
        [PSObject]
        #the settings object created holding the properties to use to transform the base object
        $transformObject, 
        [Int32]
        #the depth to search for properties to tranform
        $maxLevel = 25
        )
    $baseObject.PSObject.Properties | ForEach-Object {
        $level = 1
        Write-Host "loop base      -> $($_.Name)"
        if([bool]$transformObject.PSObject.Properties[$_.Name] `
          -and $transformObject.PSObject.Properties[$_.Name].Value.GetType().Name -eq "PSCustomObject" `
          -and $transformObject.PSObject.Properties[$_.Name].Value.GetType() -eq $_.Value.GetType()){
            Write-Host "               -> RECURSE $level"
            $tempUpdatedObject = Edit-SettingsObject -baseObject $_.Value -transformObject $transformObject.PSObject.Properties[$_.Name].Value -level ($level + 1)
            $baseObject.PSObject.Properties[$_.Name].Value =  $tempUpdatedObject
        }
    }
    $transformObject.PSObject.Properties | ForEach-Object {
        $tranformSettingName = $_.Name
        Write-Host "loop transform -> $tranformSettingName"
        if ($tranformSettingName.Contains("|")){
            $settingData = $tranformSettingName.Split("|")
            if ([enum]::GetNames([TransformType]).Contains($settingData[0]) -and [bool]$baseObject.PSObject.Properties[$settingData[1]]){
                switch ([TransformType]$settingData[0]){
                    REPLACE { 
                        Write-Host "       replace -> $($settingData[1])"
                        Write-Host "       $($baseObject.PSObject.Properties[$settingData[1]].Value ?? "'null'") becomes $($transformObject.PSObject.Properties[$tranformSettingName].Value ?? "'null'")"
                        if ($baseObject.PSObject.Properties[$settingData[1]].Value -is [Array]){
                            $baseObject.PSObject.Properties[$settingData[1]].Value = @($transformObject.PSObject.Properties[$tranformSettingName].Value)
                        } else {
                            $baseObject.PSObject.Properties[$settingData[1]].Value = $transformObject.PSObject.Properties[$tranformSettingName].Value
                        }
                        return
                    }
                    MERGE {
                        Write-Host "       merge   -> $($settingData[1])"
                        Write-Host "       $($baseObject.PSObject.Properties[$settingData[1]].Value) adding $($transformObject.PSObject.Properties[$tranformSettingName].Value)"
                        if ($baseObject.PSObject.Properties[$settingData[1]].Value -is [Array]){
                            $baseObject.PSObject.Properties[$settingData[1]].Value += $transformObject.PSObject.Properties[$tranformSettingName].Value
                        } elseif ($baseObject.PSObject.Properties[$settingData[1]].Value.GetType().Name -eq "PSCustomObject") {
                            Write-Host "       properties cannot be merged into complex objects; instead, use the 'ADD' transform action on a new property inside this object"
                        } 
                        return
                    }
                    REMOVE {
                        Write-Host "       remove  -> $($settingData[1]) : $($baseObject.PSObject.Properties[$settingData[1]].Value)"
                        $baseObject.PSObject.Properties.Remove($settingData[1])
                        return
                    }
                }
            } elseif ([TransformType]$settingData[0] -eq [TransformType]::ADD -and [bool]$baseObject.PSObject.Properties[$settingData[1]] -eq $false){
                Write-Host "       add     -> $($settingData[1]) : $($transformObject.PSObject.Properties[$tranformSettingName].Value)"
                $baseObject | Add-Member -NotePropertyName $settingData[1] -NotePropertyValue $transformObject.PSObject.Properties[$tranformSettingName].Value
                return
            } elseif ([TransformType]$settingData[0] -eq [TransformType]::ADD -and [bool]$baseObject.PSObject.Properties[$settingData[1]]){
                Write-Host "       property already exisits and cannot be added or altered using the 'ADD' transform action"
                return
            }
        } else {
            Write-Host "       none    -> $($_.Name)"
        }
    }
    return $baseObject

}

<#
.DESCRIPTION
Alters a base settings file with a transform file. The content of each file is laoded into memory and mosfied by the Edit-SettingsObject function.
#>
function Edit-AppSettings {
    param(
        [PSObject]
        #the content file to be transformed
        $baseFile,
        [Array]
        #the content files used to transform the base file
        $transformFiles
        ) 
    # load the content of the base settings file
    try {
        $baseObject = Get-Content $baseFile.FullName -Raw | ConvertFrom-Json
    } catch {
        Write-Host $_.Exception
        return
    }
    # load the content of all transform files
    $transformObjects = @()
    $transformFiles | ForEach-Object {
        try {
            $transformObjects += [TransformationData]::new($_.Name, (Get-Content $_.FullName -Raw | ConvertFrom-Json))
        } catch {
            Write-Host $_.Exception
            return
        }
    }
    $transformObjects | ForEach-Object {
        [string]::Format("Applying values to base settings file {0} using {1}", $baseFile.Name, $_.FileName) | Write-Host 
        $baseObject = Edit-SettingsObject -baseObject $baseObject -transformObject $_.TransformObject
    }
    return $baseObject
}


# SCRIPT BODY

if ($false -eq (Test-Path -Path $FileSource)) {
    Write-Host "No directory found at $FileSource"
    return
}

$baseFile = Get-ChildItem -Path $FileSource\* -Filter $BaseFileName
if ($null -eq $baseFile) {
    Write-Host "No base file found in $FileSource"
    return
}
$transformFiles = Get-ChildItem -Path $FileSource\* -Filter $BaseFileName.Replace(".json", ".*.json") -Exclude $BaseFileName
if ($null -eq $transformFiles) {
    Write-Host "No transform files found in $FileSource"
    return
}

$updatedSettings = Edit-AppSettings -baseFile $baseFile -transformFiles $transformFiles
if ($debug -eq $true){
    $count = (((Get-ChildItem -Path $OutputDirectory -Filter $BaseFileName.Replace(".json", "*.json")).Name | Where-Object {$_ -match "\d{3}.json"} ).Count + 1).ToString("000")
    $updatedSettings | ConvertTo-Json -Depth 100 | Format-Json | Out-File -Encoding utf8 (Join-Path -Path $OutputDirectory -ChildPath $BaseFileName.Replace(".json", ".$count.json")) -Force
    return
}
$updatedSettings | ConvertTo-Json -Depth 100 | Format-Json | Out-File -Encoding utf8 (Join-Path -Path $OutputDirectory -ChildPath $BaseFileName) -Force

<#

cd D:\_prj\github\azure-devops-pwsh

$env:FILESOURCE = "tests\basic_tests\alter_child_object"
$env:BASEFILENAME = "appsettings.json"
$env:OUTPUTDIRECTORY = "tests\basic_tests\alter_child_object\output"

. 'D:\_prj\github\azure-devops-pwsh\TransformAppSettings.ps1' -FileSource "D:\_prj\github\azure-devops-pwsh\tests\basic_tests\alter_child_object" -BaseFileName "appsettings.json" -OutputDirectory "D:\_prj\github\azure-devops-pwsh\tests\basic_tests\alter_child_object\output"
#>

