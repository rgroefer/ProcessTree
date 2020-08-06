# Class to handle the CIM_Process class
class MyProcess
{
    [bool]$isComputerName
    [bool]$isOrphaned
    [System.Collections.ArrayList]$ChildProcess
    [string[]]$PropertiesToShow
    [string[]]$PropertiesOnCimClass

    # Constructor
    MyProcess([CimInstance]$Process, [string[]]$PropertiesOnCimClass)
    {
        foreach($property in $PropertiesOnCimClass)
        {
            $this | Add-Member -MemberType NoteProperty -Name $property -Value $Process.$property
        }
        $this.ChildProcess = [System.Collections.ArrayList]@()
    }
    MyProcess([CimInstance]$Process, [string[]]$PropertiesOnCimClass, [string[]]$PropertiesToShow)
    {
        foreach($property in $PropertiesOnCimClass)
        {
            $this | Add-Member -MemberType NoteProperty -Name $property -Value $Process.$property
        }
        $this.ChildProcess = [System.Collections.ArrayList]@()
        $this.PropertiesToShow = $PropertiesToShow
    }
    MyProcess([string]$ComputerName,[bool]$isComputerName)
    {
        $this.isComputerName = $true
        $this | Add-Member -MemberType NoteProperty -Name Name -Value $ComputerName
    }
    
    # Add another process as a child process
    [void] AddChildProcess([MyProcess]$Proc)
    {
        $this.ChildProcess.Add($Proc)
    }
    # Set as orphaned (when the parent process is no longer running)
    [void] SetIsOrphaned()
    {
        $this.isOrphaned = $true
    }
    # Return the long string output
    [string] WriteString([string]$CurrentTab)
    {
        $OutputStringArray = [System.Collections.ArrayList]@()
        if($this.isComputerName)
        {
            $OutputStringArray.Add("`n")
        }
        
        if($this.isOrphaned)
        {
            $OutputStringArray.Add("$($CurrentTab)\--$($this.Name) `e[31m<-Orphaned Process`e[0m") | Out-Null
        }else{
            $OutputStringArray.Add("$($CurrentTab)\--$($this.Name)") | Out-Null
        }
        foreach ($property in $this.PropertiesToShow) {
            $OutputStringArray.Add("`n") | Out-Null
            $OutputStringArray.Add("$($CurrentTab)   ($property->$($this.$property))") | Out-Null
        }
        Return $($OutputStringArray -join '')
    }
}
function Get-ProcessTree
{
    <#
    .SYNOPSIS
        Get the processes, showing in tree form similar to the Tree command
    .DESCRIPTION
        Get the processes running on the local machine or remote machine(s).  Show the processes in tree form similar to the Tree command with child processes branching off from the parent.
    .PARAMETER ComputerName
        The computer names(s) of remote machine to target and gather the running processes.
    .PARAMETER Credential
        PSCredential object to use with the remote machine(s), should you need to use a separate credential.
    .EXAMPLE
        PS>Get-ProcessTree
    .EXAMPLE
        PS>Get-ProcessTree -ComputerName SomeRemoteMachineName
    .EXAMPLE
        PS>Get-ProcessTree -ComputerName SomeREmoteMachineName -Credential $MyPSCredentialObject
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]
        $ComputerName
        ,
        [Parameter()]
        [pscredential]
        $Credential
        ,
        [Parameter()]
        [string[]]
        $PropertiesToShow
        ,
        [Parameter(DontShow)]
        [CimSession]
        $CimSession
    )

    BEGIN
    {}
    PROCESS
    {
        if($PSBoundParameters.Keys.Contains('ComputerName'))
        {
            Foreach($Name in $ComputerName)
            {
                Write-Verbose "Processing $Name"
                # If a credential is supplied, attempt to get a CIM session for each remote machine
                if($PSBoundParameters.Keys.Contains('Credential'))
                {
                    Write-Verbose "`tAttempting to get a CIM session with this computer"
                    try
                    {
                        $CimSession = $null
                        $CimSession = New-CimSession -ComputerName $Name -Credential $Credential -Name $Name -ErrorAction Stop
                        Invoke-ProcessTree -CimSession $CimSession
                    }catch{
                        Write-Error "`tFailed to create a CIM session with $Name"
                        break
                    }
                }else{
                    Invoke-ProcessTree -ComputerName $Name
                }
    
                if($PSBoundParameters.Keys.Contains('Credential'))
                {
                    Write-Verbose "Cleaning up CimSession for $Name"
                    $CimSession | Remove-CimSession
                    $CimSession = $null
                }
    
                Write-Verbose "Completed processing $Name"
                Write-Output "`n"
            }
        }else{
            if($PSBoundParameters.ContainsKey('PropertiesToShow'))
            {
                Invoke-ProcessTree -PropertiesToShow $PropertiesToShow
            }else{
                Invoke-ProcessTree
            }
        }
    }
    END{}
}

