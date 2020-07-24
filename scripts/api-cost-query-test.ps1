#Requires -PSEdition Core
#Requires -Modules Az
#Requires -Modules PSWriteHTML

# https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.Commerce/UsageAggregates?api-version=2015-06-01-preview&reportedstartTime={startDateStr}&reportedEndTime={endDateStr}


$azureSub = "Visual Studio Enterprise"

function Get-BearerToken {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $tenantId
    )
    $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile)
    $token = $profileClient.AcquireAccessToken($tenantId).AccessToken

    $bearerToken = "Bearer $token"

    return $bearerToken
}

$currentAzureContext = Get-AzContext
if ($currentAzureContext.Account -eq $null) {
    Connect-AzAccount -Subscription $azureSub
}
if ($currentAzureContext.Subscription.Name -ne $azureSub) {
    Select-AzSubscription -Subscription $azureSub
}

$tenantId = $currentAzureContext.Subscription.TenantId

$token = Get-BearerToken -tenantId $tenantId

$subscriptionId = $currentAzureContext.Subscription.Id
$startDateStr = "2020-07-01"
$endDateStr = "2020-07-24"

$apiBaseUrl = $currentAzureContext.Environment.ResourceManagerUrl
$apiUrl = "${apiBaseUrl}subscriptions/${subscriptionId}/providers/Microsoft.Commerce/UsageAggregates?api-version=2015-06-01-preview&reportedstartTime=${startDateStr}&reportedEndTime=${endDateStr}"

$headers = @{
    Authorization = $token
}

$results = Invoke-RestMethod -Uri $apiUrl -Method Get -ContentType "application/json" -Headers $headers

$results.value.properties| Select-Object subscriptionId,usageStartTime,usageEndTime,meterName,meterRegion,meterCategory,unit,quantity | Out-HtmlView