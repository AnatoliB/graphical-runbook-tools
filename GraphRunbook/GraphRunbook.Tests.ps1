﻿$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.ps1$'

Get-Module -Name $sut -All | Remove-Module -Force -ErrorAction Ignore
Import-Module -Name "$here\$sut.psm1" -Force -ErrorAction Stop

InModuleScope $sut {
    function WithRunbookFile(
            [Orchestrator.GraphRunbook.Model.GraphRunbook]$Runbook,
            [scriptblock]$Action) {
        $SerializedRunbook = [Orchestrator.GraphRunbook.Model.Serialization.RunbookSerializer]::Serialize($Runbook)
        $File = New-TemporaryFile
        try {
            $SerializedRunbook | Out-File $File.FullName
            $Action.Invoke($File)
        }
        finally {
            Remove-Item $File -ErrorAction SilentlyContinue
        }
    }
    
    Describe "Show-GraphRunbookActivityTraces" {

        $TestJobId = New-Guid
        $TestResourceGroup = 'TestResourceGroupName'
        $TestAutomationAccount = 'TestAccountName'

        $TestJobOutputRecords = @(
            @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityStart",Time:"2016-11-23 23:04"}' } },
            @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityInput",Time:"2016-11-23 23:05",Values:{Data:{Input1:"A",Input2:"B"}}}' } },
            @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityOutput",Time:"2016-11-23 23:05"}' } },
            @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity1",Event:"ActivityEnd",Time:"2016-11-23 23:06",DurationSeconds:1.2}' } },
            @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity2",Event:"ActivityStart",Time:"2016-11-23 23:09"}' } },
            @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity2",Event:"ActivityOutput",Time:"2016-11-23 23:12",Values:{Data:[2,7,1]}}' } },
            @{ Value = @{ Message = 'GraphTrace:{Activity:"Activity2",Event:"ActivityEnd",Time:"2016-11-23 23:13",DurationSeconds:7}' } }
        )

        function VerifyShowObjectInput($InputObject) {
            $InputObject | Should not be $null
            $InputObject | Measure-Object | % Count | Should be 1

            $InputObject.'Job ID' | Should be $TestJobId

            $ActivityExecutionInstances = $InputObject.'Activity execution instances'

            $ActivityExecutionInstances | Measure-Object | % Count | Should be 2

            $ActivityExecutionInstances[0].Activity | Should be 'Activity1'
            $ActivityExecutionInstances[0].Start | Should be (Get-Date '2016-11-23 23:04')
            $ActivityExecutionInstances[0].End | Should be (Get-Date '2016-11-23 23:06')
            $ActivityExecutionInstances[0].Duration | Should be ([System.TimeSpan]::FromSeconds(1.2))
            $ActivityExecutionInstances[0].Input | Should not be $null
            $ActivityExecutionInstances[0].Input.Input1 | Should be "A"
            $ActivityExecutionInstances[0].Input.Input2 | Should be "B"
            $ActivityExecutionInstances[0].Output | Should be $null

            $ActivityExecutionInstances[1].Activity | Should be 'Activity2'
            $ActivityExecutionInstances[1].Start | Should be (Get-Date '2016-11-23 23:09')
            $ActivityExecutionInstances[1].End | Should be (Get-Date '2016-11-23 23:13')
            $ActivityExecutionInstances[1].Duration | Should be ([System.TimeSpan]::FromSeconds(7))
            $ActivityExecutionInstances[1].Input | Should be $null
            $ActivityExecutionInstances[1].Output | Measure-Object | % Count | Should be 3
            $ActivityExecutionInstances[1].Output[0] | Should be 2
            $ActivityExecutionInstances[1].Output[1] | Should be 7
            $ActivityExecutionInstances[1].Output[2] | Should be 1
        }

        Context "When Graph Runbook activity traces exist and job ID is known" {
            Mock Get-AzureRmAutomationJobOutput -Verifiable `
                -ParameterFilter {
                    ($ResourceGroupName -eq $TestResourceGroup) -and
                    ($AutomationAccountName -eq $TestAutomationAccount) -and
                    ($JobId -eq $TestJobId) -and
                    ($Stream -eq 'Verbose')
                } `
                -MockWith {
                    0..($TestJobOutputRecords.Length - 1)
                }

            function Get-AzureRmAutomationJobOutputRecord {
                [CmdletBinding()]
                param ([Parameter(ValueFromPipeline = $true)] $Id)

                process {
                    $TestJobOutputRecords[$Id]
                }
            }

            Mock Show-Object -Verifiable `
                -MockWith {
                    VerifyShowObjectInput -InputObject $InputObject
                }

            Show-GraphRunbookActivityTraces `
                -ResourceGroupName $TestResourceGroup `
                -AutomationAccountName $TestAutomationAccount  `
                -JobId $TestJobId

            It "Shows Graph Runbook activity traces" {
                Assert-VerifiableMocks
            }
        }

        Context "When Graph Runbook activity traces exist and runbook name is known" {
            $TestRunbookName = 'TestRunbookName'

            Mock Get-AzureRmAutomationJob -Verifiable `
                -ParameterFilter {
                    ($ResourceGroupName -eq $TestResourceGroup) -and
                    ($AutomationAccountName -eq $TestAutomationAccount) -and
                    ($RunbookName -eq $TestRunbookName)
                } `
                -MockWith {
                    $LatestJobStartTime = Get-Date
                    New-Object PSObject -Property @{ StartTime = $LatestJobStartTime - [System.TimeSpan]::FromSeconds(1); JobId = New-Guid }
                    New-Object PSObject -Property @{ StartTime = $LatestJobStartTime; JobId = $TestJobId }
                    New-Object PSObject -Property @{ StartTime = $LatestJobStartTime - [System.TimeSpan]::FromSeconds(2); JobId = New-Guid }
                }

            Mock Get-AzureRmAutomationJobOutput -Verifiable `
                -ParameterFilter {
                    ($ResourceGroupName -eq $TestResourceGroup) -and
                    ($AutomationAccountName -eq $TestAutomationAccount) -and
                    ($Stream -eq 'Verbose')
                } `
                -MockWith {
                    $JobId | Should be $TestJobId > $null

                    0..($TestJobOutputRecords.Length - 1)
                }

            function Get-AzureRmAutomationJobOutputRecord {
                [CmdletBinding()]
                param ([Parameter(ValueFromPipeline = $true)] $Id)

                process {
                    $TestJobOutputRecords[$Id]
                }
            }

            Mock Show-Object -Verifiable `
                -MockWith {
                    VerifyShowObjectInput -InputObject $InputObject
                }

            Show-GraphRunbookActivityTraces `
                -ResourceGroupName $TestResourceGroup `
                -AutomationAccountName $TestAutomationAccount  `
                -RunbookName $TestRunbookName

            It "Shows Graph Runbook activity traces" {
                Assert-VerifiableMocks
            }
        }

        Context "When no Graph Runbook activity traces" {
            Mock Get-AzureRmAutomationJobOutput -Verifiable `
                -ParameterFilter {
                    ($ResourceGroupName -eq $TestResourceGroup) -and
                    ($AutomationAccountName -eq $TestAutomationAccount) -and
                    ($JobId -eq $TestJobId) -and
                    ($Stream -eq 'Verbose')
                } `
                -MockWith {
                    1
                }

            function Get-AzureRmAutomationJobOutputRecord {
                [CmdletBinding()]
                param ( [Parameter(ValueFromPipeline = $true)] $Id)

                @{ Value = @{ Message = 'Regular verbose message' } }
            }

            Mock Write-Error -Verifiable `
                -MockWith {
                    $Message | Should be ('No activity traces found. Make sure activity tracing and ' +
                                          'logging Verbose stream are enabled in the runbook configuration.')
                }

            Show-GraphRunbookActivityTraces `
                -ResourceGroupName $TestResourceGroup `
                -AutomationAccountName $TestAutomationAccount  `
                -JobId $TestJobId

            It "Shows 'no activity traces' message" {
                Assert-VerifiableMocks
            }
        }

        Context "When no Verbose output" {
            Mock Get-AzureRmAutomationJobOutput -Verifiable `
                -ParameterFilter {
                    ($ResourceGroupName -eq $TestResourceGroup) -and
                    ($AutomationAccountName -eq $TestAutomationAccount) -and
                    ($JobId -eq $TestJobId) -and
                    ($Stream -eq 'Verbose')
                }

            Mock Get-AzureRmAutomationJobOutputRecord

            Mock Write-Error -Verifiable `
                -MockWith {
                    $Message | Should be ('No activity traces found. Make sure activity tracing and ' +
                                          'logging Verbose stream are enabled in the runbook configuration.')
                }

            Show-GraphRunbookActivityTraces `
                -ResourceGroupName $TestResourceGroup `
                -AutomationAccountName $TestAutomationAccount  `
                -JobId $TestJobId

            It "Shows 'no activity traces' message" {
                Assert-VerifiableMocks
                Assert-MockCalled Get-AzureRmAutomationJobOutputRecord -Times 0
            }
        }
    }

    Describe "Convert-GraphRunbookToPowerShellData" {
        Add-GraphRunbookModelAssembly

        Context "When GraphRunbook is empty" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be @"
@{

}

"@
            }
        }

        Context "When GraphRunbook has parameters" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook

            $ParameterA = New-Object Orchestrator.GraphRunbook.Model.Parameter -ArgumentList 'ParamA'
            $ParameterA.Optional = $false
            $ParameterA.Description = 'Parameter description'
            $Runbook.AddParameter($ParameterA)

            $ParameterB = New-Object Orchestrator.GraphRunbook.Model.Parameter -ArgumentList 'ParamB'
            $ParameterB.Optional = $true
            $ParameterB.DefaultValue = 'Default value'
            $Runbook.AddParameter($ParameterB)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be @"
@{

Parameters = @(
    @{
        Name = 'ParamA'
        Description = 'Parameter description'
        Mandatory = `$true
    }
    @{
        Name = 'ParamB'
        DefaultValue = 'Default value'
    }
)

}

