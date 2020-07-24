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

# Replace the following configuration settings
# $tenantId = ""
# $clientId = ""
# $clientPassword = ""
$subscriptionId = $currentAzureContext.Subscription.Id

# Rate Card Settings
$offerDurableId = "MS-AZR-0063P"
$currency = "EUR"
$locale = "en-US"
$regionInfo = "PL"

# Usage Settings
$startTime = (Get-Date).AddMonths(-1).ToString('yyyy-MM-dd')
$endTime = Get-Date -Format yyyy-MM-dd
$outFile = ".\billingReport-${subscriptionId}-${startTime}-${endTime}.csv"


# *** Login ****

# $loginUri = "https://login.microsoftonline.com/$tenantId/oauth2/token?api-version=1.0"

# $body = @{
#     grant_type = "client_credentials"
#     resource = "https://management.core.windows.net/"
#     client_id = $clientId
#     client_secret = $clientPassword
# }

# Write-Host "Authenticating" 

# $loginResponse = Invoke-RestMethod $loginUri -Method Post -Body $body
# $authorization = $loginResponse.token_type + ' ' + $loginResponse.access_token

# # Use the same header in all the calls, so save authorization in a header dictionary

# $headers = @{
#     authorization = $authorization
# }

# *** Rate Card ***

$rateCardFilter = "OfferDurableId eq '$offerDurableId' and Currency eq '$currency' and Locale eq '$locale' and RegionInfo eq '$regionInfo'"
$rateCardUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Commerce/RateCard?api-version=2016-08-31-preview&`$filter=$rateCardFilter"

Write-Host "Querying Rate Card API"

$rateCardResponse = Invoke-RestMethod $rateCardUri -Headers $headers -ContentType "application/json"

$rateCard = @{}

foreach ($meter in $rateCardResponse.Meters)
{
    # Note, the following if statement can be written more compact, but due to readability, I've kept it this way

    if ($rateCard[$meter.MeterId])
    {
        # A previous price was found

        if ($meter.EffectiveDate -gt $rateCard[$meter.MeterId].EffectiveDate)
        {
            # Found updated price for $meter.MeterId

            $rateCard[$meter.MeterId] = $meter
        }
    }
    else
    {
        # First time a price was found for $meter.MeterId

        $rateCard[$meter.MeterId] = $meter
    }
}


# *** Usage ***

$usageUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Commerce/UsageAggregates?api-version=2015-06-01-preview&reportedStartTime=$startTime&reportedEndTime=$endTime&aggregationGranularity=Daily&showDetails=false"
$usageRows = New-Object System.Collections.ArrayList

Write-Host "Querying Azure Usage API"

do {
    Write-Host "."

    $usageResult = Invoke-RestMethod $usageUri -Headers $headers -ContentType "application/json"

    foreach ($usageRow in $usageResult.value) {
        $usageRows.Add($usageRow) > $null
    }

    $usageUri = $usageResult.nextLink

    # If there's a continuation, then call API again
} while ($usageUri)

Write-Host "Organizing Data"

foreach ($item in $usageRows) {
    # Fix "bug" in Usage API that return instanceData as a string instead of as JSON
    if ($item.properties.instanceData) {
        $item.properties.instanceData = ConvertFrom-Json $item.properties.instanceData
    }
}

$data = $usageRows | Select-Object -ExpandProperty properties

foreach ($item in $data) {
    # Fix members to make them easier to consume

    $usageStartDate = (Get-Date $item.usageStartTime).ToShortDateString()
    $usageEndDate = (Get-Date $item.usageEndTime).ToShortDateString()

    $item | Add-Member "usageStartDate" $usageStartDate
    $item | Add-Member "usageEndDate" $usageEndDate

    $item | Add-Member "location" $item.instanceData.'Microsoft.Resources'.location
    $item | Add-Member "resourceUri" $item.instanceData.'Microsoft.Resources'.resourceUri
    $item | Add-Member "additionalInfo" $item.instanceData.'Microsoft.Resources'.additionalInfo
    $item | Add-Member "tags" $item.instanceData.'Microsoft.Resources'.tags

    $item.resourceUri -match "(?<=resourceGroups\/)(?<resourceGroup>.*)(?=\/providers)" | Out-Null
    $item | Add-Member "resourceGroup" $Matches.resourceGroup

    # Lookup pricing

    $meterRate0 = $rateCard[$item.meterId].MeterRates.0
    $total = $item.quantity * $MeterRate0

    $item | Add-Member "meterRate0" $meterRate0 # Use the first MeterRate and ignored tiered pricing for this calculation
    $item | Add-Member "total" $total
    $item | Add-Member "currency" $currency
}

# *** Fine tune result and only keep interesting information ***

$reportResult = $data | Select-Object usageStartDate, usageEndDate, location, meterName, meterCategory, meterSubCategory, quantity, unit, meterRate0, total, currency, resourceGroup, meterId, resourceUri, additionalInfo, tags

# *** Export to File ***

Write-Host "Exporting to $outFile"

$reportResult | Export-Csv $outFile -UseCulture -NoTypeInformation