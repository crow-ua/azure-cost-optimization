### Set the date range

# $reportedStartTime = (Get-Date).AddMonths(-1).ToString('yyyy-MM-dd')
$reportedStartTime = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd')
$reportedEndTime = Get-Date -Format yyyy-MM-dd

### Set path to CSV file
$subscription = Get-AzContext
$subscriptionName = $subscription.Subscription.Name
$subscriptionId = $subscription.Subscription.Id
$filename = ".\usageData-${subscriptionName}-${reportedStartTime}-${reportedEndTime}.csv"

### Set usage parameters

$granularity = "Daily" # Can be Hourly or Daily
$showDetails = $true

### Export Usage to CSV

$appendFile = $false
$continuationToken = ""
$usageData = Get-UsageAggregates `
    -ReportedStartTime $reportedStartTime `
    -ReportedEndTime $reportedEndTime `
    -AggregationGranularity $granularity `
    -ShowDetails:$showDetails 

Do { 

    $usageData.UsageAggregations.Properties | 
        Select-Object `
            UsageStartTime, `
            UsageEndTime, `
            MeterCategory, `
            MeterId, `
            MeterName, `
            MeterSubCategory, `
            MeterRegion, `
            Unit, `
            Quantity, `
            @{n='Project';e={$_.InfoFields.Project}} | 
        Export-Csv `
            -Append:$appendFile `
            -NoTypeInformation:$true `
            -Path $filename

    if ($usageData.ContinuationToken) {

        $continuationToken = $usageData.ContinuationToken

        $usageData = Get-UsageAggregates `
            -ReportedStartTime $reportedStartTime `
            -ReportedEndTime $reportedEndTime `
            -AggregationGranularity $granularity `
            -ShowDetails:$showDetails `
            -ContinuationToken $continuationToken

    } else {

        $continuationToken = ""

    }

    $appendFile = $true

} until (!$continuationToken)