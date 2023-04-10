# v0.2  ----------------------------------------------------------------------
# ----------------------  CUSTOM CONFIG  -------------------------------------

$group = "CocaCola"
$base_url = "https://push.example.com"
# $base_url = "http://10.0.19.4:9091"

# ----------------------------------------------------------------------------
# ----------------------  GENERIC USEFUL STUFF  ------------------------------

Function ConvertToUnixTime([AllowNull()][Nullable[DateTime]] $ttt) {
    if (!$ttt) { return 0 }
    return $ttt | Get-Date -UFormat %s -Millisecond 0
}

# WHEN USING HTTPS THIS FORCES TLS 1.2 INSTEAD OF POWERSHELL DEFAULT 1.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ----------------------------------------------------------------------------
# ----------------------  REPOSITORY INFO  -----------------------------------

$Repos = Get-VBRBackupRepository
foreach ($Repo in $Repos) {

  $RepoName  = $Repo.Name
  $TotalSize = $Repo.GetContainer().CachedTotalSpace.InBytes
  $FreeSpace = $Repo.GetContainer().CachedFreeSpace.InBytes

# PROMETHEUS REQUIRES LINUX LINE ENDINGS, SO \r\n IS REPLACED WITH \n
# ALSO POWERSHELL FEATURE "Here-Strings" IS USED, @""@ DEFINES BLOCK OF TEXT
# THE EMPTY LINE IS REQUIRED
$body = @"
veeam_repo_total_size_bytes $TotalSize
veeam_repo_free_space_bytes $FreeSpace

"@.Replace("`r`n","`n")

$body

# PUSH GATHERED DATA TO PROMETHEUS PUSHGATEWAY
Invoke-RestMethod `
    -Method PUT `
    -Uri "$base_url/metrics/job/veeam_report_repo/instance/`
          $RepoName/server/$env:COMPUTERNAME/group/$group" `
    -Body $body
}

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
# JobOptions.RunManually -
#   TRUE IF THE JOB HAS UNCHECKED CHECKBOX - Run the job automatically
# IsScheduleEnabled -
#   FALSE IF THE JOB IS SET TO DISABLED
if ($Job.Options.JobOptions.RunManually) { $LastJobResultCode = -2}
if (!$Job.IsScheduleEnabled) { $LastJobResultCode = -2}

$LastSession = $Job.FindLastSession()
$StartTimeLocalEpoch = ConvertToUnixTime($LastSession.progress.StartTimeLocal)
$StopTimeLocalEpoch = ConvertToUnixTime($LastSession.progress.StopTimeLocal)

$DurationInSeconds = 0
if ($LastSession.progress.Duration.TotalSeconds) {
    $DurationInSeconds = $LastSession.progress.Duration.TotalSeconds
}

$TotalSize = 0
if ($LastSession.Info.BackupTotalSize) {
    $TotalSize = $LastSession.Info.BackupTotalSize
}

# PROMETHEUS REQUIRES LINUX LINE ENDINGS, SO \r\n IS REPLACED WITH \n
# ALSO POWERSHELL FEATURE "Here-Strings" IS USED, @""@ DEFINES BLOCK OF TEXT
# THE EMPTY LINE IS REQUIRED
$body = @"
veeam_job_result_info $LastJobResultCode
veeam_job_start_time_seconds $StartTimeLocalEpoch
veeam_job_end_time_seconds $StopTimeLocalEpoch
veeam_job_duration_seconds $DurationInSeconds
veeam_job_totalsize_bytes $TotalSize

"@.Replace("`r`n","`n")

$body

# PUSH GATHERED DATA TO PROMETHEUS PUSHGATEWAY
Invoke-RestMethod `
    -Method PUT `
    -Uri "$base_url/metrics/job/veeam_report/instance/$JobName/group/`
          $group/job_type/$JobType" `
    -Body $body
}
