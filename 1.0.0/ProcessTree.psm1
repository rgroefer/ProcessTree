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
}
function Get-ProcessTree
{
    [CmdletBinding()]
    param(
        [System.Collections.Hashtable]
        $AllProcs
        ,
        [System.Collections.ArrayList]
        $FinalArrayList
        ,
        [System.Collections.Hashtable]
        $ParentProcesses
        ,
        [string]
        $CurrentTab
    )

    BEGIN
    {

    }
    PROCESS
    {
        # Create the MyProcess type object for each
        $AllProcs = [System.Collections.Hashtable]@{}
        Get-CimInstance -ClassName CIM_Process | ForEach-Object -Process {
            $ProcessToAdd = [MyProcess]::new($_.ProcessId, $_.ParentProcessId, $_.Name)
            $AllProcs.Add( $ProcessToAdd.ProcessId, $ProcessToAdd)
        }
        Write-Verbose "All process count: $($AllProcs.Count)"
        # The array to rule them all
        $FinalArrayList = [System.Collections.ArrayList]@()

        # Add the computer name as the root
        $FinalArrayList.Add( ( [MyProcess]::new(0,0,$Env:COMPUTERNAME) ) ) | Out-Null

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
                    Write-ProcessChild -ChildProc $_ -CurrentTab $CurrentTab
                } 
            }
            # $CurrentTabCount--
        }
    }
    END{}
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
        [int]$CurrentTabCount
        ,
        [string]$CurrentTab
        ,
        [int]$ChildCount
        ,
        [Parameter(DontShow)]
        [string]
        $TypeString
    )
    if($ProcessToWrite.isOrphaned)
    {
        Write-Output "$($CurrentTab)\--$($ProcessToWrite.Name) - PID: $($ProcessToWrite.ProcessId) - ParentPID: `e[31m$($ProcessToWrite.ParentProcessID)`e[0m"
    }else{
        Write-Output "$($CurrentTab)\--$($ProcessToWrite.Name) - PID: $($ProcessToWrite.ProcessId) - ParentPID: `e[32m$($ProcessToWrite.ParentProcessID)`e[0m"
    }
    
}
function Write-ProcessChild
{
    param (
        [MyProcess]$ChildProc
        ,
        [int]$CurrentTabCount
        ,
        [string]$CurrentTab
        ,
        [int]$ChildCount
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
            Write-ProcessChild -ChildProc $_ -CurrentTab $CurrentTab
        } 
    }
    $CurrentTabCount--
}