# Helper function
# Gathers the processes
# Calls other helper functions to
    # group children processes under parent
    # enumerate child processes
    # print to screen
function Invoke-ProcessTree
{
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]
        $ComputerName
        ,
        [Parameter()]
        [CimSession]
        $CimSession
        ,
        [Parameter()]
        [string[]]
        $PropertiesToShow
        ,
        [Parameter(DontShow)]
        [System.Collections.Hashtable]
        $AllProcs
        ,
        [Parameter(DontShow)]
        [System.Collections.ArrayList]
        $FinalArrayList
        ,
        [Parameter(DontShow)]
        [System.Collections.Hashtable]
        $ParentProcesses
        ,
        [Parameter(DontShow)]
        [string]
        $CurrentTab
        ,
        [Parameter(DontShow)]
        [string[]]
        $PropertiesOnCimClass
    )
    # Create the MyProcess type object for each
    $AllProcs = [System.Collections.Hashtable]@{}

    # Parameters to send to the Get-CimInstance cmdlet
    $GetCimInstanceParams = @{
        ClassName = 'CIM_Process'
    }

    # Get the current properties on the CIM class Win32_Process
    $PropertiesOnCimClass = Get-CimClass -ClassName Win32_Process | 
            Select-Object -ExpandProperty CimClassProperties |
            Select-Object -ExpandProperty Name

    if($PSBoundParameters.Keys.Contains('CimSession'))
    {
        # Add the CimSession to the GetCimInstanceParams hashtable
        $GetCimInstanceParams.Add('CimSession',($CimSession | Where-Object -Property Name -eq $Name))

        # Gather the Processes for the remote machine
        Get-CimInstance @GetCimInstanceParams | ForEach-Object -Process {
            if($PSBoundParameters.ContainsKey('PropertiesToShow'))
            {
                $ProcessToAdd = [MyProcess]::new($_,$PropertiesOnCimClass,$PropertiesToShow)
                $AllProcs.Add( $ProcessToAdd.ProcessId, $ProcessToAdd)
            }else{
                $ProcessToAdd = [MyProcess]::new($_,$PropertiesOnCimClass)
                $AllProcs.Add( $ProcessToAdd.ProcessId, $ProcessToAdd)
            }
        }
    }elseif($PSBoundParameters.Keys.Contains('ComputerName'))
    {
        # Add the CimSession to the GetCimInstanceParams hashtable
        $GetCimInstanceParams.Add('ComputerName',$ComputerName)

        # Gather the Processes for the remote machine
        Get-CimInstance @GetCimInstanceParams | ForEach-Object -Process {
            if($PSBoundParameters.ContainsKey('PropertiesToShow'))
            {
                $ProcessToAdd = [MyProcess]::new($_,$PropertiesOnCimClass,$PropertiesToShow)
                $AllProcs.Add( $ProcessToAdd.ProcessId, $ProcessToAdd)
            }else{
                $ProcessToAdd = [MyProcess]::new($_,$PropertiesOnCimClass)
                $AllProcs.Add( $ProcessToAdd.ProcessId, $ProcessToAdd)
            }
        }
    }else{
        Get-CimInstance @GetCimInstanceParams | ForEach-Object -Process {
            if($PSBoundParameters.ContainsKey('PropertiesToShow'))
            {
                $ProcessToAdd = [MyProcess]::new($_,$PropertiesOnCimClass,$PropertiesToShow)
                $AllProcs.Add( $ProcessToAdd.ProcessId, $ProcessToAdd)
            }else{
                $ProcessToAdd = [MyProcess]::new($_,$PropertiesOnCimClass)
                $AllProcs.Add( $ProcessToAdd.ProcessId, $ProcessToAdd)
            }
        }
    }

    Write-Verbose "All process count: $($AllProcs.Count)"
    # The array to rule them all
    $FinalArrayList = [System.Collections.ArrayList]@()

    # Add the computer name as the root
    if($PSBoundParameters.Keys.Contains('CimSession'))
    {
        $FinalArrayList.Add( ( [MyProcess]::new($CimSession.ComputerName, $true) ) ) | Out-Null
    }
    elseif($PSBoundParameters.Keys.Contains('ComputerName'))
    {
        $FinalArrayList.Add( ( [MyProcess]::new($ComputerName, $true) ) ) | Out-Null
    }
    else
    {
        $FinalArrayList.Add( ( [MyProcess]::new($env:COMPUTERNAME, $true) ) ) | Out-Null
    }
    

    # Set isOrphaned for all processes where the parent process isn't currently running
    ($AllProcs.Keys | ForEach-Object { $AllProcs.$_ } | Where-Object {$_.ParentProcessId -notin $AllProcs.Keys}).Foreach('SetIsOrphaned')
    Write-Verbose "Orphaned Processes: $(($AllProcs.Keys | ForEach-Object { $AllProcs.$_ } | Where-Object {$_.ParentProcessId -notin $AllProcs.Keys}).Count)"
    
    # Add children to each that have a currently running parent process
    $ParentProcesses = [System.Collections.Hashtable]@{}

    # Group children processes under parent
    $ParentProcesses = Invoke-ProcessGrouping -ParentProcesses $AllProcs

    # Add each of the completed set to the final arraylist
    $FinalArrayList.AddRange( $ParentProcesses.Values )

    # Keep a tab count for horizontal spacing
    # $CurrentTabCount = 0

    # Write the computer name as the root of the tree
    Write-Output "$(($FinalArrayList | Select-Object -First 1).Name)"

    $FinalArrayList | Select-Object -Skip 1 | Sort-Object -Property ProcessId | ForEach-Object -Process {
        $CurrentTab = ""
        # $CurrentTabCount++
        Write-MessageColor -ProcessToWrite $_ -CurrentTab  $CurrentTab
        # $CurrentTabCount++
        if($_.ChildProcess)
        {
            $ChildCount = $_.ChildProcess | Measure-Object | Select-Object -ExpandProperty Count
            if($ChildCount -gt 0){
                $CurrentTab = Set-CurrentTabString -InputTabString $CurrentTab -Increase
            }else{
                $CurrentTab = Set-CurrentTabString -InputTabString $CurrentTab -LastChild
            }
            $_.ChildProcess | Sort-Object -Property ProcessId | ForEach-Object -Process {
                Invoke-ProcessChild -ChildProc $_ -CurrentTab $CurrentTab
            } 
        }
        # $CurrentTabCount--
    }
}