"@
            }
        }

        Context "When GraphRunbook contains Code activity" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $Activity = New-Object Orchestrator.GraphRunbook.Model.WorkflowScriptActivity -ArgumentList 'Activity name'
            $Activity.Description = 'Activity description'
            $Activity.Begin = "'Begin code block'"
            $Activity.Process = "'Process code block'"
            $Activity.End = "'End code block'"
            $Activity.CheckpointAfter = $true
            $Activity.ExceptionsToErrors = $true
            $Activity.LoopExitCondition = '$RetryData.NumberOfAttempts -gt 5'
            $Activity.PositionX = 12
            $Activity.PositionY = 456
            $Runbook.AddActivity($Activity)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Description = 'Activity description'
        Type = 'Code'
        Begin = {
            'Begin code block'
        }
        Process = {
            'Process code block'
        }
        End = {
            'End code block'
        }
        CheckpointAfter = `$true
        ExceptionsToErrors = `$true
        Retry = @{
            ExitCondition = {
                `$RetryData.NumberOfAttempts -gt 5
            }
        }
        Position = 12, 456
    }
)

}

"@
            }
        }

        Context "When GraphRunbook contains Command activity" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.ModuleName = 'MyModule'
            $CommandActivityType.CommandName = 'Do-Something'
            $Activity = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList 'Activity name', $CommandActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $Activity.Parameters.Add("Parameter1", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'Value 1'))
            $Activity.Parameters.Add("Parameter2", (New-Object Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor -ArgumentList 'Activity A'))
            $Activity.Parameters.Add("Parameter3", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList @($null)))
            $Activity.CustomParameters = '-CustomParam CustomValue'
            $Activity.Description = 'Activity description'
            $Activity.CheckpointAfter = $true
            $Activity.ExceptionsToErrors = $true
            $Activity.LoopExitCondition = '$RetryData.NumberOfAttempts -gt 5'
            $LoopDelayTimeSpan = New-Object System.TimeSpan -ArgumentList 8765
            $Activity.LoopDelay = New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList $LoopDelayTimeSpan
            $Activity.PositionX = 12
            $Activity.PositionY = 456
            $Runbook.AddActivity($Activity)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Description = 'Activity description'
        Type = 'Command'
        ModuleName = 'MyModule'
        CommandName = 'Do-Something'
        Parameters = @{
            Parameter1 = 'Value 1'
            Parameter2 = @{
                SourceType = 'ActivityOutput'
                Activity = 'Activity A'
            }
            Parameter3 = `$null
        }
        CustomParameters = '-CustomParam CustomValue'
        CheckpointAfter = `$true
        ExceptionsToErrors = `$true
        Retry = @{
            ExitCondition = {
                `$RetryData.NumberOfAttempts -gt 5
            }
            Delay = 8765
        }
        Position = 12, 456
    }
)

}

"@
            }
        }

        Context "When GraphRunbook contains minimal Command activity" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.CommandName = 'Do-Something'
            $Activity = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList 'Activity name', $CommandActivityType
            $Runbook.AddActivity($Activity)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Type = 'Command'
        CommandName = 'Do-Something'
    }
)

}

"@
            }
        }

        Context "When GraphRunbook contains InvokeRunbook activity" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $InvokeRunbookActivityType = New-Object Orchestrator.GraphRunbook.Model.InvokeRunbookActivityType
            $InvokeRunbookActivityType.CommandName = 'Do-Something'
            $Activity = New-Object Orchestrator.GraphRunbook.Model.InvokeRunbookActivity -ArgumentList 'Activity name', $InvokeRunbookActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $Activity.Parameters.Add("Parameter1", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'Value 1'))
            $Activity.Parameters.Add("Parameter2", (New-Object Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor -ArgumentList 'Activity A'))
            $Activity.Parameters.Add("Parameter3", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList @($null)))
            $Activity.CustomParameters = '-CustomParam CustomValue'
            $Activity.Description = 'Activity description'
            $Activity.CheckpointAfter = $true
            $Activity.ExceptionsToErrors = $true
            $Activity.LoopExitCondition = '$RetryData.NumberOfAttempts -gt 5'
            $Activity.PositionX = 12
            $Activity.PositionY = 456
            $Runbook.AddActivity($Activity)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Description = 'Activity description'
        Type = 'InvokeRunbook'
        CommandName = 'Do-Something'
        Parameters = @{
            Parameter1 = 'Value 1'
            Parameter2 = @{
                SourceType = 'ActivityOutput'
                Activity = 'Activity A'
            }
            Parameter3 = `$null
        }
        CustomParameters = '-CustomParam CustomValue'
        CheckpointAfter = `$true
        ExceptionsToErrors = `$true
        Retry = @{
            ExitCondition = {
                `$RetryData.NumberOfAttempts -gt 5
            }
        }
        Position = 12, 456
    }
)

}

"@
            }
        }

        Context "When GraphRunbook contains Junction activity" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $Activity = New-Object Orchestrator.GraphRunbook.Model.JunctionActivity -ArgumentList 'Activity name'
            $Activity.Description = 'Activity description'
            $Activity.CheckpointAfter = $true
            $Activity.PositionX = 12
            $Activity.PositionY = 456
            $Runbook.AddActivity($Activity)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Description = 'Activity description'
        Type = 'Junction'
        CheckpointAfter = `$true
        Position = 12, 456
    }
)

}

"@
            }
        }

        function CreateRunbookWithCommandActivityWithParameter($ValueDescriptor) {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.CommandName = 'Do-Something'
            $Activity = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList 'Activity name', $CommandActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $Activity.Parameters.Add('ParameterName', $ValueDescriptor)
            [void]$Runbook.AddActivity($Activity)
            $Runbook
        }

        function CreateExpectedRunbookTextWithCommandActivityWithParameter($ParameterText) {
@"
@{

Activities = @(
    @{
        Name = 'Activity name'
        Type = 'Command'
        CommandName = 'Do-Something'
        Parameters = @{
            ParameterName = $ParameterText
        }
    }
)

}

"@            
        }

        Context "When GraphRunbook contains Command activity with ConstantValueDescriptor" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'Parameter value')

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter "'Parameter value'")
            }
        }

        Context "When GraphRunbook contains Command activity with NullConstantValueDescriptor" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.NullConstantValueDescriptor)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter "`$null")
            }
        }

        Context "When GraphRunbook contains Command activity with EmptyStringConstantValueDescriptor" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.EmptyStringConstantValueDescriptor)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter "''")
            }
        }

        Context "When GraphRunbook contains Command activity with ActivityOutputValueDescriptor (activity name only)" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor -ArgumentList 'Source activity')

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter @"
@{
                SourceType = 'ActivityOutput'
                Activity = 'Source activity'
            }
