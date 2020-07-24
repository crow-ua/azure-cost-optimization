# Ja mam taki skrypt zrobiony na szybko co z EA billing API wyciaga wszystkie billingi i wrzuca kazdy billing period jako oddzielna CSVke. Wszystko in parallel na X watkach. Wpisujesz na poczatku w parametrze umowy i klucze z EA i smiga na X umow.
# Potem power BI wsysa wszystko ladnie 🙂
# Dziele sie skryptem tu https://pastebin.com/hA2vs6c4
# Za jakis czas planowalem wrzucic gotowca na bloga jako functions code.

# https://docs.microsoft.com/en-us/rest/api/billing/enterprise/billing-enterprise-api-billing-periods


Get-Job | Stop-Job

$agreements = `
    @{"id"="";"apiKey"=""}, `
    @{"id"="";"apiKey"=""}, `
    @{"id"="";"apiKey"=""}
$periods = @()
$folder = "C:\temp"

foreach ($ea in $agreements) {
    $eaId = $ea.id
    $eaKey = $ea.apiKey
    $headers = @{"Authorization"="Bearer $eaKey"}
    Write-Host "Checking EA#$eaId"
    Write-Host "Using key $eaKey" -ForegroundColor Gray

    Write-Host "Fetching billing periods..."
    $eaPeriodsUrl = "https://consumption.azure.com/v2/enrollments/$eaId/billingperiods"
    Write-Host "Fetching from $eaPeriodsUrl" -ForegroundColor Gray
    $eaPeriods = Invoke-RestMethod $eaPeriodsUrl -Headers $headers
    foreach ($eaPeriod in $eaPeriods) {
        $periods += @{ 
            "billingPeriodId"=$eaPeriod.billingPeriodId;
            "usageDetails"=$eaPeriod.usageDetails;
            "eaId"=$eaId;
            "headers"=$headers
        }
    }

    Write-Host "Obtained $($eaPeriods.Count) periods"
}

$usagePeriods = $periods | Where-Object { $_.usageDetails -ne "" } 

$i = 0

foreach ($usagePeriod in $usagePeriods) {
    $ScriptBlock = {
        param($eaPeriod) 
        $data = @()
        $eaPeriodId = $eaPeriod.billingPeriodId
        $eaId = $eaPeriod.eaId
    
        $eaPeriodsIdUrl = "https://consumption.azure.com/$($eaPeriod.usageDetails)" 
        Write-Host "Fetching from $eaPeriodsIdUrl" -ForegroundColor Gray
    
        do {
            $eaPeriodIdUsage = Invoke-RestMethod $eaPeriodsIdUrl -Headers $eaPeriod.headers
            $eaPeriodsIdUrl = $eaPeriodIdUsage.nextLink
    
            $data += $eaPeriodIdUsage.data
            Write-Host "EA $eaId for $eaPeriodId $($eaPeriodIdUsage.data.Count) with total $($data.Length) rows."
        } until ($eaPeriodsIdUrl -eq $null)
    
        $fileName = "$eaId-$eaPeriodId.csv"
        Write-Host "Exporting $fileName with $($data.Count) rows." -ForegroundColor DarkCyan
        $data | Export-CSV -Path "$folder\$fileName" -NoTypeInformation
    }

    Start-Job $ScriptBlock -ArgumentList $usagePeriod
}

While (Get-Job -State "Running")
{
  Start-Sleep 5
  Get-Job | Receive-Job
}

# Getting the information back from the jobs
Get-Job | Receive-Job