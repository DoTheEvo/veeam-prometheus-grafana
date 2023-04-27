# v0.3  ----------------------------------------------------------------------
# ----------------------  CUSTOM CONFIG  -------------------------------------

$GROUP = "CocaCola"
$BASE_URL = "https://push.example.com"
# $base_url = "http://10.0.19.4:9091"

# ----------------------------------------------------------------------------
# ----------------------  GENERIC USEFUL STUFF  ------------------------------

# WHEN USING HTTPS THIS FORCES TLS 1.2 INSTEAD OF POWERSHELL DEFAULT 1.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


Function ConvertToUnixTime([AllowNull()][Nullable[DateTime]] $ttt) {
    if (!$ttt) { return 0 }
    return $ttt | Get-Date -UFormat %s -Millisecond 0
}


Function PushDataToPrometheus([Object] $d) {

# PROMETHEUS REQUIRES LINUX LINE ENDINGS, SO \r\n IS REPLACED WITH \n
# ALSO POWERSHELL FEATURE "Here-Strings" IS USED, @""@ DEFINES BLOCK OF TEXT
# THE EMPTY LINE IS REQUIRED
$body = @"
veeam_job_result_info $($d.result)
veeam_job_start_time_timestamp_seconds $($d.start_time)
veeam_job_end_time_timestamp_seconds $($d.end_time)
veeam_job_data_size_bytes $($d.data_size)
veeam_job_backup_size_bytes $($d.backup_size)

"@.Replace("`r`n","`n")

# PUSH GATHERED DATA TO PROMETHEUS PUSHGATEWAY
Invoke-RestMethod `
    -Method PUT `
    -Uri "$($d.url)/metrics/job/veeam_report/instance/$($d.name)/group/`
          $($d.group)/job_type/$($d.type)" `
    -Body $body
}


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
# ----------------  JOBS INFO EXCEPT AGENT BASED BACKUPS  --------------------

# GET AN ARRAY OF VEAAM JOBS, SORTED BY TYPE and NAME,
# EXCLUDE AGENT BASED BACKUPS AS IN FUTURE VEEAM VERSIONS Get-VBRJob
# WILL NOT RETURN THEM
$VeeamJobs = @(Get-VBRJob | Sort-Object typetostring, name | `
  ? {$_.BackupPlatform.Platform -ne 'ELinuxPhysical' `
  -and $_.BackupPlatform.Platform -ne 'EEndPoint'})

# FOR EVERY JOB GATHER BASIC INFO
foreach ($Job in $VeeamJobs) {

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


}

# ----------------------------------------------------------------------------
# ----------------  AGENT BASED JOBS  ----------------------------------------

# HASHTABLE THAT EASES TRANSLATION OF RESULTS FROM A WORD TO A NUMBER
# 'NONE' RESULT APPEARS WHEN THE JOB IS RUNNING
$ResultsTable = @{"Success"=0;"Warning"=1;"Failed"=2;"None"=-1}

$AgentJobs = Get-VBRComputerBackupJob
# $AgentJobs = ($AgentJobsAndPolicies | ? {$_.Mode -eq 'ManagedByBackupServer' })
# $AgentPolicies = ($AgentJobsAndPolicies | ? {$_.Mode -eq 'ManagedByAgent' })

foreach ($Job in $AgentJobs)
{

# --------------  GET JOB NAME  ------------------------------------------

$JOB_NAME = $Job.Name

# --------------  GET JOB TYPE  ------------------------------------------

# CREATE A VARIABLE IDENTIFYING IF THE JOB IS A POLICY OR NOT
$IsPolicy = $False
if ($Job.Mode -eq 'ManagedByAgent') { $IsPolicy = $True }

if ($IsPolicy -eq $True ) {
    $JOB_TYPE = 'EpAgentPolicy'
} else {
    $JOB_TYPE = 'EpAgentBackup'
}

# --------------  GET JOB LAST SESSION RESULT-----------------------------

# NOT ALL POLICY SESSIONS ARE BACKUPS, LOT OF CONFIG UPDATES THERE
# TO FILTER IT TO JUST ACTUAL BACKUPS THE NAME HAS WILDCARD ADDED
# https://forums.veeam.com/post434804.html

$JobNameForQuery = $Job.Name
if ($IsPolicy -eq $True ) { $JobNameForQuery = '{0}?*' -f $Job.Name }

$Sessions = Get-VBRComputerBackupJobSession -Name $JobNameForQuery
$LastSession = $Sessions[0]

$LAST_SESSION_RESULT_CODE = $ResultsTable[$LastSession.Result.ToString()]

if (-NOT $Job.ScheduleEnabled) { $LAST_SESSION_RESULT_CODE = -2}
if (-NOT $Job.JobEnabled) { $LAST_SESSION_RESULT_CODE = -2}

# --------------  GET JOB START AND STOP TIME ----------------------------

$START_TIME_UTC_EPOCH = ConvertToUnixTime($LastSession.CreationTime)
$STOP_TIME_UTC_EPOC = ConvertToUnixTime($LastSession.EndTime)


# TO VISUALIZE JOB RUN IN GRAPH
# LAST_SESSION_RESULT_CODE IS CHANGED IF IT RUN IN LAST HOUR
$SecondsAgo = (ConvertToUnixTime(Get-Date)) - $START_TIME_UTC_EPOCH
if ($SecondsAgo -le 3600) { $LAST_SESSION_RESULT_CODE = -1 }

# --------------  GET JOB DATA AND BACKUP SZE ----------------------------

$AgentBackup = Get-VBRBackup -Name $Job.Name
$RestorePoints = Get-VBRRestorePoint -Backup $AgentBackup
$BACKUP_SIZE = 0
$DATA_SIZE = 0
$result = foreach ($r in $RestorePoints) {
    $Storage = $r.FindStorage()
    $BACKUP_SIZE += $Storage.Stats.BackupSize
    $DATA_SIZE += $Storage.Stats.DataSize
}

# --------------  SEND DATA TO PUSHGATEWAY  ------------------------------

# CREATE A CUSTOM OBJECT FROM GATHERED DATA
$JOBS_DATA = [PSCustomObject]@{
    name = $JOB_NAME
    group = $GROUP
    type = $JOB_TYPE
    result = $LAST_SESSION_RESULT_CODE
    start_time = $START_TIME_UTC_EPOCH
    end_time = $STOP_TIME_UTC_EPOC
    data_size = $DATA_SIZE
    backup_size = $BACKUP_SIZE
    url = $BASE_URL
}

$JOBS_DATA
PushDataToPrometheus $JOBS_DATA
"--------------------------------"

}