"@)
            }
        }

        Context "When GraphRunbook contains Command activity with ActivityOutputValueDescriptor (activity name and field path)" {
            $FieldPath = New-Object 'System.Collections.Generic.List`1[string]'
            $FieldPath.Add('Field1')
            $FieldPath.Add('Field2')
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor -ArgumentList 'Source activity', $FieldPath)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter @"
@{
                SourceType = 'ActivityOutput'
                Activity = 'Source activity'
                FieldPath = @(
                    'Field1'
                    'Field2'
                )
            }
"@)
            }
        }

        Context "When GraphRunbook contains Command activity with PowerShellExpressionValueDescriptor" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.PowerShellExpressionValueDescriptor -ArgumentList '"PowerShell expression"')

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter @"
{
                "PowerShell expression"
            }
"@)
            }
        }

        Context "When GraphRunbook contains Command activity with RunbookParameterValueDescriptor" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.RunbookParameterValueDescriptor -ArgumentList 'RunbookParameterName')

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter @"
@{
                SourceType = 'RunbookParameter'
                Name = 'RunbookParameterName'
            }
"@)
            }
        }

        Context "When GraphRunbook contains Command activity with AutomationCertificateValueDescriptor" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.AutomationCertificateValueDescriptor -ArgumentList 'AssetName')

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter @"
@{
                SourceType = 'AutomationCertificate'
                Name = 'AssetName'
            }
