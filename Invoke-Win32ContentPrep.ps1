[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ContentLocation,
    [Parameter(Position = 1, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SetupFile,
    [Parameter(Position = 2)]
    [string]$AppName
)

process {

    #Resolving the paths of the provided files
    $contentPathResolved = (Resolve-Path -Path $ContentLocation -ErrorAction "Stop").Path
    $setupFilePathResolved = (Resolve-Path -Path $SetupFile -ErrorAction "Stop").Path

    #Getting the provided files as objects for later use.
    $contentLocationItem = Get-Item -Path $contentPathResolved
    $setupFileItem = Get-Item -Path $setupFilePathResolved

    #Checking to see if the extension in the setup file is allowed.
    switch (($setupFileItem.Extension -in @(".exe", ".msi", ".ps1"))) {
        $false {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Setup file is not an '.exe', '.msi', or '.ps1' file."),
                    "InvalidSetupFileType",
                    [System.Management.Automation.ErrorCategory]::InvalidType,
                    $setupFileItem.Name
                )
            )
            break
        }
    }

    $scriptPath = $PSScriptRoot #Getting the script's root path.
    $win32ContentPrepToolDir = [System.IO.Path]::Combine($scriptPath, "Microsoft-Win32-Content-Prep-Tool") #Creating a path to the win32 content prep tool in the script's root.

    #Check to see if 'IntuneWinAppUtil.exe' actually exists.
    $win32ContentPrepTool = $null
    switch ((Test-Path -Path $win32ContentPrepToolDir)) {
        $false {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("'Microsoft-Win32-Content-Prep-Tool' was not found in the script's root directory."),
                    "RequiredDependencyNotFound",
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $win32ContentPrepToolDir
                )
            )
            break
        }

        Default {
            $win32ContentPrepTool = Get-Item -Path ([System.IO.Path]::Combine($win32ContentPrepToolDir, "IntuneWinAppUtil.exe"))
            break
        }
    }

    #Test to see if the 'workspace' directory exists in the script's root. If it doesn't, create it.
    $workspaceDir = [System.IO.Path]::Combine($scriptPath, "workspace")
    switch ((Test-Path -Path $workspaceDir)) {
        $false {
            Write-Warning "The directory, 'workspace', doesn't exist. Creating..."
            if ($PSCmdlet.ShouldProcess($workspaceDir, "Create directory")) {
                $null = New-Item -Path $workspaceDir -ItemType "Directory" -Force -ErrorAction "Stop"
            }
        }

        Default {
            break
        }
    }

    #Test to see if the 'packagedapps' directory exists in the 'workspace' directory. If it doesn't, create it.
    $packagedAppsDir = [System.IO.Path]::Combine($workspaceDir, "packagedapps")
    switch ((Test-Path -Path $packagedAppsDir)) {
        $false {
            Write-Warning "The directory, 'packagedapps', doesn't exist. Creating..."
            if ($PSCmdlet.ShouldProcess($packagedAppsDir, "Create directory")) {
                $null = New-Item -Path $packagedAppsDir -ItemType "Directory" -Force -ErrorAction "Stop"
            }
        }

        Default {
            break
        }
    }
    
    #Check to make sure that the content location is actually a directory, as the 'System.IO.DirectoryInfo' type can be created from any file type.
    switch ($contentLocationItem.Attributes) {
        "Directory" {
            break
        }

        Default {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("'$($contentLocationItem.FullName)' is not a directory"),
                    "ContentPath.IsDirectoryFailed",
                    [System.Management.Automation.ErrorCategory]::InvalidType,
                    $contentLocationItem
                )
            )
            break
        }
    }

    #Check to make sure the setup file exists in the content location's directory. 'IntuneWinAppUtil.exe' will throw an error if the file isn't in the content location's directory, but this will prevent the script from reaching that point. 
    switch ($setupFileItem.Directory.FullName -eq [System.IO.Path]::TrimEndingDirectorySeparator($contentLocationItem)) {
        $false {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Provided setup file is not in the content location directory, '$($contentLocationItem.FullName)'."),
                    "SetupFile.Check.FileIsInContentLocationFailed",
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $setupFileItem
                )
            )
            break
        }

        Default {
            break
        }
    }

    #If 'AppName' is not provided or if there is a whitespace in it, automatically use the content location's directory name.
    switch ([string]::IsNullOrWhiteSpace($AppName)) {
        $true {
            Write-Warning "An app name wasn't provided. Using the content location's directory name, '$($contentLocationItem.Name)', as the app name."
            $AppName = $contentLocationItem.Name
            break
        }
        
        Default {
            break
        }
    }

    #Check to see if the output directory for the app already exists. If it already exists, remove the directory.
    $appDirPath = [System.IO.Path]::Combine($packagedAppsDir, $AppName)
    switch ((Test-Path -Path $appDirPath)) {
        $true {
            Write-Warning "A path for '$($AppName)' already exists. Deleting contents."
            Remove-Item -Path $appDirPath -Recurse -Force -ErrorAction "Stop"
            break
        }

        Default {
            break
        }
    }

    #Create the ouput directory for the app
    $appDir = New-Item -Path $appDirPath -ItemType "Directory" -Force -ErrorAction "Stop"

    if ($PSCmdlet.ShouldProcess($win32ContentPrepTool.Name, "Run with arguments: '-c `"$($ContentLocation.FullName)`" -s `"$($SetupFile.Name)`" -o `"$($appDir.FullName)`"'")) {
        #Push the location to the win32 content prep tool directory
        Push-Location -Path $win32ContentPrepToolDir -StackName "contentPrepToolDir"

        try {
            #Due to some weird issue with quotes in the arguments list for 'Start-Process' and 'IntuneWinAppUtil', we have to dot source the win32 content prep tool.
            & ".\IntuneWinAppUtil.exe" -c "$($contentLocationItem.FullName)" -s "$($setupFileItem.Name)" -o "$($appDir.FullName)"
        }
        catch {
            #Nothing to catch.
        }
        finally {
            #Return back to the directory where the user was originally.
            Pop-Location -StackName "contentPrepToolDir"
        }
    }
}