<#
  .SYNOPSIS
  Transform a settings .json file using logic similar to that used to transform .xml configuration files.

  .DESCRIPTION
  .Net Core use .json files for external app configuration (typically appsettings.json). The standard means to transform a settings file
  deploying to various environments is to overlay some or all of a base settings file with a file matched to an environemnr. For example, when 
  deploying to QA, at startup, the application can overlay appsettinfs.json with a file called appsettings.QA.json, then load those settings 
  into memory.

  For various reasons, an organization may need to employ logic more similar to that used for transforming XML configuration files. This script 
  fulfills that goal producing a single file that can be copied to the server before application startup. It is specifically created for use in
  Azure DevOps release pipelines and is constructed to be called by a PowerShell pipeline task.

  The script uses a pipe character in the json property name to indicate the transformation action. The available actions are defined in the 
  TransformType enum.

  .PARAMETER FileSource
  A directory containing a base json settings file and files to be used for it's transformation. Defaults to an environment vairable of the same 
  name.

  .PARAMETER Environment
  For transformations when deploying to an environment, the environment name to be used to find a transform file.
#>


param (
    $FileSource = $env:FILESOURCE, 
    $Environment = $env:ENVIRONMENT
)


if ($host.Version.Major -eq 7) {
    $PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText;
}

<#
.DESCRIPTION
Holds values used in a tranformation file that indicate the changes to the base file. The available actions are:
REPLACE: replace a property completely, including nested properties
MERGE: for arrays; merges new values into an exisiting object
ADD: adds a property not present in the base file
REMOVE: removes a property from the base settings file
#>
enum TransformType {
    REPLACE
    MERGE
    ADD
    REMOVE
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
        $level
        )
    param($baseObject, $transformObject, $level)
    $baseObject.PSObject.Properties | ForEach-Object {
        Write-Host "loop base      -> $($_.Name)"
        if([bool]$transformObject.PSObject.Properties[$_.Name] `
          -and $transformObject.PSObject.Properties[$_.Name].Value.GetType().Name -eq "PSCustomObject" `
          -and $transformObject.PSObject.Properties[$_.Name].Value.GetType() -eq $_.Value.GetType()){
            Write-Host "               -> RECURSE $level"
            Edit-SettingsObject -baseObject $_.Value -transformObject $transformObject.PSObject.Properties[$_.Name].Value -level ($level + 1)
        }
    }
    $transformObject.PSObject.Properties | ForEach-Object {
        Write-Host "loop transform -> $($_.Name)"
        if ($_.Name.Contains("|")){
            $setting = $_.Name.Split("|")
            if ([bool]$baseObject.PSObject.Properties[$setting[0]]){
                switch ([TransformType]$setting[1]){
                    REPLACE {
                        Write-Host "       replace -> $($setting[0])"
                        #$baseObject.PSObject.Properties[$setting[0]] = $_
                    }
                    MERGE {
                        Write-Host "       merge   -> $($setting[0])"
                        # if ($baseObject.PSObject.Properties[$setting[0]] -is [Array]){
                        #     $baseObject.$settingName += $_
                        # }
                        # else{}
                    }
                    ADD {
                        Write-Host "       add     -> $($setting[0])"
                        #$baseObject | Add-Member -NotePropertyName $setting[0] -NotePropertyValue $_
                    }
                    REMOVE {
                        Write-Host "       remove  -> $($setting[0])"
                        #$baseObject.PSObject.Properties.Remove($setting[0])
                    }
                }
            }
        } else {
            Write-Host "       none    -> $($_.Name)"
        }
        
    }

}

<#
.DESCRIPTION
Alters a base settings file with a transform file. The content of each file is laoded into memory and mosfied by the Edit-SettingsObject function.
#>
function Edit-AppSettings {
    param(
        [string]
        #the content file to be transformed
        $baseFile,
        [string]
        #the content file used to transform the base file
        $transformFile
        ) 
    [string]::Format("Applying values to base settings file {0} using {1}", $baseFile.Name, $transformFile.Name) | Write-Host 
    # load the content of the base settings file and the transform settings file
    try {
        $baseObject = Get-Content "$baseFile" -Raw | ConvertFrom-Json
        $transformObject = Get-Content "$transformFile" -Raw | ConvertFrom-Json
    } catch {
        Write-Host $_.Exception
        return
    }
    Edit-SettingsObject -baseObject $baseObject -transformObject $transformObject -level 1
}


# SCRIPT BODY

if ($false -eq (Test-Path -Path $FileSource)) {
    Write-Host "No directory found at source location $FileSource"
}

$baseFile = Get-ChildItem -Path $FileSource -Filter "appsettings.json" -Recurse
$transformFile = Get-ChildItem -Path $FileSource -Filter "appsettings.$Environment.json" -Recurse

Edit-AppSettings -baseFile $baseFile -transformFile $transformFile

