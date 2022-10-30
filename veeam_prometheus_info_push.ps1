# ----------------------------------------------------------------------------

$group = "CocaCola"

# ----------------------------------------------------------------------------

Function ConvertToUnixTime([DateTime] $ttt) {
    return $ttt | Get-Date -UFormat %s -Millisecond 0
}

# WHEN USING HTTPS THIS FORCES TLS 1.2 INSTAD OF POWERSHELL DEFAULT 1.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# GET AN ARRAY OF VEAAM JOBS
$VeeamJobs = Get-VBRJob | Sort-Object typetostring, name

# FOR EVERY JOB GATHER BASIC INFO
foreach ($Job in $VeeamJobs) {

$JobName = $Job.Name

# SUCCESS=0 WARNING=1 FAILED=2 RUNNING=-1
$LastJobResultCode = $Job.GetLastResult().value__

# POSSIBLE VALUES TO SEND IF PROMETHEUS WAS NOT LIMITED TO FLOATS METRICS
# ALTERNATIVE IS PUTTING IT AS LABEL, BUT THAT NEEDS SOME SANITATION
$JobDescription = $Job.Description
$JobType = $Job.JobType
$JobRepo = $Job.GetTargetRepository().FriendlyPath

$LastSession = $Job.FindLastSession()
$StartTimeLocalEpoch = ConvertToUnixTime($LastSession.progress.StartTimeLocal)
$StopTimeLocalEpoch = ConvertToUnixTime($LastSession.progress.StopTimeLocal)
$DurationInSeconds = $LastSession.progress.Duration.TotalSeconds
$TotalSize = $LastSession.Info.BackupTotalSize

# PROMETHEUS REQUIRES LINUX LINE ENDIG, SO \r\n IS REPLACED WITH \n
# ALSO POWERSHELL FEATURE "Here-Strings" IS USED @""@ DEFINES BLOCK OF TEXT
# THE EMPTY LINE IS REQUIRED
$body = @"
veeam_job_result $LastJobResultCode
veeam_job_start_time $StartTimeLocalEpoch
veeam_job_end_time $StopTimeLocalEpoch
veeam_job_duration $DurationInSeconds
veeam_job_totalsize $TotalSize

"@.Replace("`r`n","`n")

$body

# PUSH GATHERED DATA TO PROMETHEUS PUSHGATEWAY
# ONLY A UNIQUE URL CREATES A NEW UNIQUE ENTRY
Invoke-RestMethod `
    -Method PUT `
    -Uri "http://10.0.19.4:9091/metrics/job/veeam_report/instance/$JobName/group/$group" `
    -Body $body
}
