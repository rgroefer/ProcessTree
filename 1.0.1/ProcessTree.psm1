# Class to handle the CIM_Process class
class MyProcess
{
    [int]$ProcessId
    [int]$ParentProcessId
    [string]$Name
    [bool]$isOrphaned
    [System.Collections.ArrayList]$ChildProcess

    # Constructor
    MyProcess([int]$ProcessId, [int]$ParentProcessId, [string]$Name)
    {
        $this.ParentProcessId = $ParentProcessId
        $this.ProcessId = $ProcessId
        $this.Name = $Name
        $this.ChildProcess = [System.Collections.ArrayList]@()
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
        if($this.isOrphaned)
        {
            Return "$($CurrentTab)\--$($this.Name) - PID: $($this.ProcessId) - ParentPID: `e[31m$($this.ParentProcessID)`e[0m"
        }else{
            Return "$($CurrentTab)\--$($this.Name) - PID: $($this.ProcessId) - ParentPID: `e[32m$($this.ParentProcessID)`e[0m"
        }
    }
}
function Get-ProcessTree
{
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
        [Parameter(DontShow)]
        [CimSession]
        $CimSession
    )

    BEGIN
    {
        
    }
    PROCESS
    {
        Write-Verbose "Processing"

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
            Invoke-ProcessTree
        }
        
        
    }
    END{}

}
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
    )
    # Create the MyProcess type object for each
    $AllProcs = [System.Collections.Hashtable]@{}

    $GetCimInstanceParams = @{
        ClassName = 'CIM_Process'
    }

    if($PSBoundParameters.Keys.Contains('CimSession'))
    {
        # Add the CimSession to the GetCimInstanceParams hashtable
        $GetCimInstanceParams.Add('CimSession',($CimSession | Where-Object -Property Name -eq $Name))

        # Gather the Processes for the remote machine
        Get-CimInstance @GetCimInstanceParams | ForEach-Object -Process {
            $ProcessToAdd = [MyProcess]::new($_.ProcessId, $_.ParentProcessId, $_.Name)
            $AllProcs.Add( $ProcessToAdd.ProcessId, $ProcessToAdd)
        }
    }elseif($PSBoundParameters.Keys.Contains('ComputerName'))
    {
        # Add the CimSession to the GetCimInstanceParams hashtable
        $GetCimInstanceParams.Add('ComputerName',$ComputerName)

        # Gather the Processes for the remote machine
        Get-CimInstance @GetCimInstanceParams | ForEach-Object -Process {
            $ProcessToAdd = [MyProcess]::new($_.ProcessId, $_.ParentProcessId, $_.Name)
            $AllProcs.Add( $ProcessToAdd.ProcessId, $ProcessToAdd)
        }
    }

    Get-CimInstance @GetCimInstanceParams | ForEach-Object -Process {
        $ProcessToAdd = [MyProcess]::new($_.ProcessId, $_.ParentProcessId, $_.Name)
        $AllProcs.Add( $ProcessToAdd.ProcessId, $ProcessToAdd)
    }

    Write-Verbose "All process count: $($AllProcs.Count)"
    # The array to rule them all
    $FinalArrayList = [System.Collections.ArrayList]@()

    # Add the computer name as the root
    if($PSBoundParameters.Keys.Contains('CimSession'))
    {
        $FinalArrayList.Add( ( [MyProcess]::new(0,0,$CimSession.ComputerName) ) ) | Out-Null
    }
    elseif($PSBoundParameters.Keys.Contains('ComputerName'))
    {
        $FinalArrayList.Add( ( [MyProcess]::new(0,0,$ComputerName) ) ) | Out-Null
    }
    else
    {
        $FinalArrayList.Add( ( [MyProcess]::new(0,0,$env:COMPUTERNAME) ) ) | Out-Null
    }
    

    # Set isOrphaned for all processes where the parent process id isn't currently running
    ($AllProcs.Keys | ForEach-Object { $AllProcs.$_ } | Where-Object {$_.ParentProcessId -notin $AllProcs.Keys}).Foreach('SetIsOrphaned')
    Write-Verbose "Orphaned Processes: $(($AllProcs.Keys | ForEach-Object { $AllProcs.$_ } | Where-Object {$_.ParentProcessId -notin $AllProcs.Keys}).Count)"
    # Add children to each that have a currently running parent process
    $ParentProcesses = [System.Collections.Hashtable]@{}

    # Run first time with $AllProcs
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
function Invoke-ProcessGrouping
{
    param(
        [System.Collections.Hashtable]
        $ParentProcesses
        ,
        # [System.Collections.Hashtable]
        # $NewParentProcesses
        # ,
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

        # Write-Host "Process: $($Process.ProcessID)"
        # Write-Host "Parent Process: $ParentProcessID"
        # Write-Host "Contains Parent: $($ParentProcesses.Contains($ParentProcessID))"
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
function Write-MessageColor
{
    param(
        [MyProcess]$ProcessToWrite
        ,
        [string]$CurrentTab
    )
    $ProcessToWrite.WriteString($CurrentTab)
}
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