# Helper function
# Accepts the total array of processes
# Places each proces under its parent
# Returns the final array without duplicates
function Invoke-ProcessGrouping
{
    param(
        [System.Collections.Hashtable]
        $ParentProcesses
        ,
        [Parameter(DontShow)]
        [MyProcess]
        $ThisParentProcess
        ,
        [Parameter(DontShow)]
        [System.Collections.ArrayList]
        $SpentProcesses
    )

    # Hold the processes to remove from the root here until after looping through all
    $SpentProcesses = [System.Collections.ArrayList]@()

    # Place children under their parent
    $ParentProcesses.Keys | ForEach-Object -Process {
        $Process = $null
        $Process = $ParentProcesses.$_
        $ParentProcessID = $null
        $ParentProcessID = $Process.ParentProcessID

        if($ParentProcesses.Contains($ParentProcessID))
        {
            $ThisParentProcess = $null
            $ThisParentProcess = $ParentProcesses.$ParentProcessID
            $ThisParentProcess.AddChildProcess( $Process )
            if(! $Process.isOrphaned)
            {
                $SpentProcesses.Add( $Process ) | Out-Null
            }
            
        }

    }

    # Remove the spent processes from the root level
    $SpentProcesses | ForEach-Object -Process {
        $ParentProcesses.Remove($_.ProcessId) | Out-Null
    }

    Write-Output $ParentProcesses
}

# Helper function
# Increases or decreases the tree indentation
function Set-CurrentTabString
{
    param(
        $InputTabString
        ,
        [switch]$Increase
        ,
        [switch]$LastChild
    )
    if($Increase)
    {
        $OutputString = $InputTabString + "|    "
        Write-Output $OutputString
    }else{
        $OutputString = $InputTabString.Substring($InputTabString.Length - 4)
        Write-Output $OutputString
    }
}

# Helper function
# Prints the process and associated properties to screen
function Write-MessageColor
{
    param(
        [MyProcess]$ProcessToWrite
        ,
        [string]$CurrentTab
    )
    $ProcessToWrite.WriteString($CurrentTab)
}

# Helper function
# Process all the child objects of the object passed in
# Recursive function
function Invoke-ProcessChild
{
    param (
        [MyProcess]$ChildProc
        ,
        [string]$CurrentTab
    )
    Write-MessageColor -ProcessToWrite $ChildProc -CurrentTab $CurrentTab
    if($ChildProc.ChildProcess)
    {
        $NewChildCount = $_.ChildProcess | Measure-Object | Select-Object -ExpandProperty Count
        if($NewChildCount -gt 0){
            $CurrentTab = Set-CurrentTabString -InputTabString $CurrentTab -Increase
        }else{
            $CurrentTab = Set-CurrentTabString -InputTabString $CurrentTab -LastChild
        }
        $ChildProc.ChildProcess | Sort-Object -Property ProcessId | ForEach-Object -Process {
            Invoke-ProcessChild -ChildProc $_ -CurrentTab $CurrentTab
        } 
    }
    $CurrentTabCount--
}