"@)
            }
        }

        Context "When GraphRunbook contains Command activity with AutomationCredentialValueDescriptor" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.AutomationCredentialValueDescriptor -ArgumentList 'AssetName')

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter @"
@{
                SourceType = 'AutomationCredential'
                Name = 'AssetName'
            }
"@)
            }
        }

        Context "When GraphRunbook contains Command activity with AutomationConnectionValueDescriptor" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.AutomationConnectionValueDescriptor -ArgumentList 'AssetName')

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter @"
@{
                SourceType = 'AutomationConnection'
                Name = 'AssetName'
            }
"@)
            }
        }

        Context "When GraphRunbook contains Command activity with AutomationVariableValueDescriptor" {
            $Runbook = CreateRunbookWithCommandActivityWithParameter `
                -ValueDescriptor (New-Object Orchestrator.GraphRunbook.Model.AutomationVariableValueDescriptor -ArgumentList 'AssetName')

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookTextWithCommandActivityWithParameter @"
@{
                SourceType = 'AutomationVariable'
                Name = 'AssetName'
            }
"@)
            }
        }

        function CreateRunbookWithLink($LinkType)
        {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook

            $ActivityA = New-Object Orchestrator.GraphRunbook.Model.WorkflowScriptActivity -ArgumentList 'Activity A'
            [void]$Runbook.AddActivity($ActivityA)

            $ActivityB = New-Object Orchestrator.GraphRunbook.Model.WorkflowScriptActivity -ArgumentList 'Activity B'
            [void]$Runbook.AddActivity($ActivityB)

            $LinkAtoB = New-Object Orchestrator.GraphRunbook.Model.Link -ArgumentList $ActivityA, $ActivityB, $LinkType
            [void]$Runbook.AddLink($LinkAtoB)

            $Runbook
            $LinkAtoB
        }

        function CreateExpectedRunbookWithLinkText($LinkText)
        {
@"
@{

Activities = @(
    @{
        Name = 'Activity A'
        Type = 'Code'
    }
    @{
        Name = 'Activity B'
        Type = 'Code'
    }
)

Links = @(
    $LinkText
)

}

"@
        }

        Context "When GraphRunbook contains regular sequence link" {
            $Runbook, $Link = CreateRunbookWithLink -LinkType Sequence
            $Link.Condition = '$ActivityOutput[''A''].Count -gt 0'
            $Link.LinkStreamType = 'Output'

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookWithLinkText @"
@{
        From = 'Activity A'
        To = 'Activity B'
        Type = 'Sequence'
        Condition = {
            `$ActivityOutput['A'].Count -gt 0
        }
    }
