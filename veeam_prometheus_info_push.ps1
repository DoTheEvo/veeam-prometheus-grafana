# ----------------------------------------------------------------------------

$group = "CocaCola"

# ----------------------------------------------------------------------------

Function ConvertToUnixTime([DateTime] $ttt) {
    return $ttt | Get-Date -UFormat %s -Millisecond 0
}

# GET AN ARRAY OF VEAAM JOBS
$VeeamJobs = Get-VBRJob | Sort-Object typetostring, name

# FOR EVERY JOB GATHER BASIC INFO
foreach ($Job in $VeeamJobs) {

$JobName = $Job.Name

# SUCCESS=0 WARNING=1 FAILED=2 RUNNING=-1
$LastJobResultCode = $Job.GetLastResult().value__

$JobDescription = $Job.Description
$JobType = $Job.JobType
$JobRepo = $Job.GetTargetRepository().FriendlyPath

$LastSession = $Job.FindLastSession()
$StartTimeLocalEpoch = ConvertToUnixTime($LastSession.progress.StartTimeLocal)
$StopTimeLocalEpoch = ConvertToUnixTime($LastSession.progress.StopTimeLocal)
$DurationInSeconds = $LastSession.progress.Duration.TotalSeconds


# PROMETHEUS REQUIRES LINUX LINE ENDIG, SO \r\n IS REPLACED WITH \n
# ALSO POWERSHELL FEATURE "Here-Strings" IS USED @""@ DEFINES BLOCK OF TEXT
# THE EMPTY LINE IS REQUIRED
$body = @"
veeam_job_result $LastJobResultCode
veeam_job_description $JobDescription
veeam_job_type $JobType
veeam_job_target_repo $JobRepo
veeam_job_start_time $StartTimeLocalEpoch
veeam_job_end_time $StopTimeLocalEpoch
veeam_job_duration $DurationInSeconds

"@.Replace("`r`n","`n")

$body

# PUSH GATHERED DATA TO PROMETHEUS PUSHGATEWAY
# ONLY A UNIQUE URL CREATES A NEW UNIQUE ENTRY
Invoke-RestMethod `
    -Method PUT `
    -Uri "http://10.0.19.4:9091/metrics/job/veeam_report/instance/$JobName/group/$group" `
    -Body $body
}
