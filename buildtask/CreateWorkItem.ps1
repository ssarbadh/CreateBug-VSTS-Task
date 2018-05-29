#Requires -Version 5
<#
	.NOTES
		==============================================================================================
		Copyright(c) Aman Bedi. All rights reserved.
		
		File:		CreateWorkItem.ps1
		
		Purpose:	Create work item on release failure in VSTS.
		
		Version: 	1.0.0.2 - 28th May 2018 - Aman Bedi
		==============================================================================================	

	.SYNOPSIS
		Create a work item in VSTS
	
	.DESCRIPTION
		Dynamically creates a bug (work item) in current
		or custom defined area & iteration path for the
		team project in VSTS on release failure with 
		details like repro steps, errors, description,
		title, priority, severity & assigns it to the
		person who triggered the release.
		
		Deployment steps of the script are outlined below.
	
	.EXAMPLE
		Default:
		C:\PS> CreateWorkItem.ps1 `
#>

#region - Script

[CmdletBinding()]
param()

#region - Control Routine
Import-Module -Name $PSScriptRoot\ps_modules\VstsTaskSdk\VstsTaskSdk.psm1 -Verbose
Trace-VstsEnteringInvocation $MyInvocation
#endregion

try {

[string]$AuthToken = $env:SYSTEM_ACCESSTOKEN
if($AuthToken -eq $null -or $AuthToken -eq "")
{
	throw "The script cannot access Personal Access Token, Please enable `"Allow scripts to access OAuth token`" flag in in Agent Phase -> Additional options."
}

$Build = $env:BUILD_DEFINITIONNAME
$ReleaseName = $env:RELEASE_RELEASENAME
$Requestor = $env:RELEASE_REQUESTEDFOR
$EnvironmentName = $env:RELEASE_ENVIRONMENTNAME
[int] $ReleaseId = ( $env:RELEASE_RELEASEID -as [int])
[string]$ReleaseDefinition = $env:RELEASE_DEFINITIONNAME
$vstsAccount = $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
$vstsUri = $env:SYSTEM_TEAMFOUNDATIONSERVERURI
$teamProject = $env:SYSTEM_TEAMPROJECTID

$Authentication = [Text.Encoding]::ASCII.GetBytes(":$AuthToken")
$Authentication = [System.Convert]::ToBase64String($Authentication)

$Headers = @{
	Authorization   = ("Basic {0}" -f $Authentication)
}

$customPaths = Get-VstsInput -Name 'custompaths' -Require
if ($customPaths -eq $true) {
	Write-Host "Custom Paths provided."
	$AreaPath = Get-VstsInput -Name 'areapath' -Require
	$IterationPath = Get-VstsInput -Name 'iterationpath' -Require
	$currentIteration = $IterationPath
	Write-Host "Custom Area Path: $AreaPath"
	Write-Host "Custom Iteration Path: $IterationPath"
}
else {
	Write-Host "Getting default area and iteration paths for current team project."
	$iterationPropertiesUri = "$vstsAccount" + "DefaultCollection/" + $teamProject + "/_apis/work/TeamSettings/Iterations?$timeframe=current&api-version=4.1"
	Write-Host "Invoking Rest Endpoint for getting default current iteration path: $iterationPropertiesUri"
	
	$Parameters = @{
		Uri			    = $iterationPropertiesUri
		Method		    = 'Get'
		Headers		    = $Headers
	}
	$iterations = Invoke-RestMethod @Parameters
	$cIteration = $iterations.value | Where-Object { $PSItem.attributes.timeFrame -eq 'current' }
	$currentIteration = $cIteration.path
	Write-Host "Default current iteration Path: $currentIteration"
	
	$areaPathUri = "$vstsAccount" + "DefaultCollection/" + $teamProject + "/_apis/work/TeamSettings/TeamFieldValues?api-version=4.1"
	Write-Host "Invoking Rest Endpoint for getting default area path: $areaPathUri"
	
	$Parameters = @{
		Uri			    = $areaPathUri
		Method		    = 'Get'
		Headers		    = $Headers
	}
	$areaPathProperty = Invoke-RestMethod @Parameters
	$currentAreaPath = $areaPathProperty.defaultvalue
	$AreaPath = $currentAreaPath
	Write-Host "Default area path: $AreaPath"
}