"@)
            }
        }

        Context "When GraphRunbook contains error pipeline link" {
            $Runbook, $Link = CreateRunbookWithLink -LinkType Pipeline
            $Link.Condition = '$ActivityOutput[''A''].Count -gt 0'
            $Link.LinkStreamType = 'Error'

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookWithLinkText @"
@{
        From = 'Activity A'
        To = 'Activity B'
        Stream = 'Error'
        Type = 'Pipeline'
        Condition = {
            `$ActivityOutput['A'].Count -gt 0
        }
    }
"@)
            }
        }

        Context "When GraphRunbook contains link with description" {
            $Runbook, $Link = CreateRunbookWithLink -LinkType Pipeline
            $Link.Description = 'My link description'

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookWithLinkText @"
@{
        From = 'Activity A'
        To = 'Activity B'
        Description = 'My link description'
        Type = 'Pipeline'
    }
"@)
            }
        }

        Context "When GraphRunbook contains link with empty description" {
            $Runbook, $Link = CreateRunbookWithLink -LinkType Pipeline
            $Link.Description = ''

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be (CreateExpectedRunbookWithLinkText @"
@{
        From = 'Activity A'
        To = 'Activity B'
        Type = 'Pipeline'
    }
"@)
            }
        }

        Context "When GraphRunbook contains activities, links, output types, and comments" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook

            $ParameterA = New-Object Orchestrator.GraphRunbook.Model.Parameter -ArgumentList 'ParamA'
            $Runbook.AddParameter($ParameterA)
            $ParameterB = New-Object Orchestrator.GraphRunbook.Model.Parameter -ArgumentList 'ParamB'
            $Runbook.AddParameter($ParameterB)

            $Comment1 = New-Object Orchestrator.GraphRunbook.Model.Comment -ArgumentList 'First comment'
            $Comment1.Text = 'First comment text'
            $Runbook.AddComment($Comment1)
            $Comment2 = New-Object Orchestrator.GraphRunbook.Model.Comment -ArgumentList 'Second comment'
            $Comment2.Text = 'Second comment text'
            $Runbook.AddComment($Comment2)

            $Runbook.AddOutputType('First output type');
            $Runbook.AddOutputType('Second output type');

            $ActivityA = New-Object Orchestrator.GraphRunbook.Model.WorkflowScriptActivity -ArgumentList 'Activity A'
            $ActivityA.Process = "'Hello'"
            $Runbook.AddActivity($ActivityA)

            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.CommandName = 'Get-Date'
            $ActivityB = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList 'Activity B', $CommandActivityType
            $ActivityB.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $ActivityB.Parameters.Add("Parameter1", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'Value 1'))
            $ActivityB.Parameters.Add("Parameter2", (New-Object Orchestrator.GraphRunbook.Model.ActivityOutputValueDescriptor -ArgumentList 'Activity A'))
            $ActivityB.Parameters.Add("Parameter3", (New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList @($null)))
            $Runbook.AddActivity($ActivityB)

            $LinkAtoB = New-Object Orchestrator.GraphRunbook.Model.Link -ArgumentList $ActivityA, $ActivityB, Pipeline
            $Runbook.AddLink($LinkAtoB)

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData -Runbook $Runbook

                $Text | Should be @"
@{

Parameters = @(
    @{
        Name = 'ParamA'
    }
    @{
        Name = 'ParamB'
    }
)

Comments = @(
    @{
        Name = 'First comment'
        Text = 'First comment text'
    }
    @{
        Name = 'Second comment'
        Text = 'Second comment text'
    }
)

OutputTypes = @(
    'First output type'
    'Second output type'
)

Activities = @(
    @{
        Name = 'Activity A'
        Type = 'Code'
        Process = {
            'Hello'
        }
    }
    @{
        Name = 'Activity B'
        Type = 'Command'
        CommandName = 'Get-Date'
        Parameters = @{
            Parameter1 = 'Value 1'
            Parameter2 = @{
                SourceType = 'ActivityOutput'
                Activity = 'Activity A'
            }
            Parameter3 = `$null
        }
    }
)

Links = @(
    @{
        From = 'Activity A'
        To = 'Activity B'
        Type = 'Pipeline'
    }
)

}

"@
            }
        }

        Context "When .graphrunbook file name is provided" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $Activity = New-Object Orchestrator.GraphRunbook.Model.WorkflowScriptActivity -ArgumentList 'Activity'
            $Runbook.AddActivity($Activity)

            WithRunbookFile -Runbook $Runbook -Action {
                param($File)

                It "Converts GraphRunbook to text" {
                    $Text = Convert-GraphRunbookToPowerShellData -RunbookFileName $File.FullName

                    $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity'
        Type = 'Code'
    }
)

}

