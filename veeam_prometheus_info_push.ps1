# v0.1  ----------------------------------------------------------------------
# ----------------------------------------------------------------------------

$group = "CocaCola"
$base_url = "http://10.0.19.4:9091"
# $base_url = "https://push.example.com"

# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------

Function ConvertToUnixTime([AllowNull()][Nullable[DateTime]] $ttt) {
    if (!$ttt) { return 0 }
    return $ttt | Get-Date -UFormat %s -Millisecond 0
}

# WHEN USING HTTPS THIS FORCES TLS 1.2 INSTAD OF POWERSHELL DEFAULT 1.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ----------------------------------------------------------------------------
# ----------------------------------------------------------------------------

# GET AN ARRAY OF VEAAM JOBS
$VeeamJobs = Get-VBRJob | Sort-Object typetostring, name

# FOR EVERY JOB GATHER BASIC INFO
foreach ($Job in $VeeamJobs) {

$JobName = $Job.Name
$JobType = $Job.JobType

# SUCCESS=0 | WARNING=1 | FAILED=2 | RUNNING=-1 | +DISABLED OR NOT SCHEDULED=-2
$LastJobResultCode = $Job.GetLastResult().value__

# IF THE JOB IS NOT SCHEDULED OR DISABLED, SET LastJobResultCode TO -2
# Options.JobOptions.RunManually -
#   - TRUE IF THE JOB HAS UNCHECKED CHECKBOX - Run the job automaticly
# IsScheduleEnabled - FALSE IF THE JOB IS SET AS SET TO DISABLED
if ($Job.Options.JobOptions.RunManually) { $LastJobResultCode = -2}
if (!$Job.IsScheduleEnabled) { $LastJobResultCode = -2}

$LastSession = $Job.FindLastSession()
$StartTimeLocalEpoch = ConvertToUnixTime($LastSession.progress.StartTimeLocal)
$StopTimeLocalEpoch = ConvertToUnixTime($LastSession.progress.StopTimeLocal)

if ($LastSession.progress.Duration.TotalSeconds) {
    $DurationInSeconds = $LastSession.progress.Duration.TotalSeconds
} else {
    $DurationInSeconds = 0
}

if ($LastSession.Info.BackupTotalSize) {
    $TotalSize = $LastSession.Info.BackupTotalSize
} else {
    $TotalSize = 0
}

# PROMETHEUS REQUIRES LINUX LINE ENDIG, SO \r\n IS REPLACED WITH \n
# ALSO POWERSHELL FEATURE "Here-Strings" IS USED, @""@ DEFINES BLOCK OF TEXT
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
    -Uri "$base_url/metrics/job/veeam_report/instance/$JobName/group/$group/job_type/$JobType" `
    -Body $body
}