$uri = "$vstsUri$teamProject/_apis/Release/releases/$($ReleaseId)?api-version=3.0-preview.1"
Write-Host "Invoking Rest Endpoint to get current release details: $uri"

$Parameters = @{
	Uri			    = $uri
	Method		    = 'Get'
	Headers		    = $Headers
}
$result = Invoke-RestMethod @Parameters

$script:errorText = "<font color = ""red""><b>The release failed due to following errors: </b></font><br/><br/>"
$environments = $result.environments
Write-Host "Getting Environment details"
#Write-Output $environments
$failedEnvironments = $environments | Where-Object { $PSItem.status -eq "rejected" -or $PSItem.status -eq "inProgress" }
#Write-Output $failedEnvironments

if ($failedEnvironments -ne $null)
{
	Write-Host "Getting details for the environments where the release failed."
	foreach ($environment in $failedEnvironments)
	{
		#Write-Output $environment
		$script:errorText += "<font color = ""red""><b>Errors in environment $($environment.name) : </b></font><br/><br/>"
		Write-Host "Getting failed phases for current environment: $($environment.name)"
		
		$deploymentPhases = $environment.deploySteps.releasedeployphases
		#Write-Output $deploymentPhases
		foreach ($phase in $deploymentPhases)
		{
			Write-Host "Getting details of the phase: $($phase.name)"
			#Write-Output $phase
			$issueTasks = $phase.deploymentJobs.Tasks | Where-Object { $PSItem.issues -ne $null }
			#Write-Output $issueTasks
			if ($issueTasks -ne $null)
			{
				Write-Host "Getting details of the tasks which failed in the current phase."			
				foreach ($Task in $issueTasks)
				{
					Write-Host "Getting error details of the failed task: $($Task.name)"							
					#Write-Output $Task
					$script:errorText += "<font color = ""red"">Errors in task $($Task.name) : </font><br/><br/>"
					$script:errorText += "<ul>"
					Write-Host "Following errors found."	
					
					foreach ($issue in $Task.issues)
					{
						Write-Host "Error message: $($issue.message)"																									
						#Write-Output $issue
						$script:errorText += "<li>"
						$script:errorText += "$($issue.message) <br/><br/>"
						$script:errorText += "</li>"
					}
					$script:errorText += "</ul>"
				}
			}
		}
	}
}

Write-Host "Consolidated error report:"
Write-Host $script:errorText

$RestParams = @{
	Uri		       = "$vstsAccount$teamProject/_apis/wit/workitems/`$Bug?api-version=2.2"
	ContentType    = 'application/json-patch+json'
	Headers	       = @{
		Authorization    = ("Basic {0}" -f $authentication)
	}
	Method		   = "Patch"
	Body		   = @(
		@{
			op	     = "add"
			path	 = "/fields/System.Title"
			value    = "Release $ReleaseName failed for release definition $ReleaseDefinition in the environment $EnvironmentName against the build $Build"
		}
		@{
			op	     = "add"
			path	 = "/fields/System.AreaPath"
			value    = "$AreaPath"
		}
		@{
			op	     = "add"
			path	 = "/fields/System.IterationPath"
			value    = "$currentIteration"
		}
		@{
			op	     = "add"
			path	 = "/fields/System.AssignedTo"
			value    = "$Requestor"
		}
		@{
			op	     = "add"
			path	 = "/fields/Microsoft.VSTS.Common.Priority"
			value    = 2
		}
		@{
			op	     = "add"
			path	 = "/fields/Microsoft.VSTS.Common.Severity"
			value    = "2 - High"
		}
		@{
			op	     = "add"
			path	 = "/fields/Microsoft.VSTS.TCM.ReproSteps"
			value    = $script:errorText
		}
	) | ConvertTo-Json
}
Write-Host "Creating a bug with the generated error report under the configured area & iteration path with default severity & priority, populated with release details in title & assigned to the person who triggered the release."
#$RestParams.Body

try
{
	Invoke-RestMethod @RestParams -Verbose
}
catch
{
	$PSItem.Exception.Message
}

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}
#endregion