"@
                }
            }
        }

        Context "When runbook name is provided" {
            $TestResourceGroup = 'TestResourceGroupName'
            $TestAutomationAccount = 'TestAccountName'
            $TestRunbookName = 'TestRunbookName'

            Mock Export-AzureRMAutomationRunbook -Verifiable `
                -MockWith {
                    $ResourceGroupName | Should be $TestResourceGroup > $null
                    $AutomationAccountName | Should be $AutomationAccountName > $null
                    $Name | Should be $TestRunbookName > $null
                    $Slot | Should be 'Published' > $null

                    $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
                    $Activity = New-Object Orchestrator.GraphRunbook.Model.WorkflowScriptActivity -ArgumentList 'Activity'
                    [void]$Runbook.AddActivity($Activity)
                    $SerializedRunbook = [Orchestrator.GraphRunbook.Model.Serialization.RunbookSerializer]::Serialize($Runbook)
                    $OutputFileName = Join-Path $OutputFolder "$Name.graphrunbook"
                    $SerializedRunbook | Out-File $OutputFileName

                    Get-Item -Path $OutputFileName
                }

            It "Converts GraphRunbook to text" {
                $Text = Convert-GraphRunbookToPowerShellData `
                    -RunbookName $TestRunbookName `
                    -ResourceGroupName $TestResourceGroup `
                    -AutomationAccount $TestAutomationAccount 

                $Text | Should be @"
@{

Activities = @(
    @{
        Name = 'Activity'
        Type = 'Code'
    }
)

}

"@
                Assert-VerifiableMocks
            }
        }
    }

    Describe "Get-GraphRunbookDependency" {
        function New-CommandActivity($ModuleName, $CommandName = 'Do-Something', $ValueDescriptors) {
            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.ModuleName = $ModuleName
            $CommandActivityType.CommandName = $CommandName
            $Activity = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList New-Guid, $CommandActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            foreach ($ValueDescriptor in $ValueDescriptors) {
                [void]$Activity.Parameters.Add((New-Guid).ToString(), $ValueDescriptor)
            }
            $Activity
        }

        function New-AssetAccessCommandActivity($ModuleName, $CommandName, $AssetName) {
            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.CommandName = $CommandName
            $Activity = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList New-Guid, $CommandActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $ValueDescriptor = New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList $AssetName
            [void]$Activity.Parameters.Add('Name', $ValueDescriptor)
            $Activity
        }

        function New-GetAutomationCertificateActivity($CertificateName) {
            New-AssetAccessCommandActivity -CommandName 'Get-AutomationCertificate' -AssetName $CertificateName
        }

        function New-GetAutomationConnectionActivity($ConnectionName) {
            New-AssetAccessCommandActivity -CommandName 'Get-AutomationConnection' -AssetName $ConnectionName
        }

        function New-GetAutomationCredentialActivity($CredentialName) {
            New-AssetAccessCommandActivity -CommandName 'Get-AutomationPSCredential' -AssetName $CredentialName
        }

        function New-GetAutomationVariableActivity($VariableName) {
            New-AssetAccessCommandActivity -CommandName 'Get-AutomationVariable' -AssetName $VariableName
        }

        function New-SetAutomationVariableActivity($VariableName) {
            New-AssetAccessCommandActivity -CommandName 'Set-AutomationVariable' -AssetName $VariableName
        }

        function New-InvokeRunbookActivity($RunbookName, $ValueDescriptors) {
            $InvokeRunbookCommandActivityType = New-Object Orchestrator.GraphRunbook.Model.InvokeRunbookActivityType
            $InvokeRunbookCommandActivityType.CommandName = $RunbookName
            $Activity = New-Object Orchestrator.GraphRunbook.Model.InvokeRunbookActivity -ArgumentList New-Guid, $InvokeRunbookCommandActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            foreach ($ValueDescriptor in $ValueDescriptors) {
                [void]$Activity.Parameters.Add((New-Guid).ToString(), $ValueDescriptor)
            }
            $Activity
        }

        Context "When modules are requested" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $Runbook.AddActivity((New-CommandActivity -ModuleName 'ModuleA'))
            $Runbook.AddActivity((New-CommandActivity -ModuleName 'ModuleB'))
            $Runbook.AddActivity((New-CommandActivity -ModuleName 'ModuleA'))
            $Runbook.AddActivity((New-CommandActivity -ModuleName ''))
            $Runbook.AddActivity((New-CommandActivity -ModuleName 'modulea'))
            $Runbook.AddActivity((New-CommandActivity -ModuleName 'MODULEB'))
            
            It "Outputs required modules" {
                $RequiredModules = Get-GraphRunbookDependency -Runbook $Runbook -DependencyType Module
                $RequiredModules | Measure-Object | ForEach-Object Count | Should be 2
                ($RequiredModules[0].Name -ieq 'ModuleA') | Should be $true
                $RequiredModules[0].Type | Should be 'Module'
                ($RequiredModules[1].Name -ieq 'ModuleB') | Should be $true
                $RequiredModules[1].Type | Should be 'Module'
            }
        }

        Context "When Automation Assets are requested" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook

            $Runbook.AddActivity((New-CommandActivity -ValueDescriptors `
                (New-Object Orchestrator.GraphRunbook.Model.AutomationVariableValueDescriptor -ArgumentList 'Variable1'),
                (New-Object Orchestrator.GraphRunbook.Model.AutomationCredentialValueDescriptor -ArgumentList 'Credential1'),
                (New-Object Orchestrator.GraphRunbook.Model.AutomationVariableValueDescriptor -ArgumentList 'VARIABLE1'),
                (New-Object Orchestrator.GraphRunbook.Model.AutomationConnectionValueDescriptor -ArgumentList 'Connection3'),
                (New-Object Orchestrator.GraphRunbook.Model.AutomationVariableValueDescriptor -ArgumentList 'Variable2'),
                (New-Object Orchestrator.GraphRunbook.Model.AutomationCertificateValueDescriptor -ArgumentList 'Certificate2')))

            $Runbook.AddActivity((New-CommandActivity -ValueDescriptors @()))

            $Runbook.AddActivity((New-CommandActivity -ValueDescriptors `
                (New-Object Orchestrator.GraphRunbook.Model.AutomationConnectionValueDescriptor -ArgumentList 'Connection2'),
                (New-Object Orchestrator.GraphRunbook.Model.AutomationVariableValueDescriptor -ArgumentList 'variable1'),
                (New-Object Orchestrator.GraphRunbook.Model.AutomationCertificateValueDescriptor -ArgumentList 'certificate1'),
                (New-Object Orchestrator.GraphRunbook.Model.AutomationConnectionValueDescriptor -ArgumentList 'Connection1')))

            $Runbook.AddActivity((New-GetAutomationCertificateActivity -CertificateName 'Certificate3'))
            $Runbook.AddActivity((New-GetAutomationConnectionActivity -ConnectionName 'Connection4'))
            $Runbook.AddActivity((New-GetAutomationCredentialActivity -CredentialName 'Credential2'))
            $Runbook.AddActivity((New-GetAutomationVariableActivity -VariableName 'Variable3'))
            $Runbook.AddActivity((New-SetAutomationVariableActivity -VariableName 'variable4'))
            
            It "Outputs required Automation Assets" {
                $RequiredAssets = Get-GraphRunbookDependency -Runbook $Runbook -DependencyType AutomationAsset
                $RequiredAssets | Measure-Object | ForEach-Object Count | Should be 13

                $RequiredVariables = $RequiredAssets | Where-Object { $_.Type -eq 'AutomationVariable' }
                $RequiredVariables | Measure-Object | ForEach-Object Count | Should be 4
                ($RequiredVariables[0].Name -ieq 'Variable1') | Should be $true
                $RequiredVariables[1].Name | Should be 'Variable2'
                $RequiredVariables[2].Name | Should be 'Variable3'
                $RequiredVariables[3].Name | Should be 'variable4'
                
                $RequiredCertificates = $RequiredAssets | Where-Object { $_.Type -eq 'AutomationCertificate' }
                $RequiredCertificates | Measure-Object | ForEach-Object Count | Should be 3
                $RequiredCertificates[0].Name | Should be 'certificate1'
                $RequiredCertificates[1].Name | Should be 'Certificate2'
                $RequiredCertificates[2].Name | Should be 'Certificate3'
                
                $RequiredConnections = $RequiredAssets | Where-Object { $_.Type -eq 'AutomationConnection' }
                $RequiredConnections | Measure-Object | ForEach-Object Count | Should be 4
                $RequiredConnections[0].Name | Should be 'Connection1'
                $RequiredConnections[1].Name | Should be 'Connection2'
                $RequiredConnections[2].Name | Should be 'Connection3'
                $RequiredConnections[3].Name | Should be 'Connection4'
                
                $RequiredCredentials = $RequiredAssets | Where-Object { $_.Type -eq 'AutomationCredential' }
                $RequiredCredentials | Measure-Object | ForEach-Object Count | Should be 2
                $RequiredCredentials[0].Name | Should be 'Credential1'
                $RequiredCredentials[1].Name | Should be 'Credential2'
            }
        }

        Context "When runbooks are requested" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $Runbook.AddActivity((New-InvokeRunbookActivity -RunbookName 'RunbookA'))
            $Runbook.AddActivity((New-InvokeRunbookActivity -RunbookName 'RunbookB'))
            $Runbook.AddActivity((New-InvokeRunbookActivity -RunbookName 'runbooka'))

            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.CommandName = 'Start-AzureRmAutomationRunbook'
            $Activity = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList New-Guid, $CommandActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $ValueDescriptor = New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'RunbookC'
            $Activity.Parameters.Add('Name', $ValueDescriptor)
            $Runbook.AddActivity($Activity)

            $CommandActivityType = New-Object Orchestrator.GraphRunbook.Model.CommandActivityType
            $CommandActivityType.CommandName = 'Start-AzureAutomationRunbook'
            $Activity = New-Object Orchestrator.GraphRunbook.Model.CommandActivity -ArgumentList New-Guid, $CommandActivityType
            $Activity.Parameters = New-Object Orchestrator.GraphRunbook.Model.ActivityParameters
            $ValueDescriptor = New-Object Orchestrator.GraphRunbook.Model.ConstantValueDescriptor -ArgumentList 'RunbookD'
            $Activity.Parameters.Add('Name', $ValueDescriptor)
            $Runbook.AddActivity($Activity)

            It "Outputs required runbooks" {
                $RequiredRunbooks = Get-GraphRunbookDependency -Runbook $Runbook -DependencyType Runbook
                $RequiredRunbooks | Measure-Object | ForEach-Object Count | Should be 4
                ($RequiredRunbooks[0].Name -ieq 'RunbookA') | Should be $true
                $RequiredRunbooks[0].Type | Should be 'Runbook'
                $RequiredRunbooks[1].Name | Should be 'RunbookB'
                $RequiredRunbooks[1].Type | Should be 'Runbook'
                $RequiredRunbooks[2].Name | Should be 'RunbookC'
                $RequiredRunbooks[2].Type | Should be 'Runbook'
                $RequiredRunbooks[3].Name | Should be 'RunbookD'
                $RequiredRunbooks[3].Type | Should be 'Runbook'
            }
        }

        Context "When all dependencies are requested" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $Runbook.AddActivity((New-CommandActivity -ModuleName 'ModuleA'))

            $Runbook.AddActivity((New-CommandActivity -ValueDescriptors `
                (New-Object Orchestrator.GraphRunbook.Model.AutomationVariableValueDescriptor -ArgumentList 'Variable1'),
                (New-Object Orchestrator.GraphRunbook.Model.AutomationCredentialValueDescriptor -ArgumentList 'Credential1')))

            $Runbook.AddActivity((New-InvokeRunbookActivity -RunbookName 'RunbookA'))

            $Runbook.AddActivity((New-Object Orchestrator.GraphRunbook.Model.WorkflowScriptActivity -ArgumentList 'Activity'))
            
            It "Outputs all dependencies" {
                $AllDependencies = Get-GraphRunbookDependency -Runbook $Runbook -DependencyType All
                $AllDependencies | Measure-Object | ForEach-Object Count | Should be 4

                $RequiredModules = $AllDependencies | Where-Object { $_.Type -eq 'Module' }
                $RequiredModules | Measure-Object | ForEach-Object Count | Should be 1
                $RequiredModules.Name | Should be 'ModuleA'

                $RequiredVariables = $AllDependencies | Where-Object { $_.Type -eq 'AutomationVariable' }
                $RequiredVariables | Measure-Object | ForEach-Object Count | Should be 1
                $RequiredVariables.Name | Should be 'Variable1'
                
                $RequiredCredentials = $AllDependencies | Where-Object { $_.Type -eq 'AutomationCredential' }
                $RequiredCredentials | Measure-Object | ForEach-Object Count | Should be 1
                $RequiredCredentials.Name | Should be 'Credential1'

                $RequiredRunbooks = $AllDependencies | Where-Object { $_.Type -eq 'Runbook' }
                $RequiredRunbooks | Measure-Object | ForEach-Object Count | Should be 1
                $RequiredRunbooks.Name | Should be 'RunbookA'
            }
        }

        Context "When .graphrunbook file name is provided" {
            $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
            $Runbook.AddActivity((New-CommandActivity -ModuleName 'ModuleA'))

            $Runbook.AddActivity((New-CommandActivity -ValueDescriptors `
                (New-Object Orchestrator.GraphRunbook.Model.AutomationVariableValueDescriptor -ArgumentList 'Variable1'),
                (New-Object Orchestrator.GraphRunbook.Model.AutomationCredentialValueDescriptor -ArgumentList 'Credential1')))
            
            WithRunbookFile -Runbook $Runbook -Action {
                param($File)

                It "Outputs all dependencies" {
                    $AllDependencies = Get-GraphRunbookDependency -RunbookFileName $File.FullName -DependencyType All
                    $AllDependencies | Measure-Object | ForEach-Object Count | Should be 3

                    $RequiredModules = $AllDependencies | Where-Object { $_.Type -eq 'Module' }
                    $RequiredModules | Measure-Object | ForEach-Object Count | Should be 1
                    $RequiredModules.Name | Should be 'ModuleA'

                    $RequiredVariables = $AllDependencies | Where-Object { $_.Type -eq 'AutomationVariable' }
                    $RequiredVariables | Measure-Object | ForEach-Object Count | Should be 1
                    $RequiredVariables.Name | Should be 'Variable1'
                    
                    $RequiredCredentials = $AllDependencies | Where-Object { $_.Type -eq 'AutomationCredential' }
                    $RequiredCredentials | Measure-Object | ForEach-Object Count | Should be 1
                    $RequiredCredentials.Name | Should be 'Credential1'
                }
            }
        }

        Context "When runbook name is provided" {
            $TestResourceGroup = 'TestResourceGroupName'
            $TestAutomationAccount = 'TestAccountName'
            $TestRunbookName = 'TestRunbookName'

            Mock Export-AzureRMAutomationRunbook -Verifiable `
                -MockWith {
                    $ResourceGroupName | Should be $TestResourceGroup > $null
                    $AutomationAccountName | Should be $AutomationAccountName > $null
                    $Name | Should be $TestRunbookName > $null
                    $Slot | Should be 'Published' > $null

                    $Runbook = New-Object Orchestrator.GraphRunbook.Model.GraphRunbook
                    [void]$Runbook.AddActivity((New-CommandActivity -ModuleName 'ModuleA'))

                    [void]$Runbook.AddActivity((New-CommandActivity -ValueDescriptors `
                        (New-Object Orchestrator.GraphRunbook.Model.AutomationVariableValueDescriptor -ArgumentList 'Variable1'),
                        (New-Object Orchestrator.GraphRunbook.Model.AutomationCredentialValueDescriptor -ArgumentList 'Credential1')))
                    
                    $SerializedRunbook = [Orchestrator.GraphRunbook.Model.Serialization.RunbookSerializer]::Serialize($Runbook)
                    $OutputFileName = Join-Path $OutputFolder "$Name.graphrunbook"
                    $SerializedRunbook | Out-File $OutputFileName

                    Get-Item -Path $OutputFileName
                }

            It "Outputs all dependencies" {
                $AllDependencies = Get-GraphRunbookDependency `
                    -RunbookName $TestRunbookName `
                    -ResourceGroupName $TestResourceGroup `
                    -AutomationAccount $TestAutomationAccount `
                    -DependencyType All

                $AllDependencies | Measure-Object | ForEach-Object Count | Should be 3

                $RequiredModules = $AllDependencies | Where-Object { $_.Type -eq 'Module' }
                $RequiredModules | Measure-Object | ForEach-Object Count | Should be 1
                $RequiredModules.Name | Should be 'ModuleA'

                $RequiredVariables = $AllDependencies | Where-Object { $_.Type -eq 'AutomationVariable' }
                $RequiredVariables | Measure-Object | ForEach-Object Count | Should be 1
                $RequiredVariables.Name | Should be 'Variable1'
                
                $RequiredCredentials = $AllDependencies | Where-Object { $_.Type -eq 'AutomationCredential' }
                $RequiredCredentials | Measure-Object | ForEach-Object Count | Should be 1
                $RequiredCredentials.Name | Should be 'Credential1'

                Assert-VerifiableMocks
            }
        }
    }
}
