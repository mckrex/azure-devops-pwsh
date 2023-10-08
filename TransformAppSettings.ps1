param (
    $FileSource = $env:FILESOURCE, 
    $Environment = $env:ENVIRONMENT
)


if ($host.Version.Major -eq 7) {
    $PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText;
}

enum TransformType {
    REPLACE
    MERGE
    ADD
    REMOVE
}


function Edit-SettingsObject{
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
performs settings transformations
#>
function Edit-AppSettings {
    param($transformFile, $baseFile)
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

<#
TESTING

Copy-Item -Path "C:\_prj\Tasks\devops\app_transform\tests\source_folder_bak\*" -Destination "C:\_prj\Tasks\devops\app_transform\tests\source_folder" -Recurse -Force

$env:ENVIRONMENT = "QA"
$env:FILESOURCE = "C:\_prj\Tasks\devops\app_transform\tests\"


. C:\_prj\AccountNet\DeployScripts\Release_TransformAppSettings.ps1 -SpecificPropertiesSource "appsettings.ALL.json"
#>
