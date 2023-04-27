# v0.3  ----------------------------------------------------------------------
# ----------------------  CUSTOM CONFIG  -------------------------------------

$GROUP = "CocaCola"
$BASE_URL = "https://push.example.com"
# $base_url = "http://10.0.19.4:9091"

# ----------------------------------------------------------------------------
# ----------------------  GENERIC USEFUL STUFF  ------------------------------
# ----------------------------------------------------------------------------

# WHEN USING HTTPS THIS FORCES TLS 1.2 INSTEAD OF POWERSHELL DEFAULT 1.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# USING EPOCH TIME, SECONDS SINCE 1.1.1970, UTC
Function ConvertToUnixTime([AllowNull()][Nullable[DateTime]] $ttt) {
    if (!$ttt) { return 0 }
    return $ttt | Get-Date -UFormat %s -Millisecond 0
}

# ----------------------------------------------------------------------------
# -----------------  PUSH TO PROMETHEUS PUSHGATEWAY  -------------------------
# ----------------------------------------------------------------------------

Function PushDataToPrometheus([Object] $d)
{

# -----------------  PUSH OF BACKUP JOBS REPORT ------------------------------

if ($d.report_type -eq 'veeam_job_report')
{
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

# SEND GATHERED DATA TO PROMETHEUS PUSHGATEWAY
Invoke-RestMethod `
    -Method PUT `
    -Uri "$($d.url)/metrics/job/$($d.report_type)/instance/$($d.name)/group/`
          $($d.group)/job_type/$($d.type)" `
    -Body $body
}

# -----------------  PUSH OF REPO REPORT  ------------------------------------

if ($d.push_type -eq 'veeam_repo_report')
{

# PROMETHEUS REQUIRES LINUX LINE ENDINGS, SO \r\n IS REPLACED WITH \n
# ALSO POWERSHELL FEATURE "Here-Strings" IS USED, @""@ DEFINES BLOCK OF TEXT
# THE EMPTY LINE IS REQUIRED
$body = @"
veeam_repo_total_size_bytes $($d.size)
veeam_repo_free_space_bytes $($d.free)

"@.Replace("`r`n","`n")

# SEND GATHERED DATA TO PROMETHEUS PUSHGATEWAY
Invoke-RestMethod `
    -Method PUT `
    -Uri "$($d.url)/metrics/job/$($d.report_type)/instance/$($d.name)/group/`
          $($d.group)/server/$($d.server)" `
    -Body $body
}

}

# ----------------------------------------------------------------------------
# ----------------------  REPOSITORY INFO  -----------------------------------
# ----------------------------------------------------------------------------

$Repos = Get-VBRBackupRepository
foreach ($Repo in $Repos)
{

$REPO_NAME  = $Repo.Name
$TOTAL_SIZE = $Repo.GetContainer().CachedTotalSpace.InBytes
$FREE_SPACE = $Repo.GetContainer().CachedFreeSpace.InBytes

# --------------  SEND REPO DATA TO PUSHGATEWAY  -----------------------------

# CREATE A CUSTOM OBJECT FROM GATHERED DATA
$REPO_DATA = [PSCustomObject]@{
    push_type = 'repo_push'
    name = $REPO_NAME
    server = $env:COMPUTERNAME
    group = $GROUP
    size = $TOTAL_SIZE
    free = $FREE_SPACE
    url = $BASE_URL
}

$REPO_DATA
PushDataToPrometheus $REPO_DATA
"------------------------------"

}

# ----------------------------------------------------------------------------
# ----------------  JOBS INFO EXCEPT AGENT BASED BACKUPS  --------------------
# ----------------------------------------------------------------------------

# GET AN ARRAY OF VEAAM JOBS, SORTED BY TYPE and NAME,
# EXCLUDE AGENT BASED BACKUPS AS IN FUTURE VEEAM VERSIONS Get-VBRJob
# WILL NOT RETURN THEM
$VeeamJobs = @(Get-VBRJob | Sort-Object typetostring, name | `
  ? {$_.BackupPlatform.Platform -ne 'ELinuxPhysical' `
  -and $_.BackupPlatform.Platform -ne 'EEndPoint'})

# FOR EVERY JOB GATHER BASIC INFO
foreach ($Job in $VeeamJobs)
{

# --------------  GET JOB NAME  -------------------------------------

$JOB_NAME = $Job.Name

# --------------  GET JOB TYPE  -------------------------------------

$JOB_TYPE = $Job.JobType

# --------------  GET JOB LAST SESSION RESULT------------------------

# SUCCESS=0 | WARNING=1 | FAILED=2 | RUNNING=-1 | +DISABLED OR NOT SCHEDULED=-2
$LAST_SESSION_RESULT_CODE = $Job.GetLastResult().value__

# IF THE JOB IS NOT SCHEDULED OR DISABLED, SET LAST_SESSION_RESULT_CODE TO -2
# JobOptions.RunManually -
#   TRUE IF THE JOB HAS UNCHECKED CHECKBOX - Run the job automatically
# IsScheduleEnabled -
#   FALSE IF THE JOB IS SET TO DISABLED
if ($Job.Options.JobOptions.RunManually) { $LAST_SESSION_RESULT_CODE = -2}
if (!$Job.IsScheduleEnabled) { $LAST_SESSION_RESULT_CODE = -2}

# --------------  GET JOB START AND STOP TIME -----------------------

$LastSession = $Job.FindLastSession()
$START_TIME_UTC_EPOCH = ConvertToUnixTime($LastSession.progress.StartTimeLocal)
$STOP_TIME_UTC_EPOC = ConvertToUnixTime($LastSession.progress.StopTimeLocal)

# TO VISUALIZE JOB RUN IN GRAPH
# LAST_SESSION_RESULT_CODE IS CHANGED IF JOB RUN IN LAST HOUR
$SecondsAgo = (ConvertToUnixTime(Get-Date)) - $STOP_TIME_UTC_EPOC
if ($SecondsAgo -le 3600) { $LAST_SESSION_RESULT_CODE = -1 }

# --------------  GET JOB DATA AND BACKUP SZE -----------------------

$DATA_SIZE = $LastSession.BackupStats.DataSize
$BACKUP_SIZE = $LastSession.Info.BackupTotalSize

# --------------  SEND DATA TO PUSHGATEWAY  -------------------------

# CREATE A CUSTOM OBJECT FROM GATHERED DATA
$JOBS_DATA = [PSCustomObject]@{
    report_type = 'veeam_job_report'
    name = $JOB_NAME
    type = $JOB_TYPE
    result = $LAST_SESSION_RESULT_CODE
    group = $GROUP
    start_time = $START_TIME_UTC_EPOCH
    end_time = $STOP_TIME_UTC_EPOC
    data_size = $DATA_SIZE
    backup_size = $BACKUP_SIZE
    url = $BASE_URL
}

$JOBS_DATA
PushDataToPrometheus $JOBS_DATA
"------------------------------"

}

# ----------------------------------------------------------------------------
# --------------------  AGENT BASED JOBS  ------------------------------------
# ----------------------------------------------------------------------------

# HASHTABLE THAT EASES TRANSLATION OF RESULTS FROM A WORD TO A NUMBER
# 'NONE' RESULT APPEARS WHEN THE JOB IS RUNNING
$ResultsTable = @{"Success"=0;"Warning"=1;"Failed"=2;"None"=-1}

$AgentJobs = Get-VBRComputerBackupJob

# FOR EVERY AGENT JOB GATHER BASIC INFO
foreach ($Job in $AgentJobs)
{

# --------------  GET JOB NAME  -------------------------------------

$JOB_NAME = $Job.Name

# --------------  GET JOB TYPE  -------------------------------------

# CREATE A VARIABLE IDENTIFYING IF THE JOB IS A POLICY OR NOT
$IsPolicy = $False
if ($Job.Mode -eq 'ManagedByAgent') { $IsPolicy = $True }

if ($IsPolicy -eq $True ) {
    $JOB_TYPE = 'EpAgentPolicy'
} else {
    $JOB_TYPE = 'EpAgentBackup'
}

# --------------  GET JOB LAST SESSION RESULT------------------------

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

# --------------  GET JOB START AND STOP TIME -----------------------

$START_TIME_UTC_EPOCH = ConvertToUnixTime($LastSession.CreationTime)
$STOP_TIME_UTC_EPOC = ConvertToUnixTime($LastSession.EndTime)

# TO VISUALIZE JOB RUN IN GRAPH
# LAST_SESSION_RESULT_CODE IS CHANGED IF JOB RUN IN LAST HOUR
$SecondsAgo = (ConvertToUnixTime(Get-Date)) - $STOP_TIME_UTC_EPOC
if ($SecondsAgo -le 3600) { $LAST_SESSION_RESULT_CODE = -1 }

# --------------  GET JOB DATA AND BACKUP SZE -----------------------

$AgentBackup = Get-VBRBackup -Name $Job.Name
$RestorePoints = Get-VBRRestorePoint -Backup $AgentBackup
$BACKUP_SIZE = 0
$DATA_SIZE = 0
foreach ($r in $RestorePoints) {
    $Storage = $r.FindStorage()
    $BACKUP_SIZE += $Storage.Stats.BackupSize
    $DATA_SIZE += $Storage.Stats.DataSize
}

# --------------  SEND DATA TO PUSHGATEWAY  -------------------------

# CREATE A CUSTOM OBJECT FROM GATHERED DATA
$JOBS_DATA = [PSCustomObject]@{
    report_type = 'veeam_job_report'
    name = $JOB_NAME
    type = $JOB_TYPE
    result = $LAST_SESSION_RESULT_CODE
    group = $GROUP
    start_time = $START_TIME_UTC_EPOCH
    end_time = $STOP_TIME_UTC_EPOC
    data_size = $DATA_SIZE
    backup_size = $BACKUP_SIZE
    url = $BASE_URL
}

$JOBS_DATA
PushDataToPrometheus $JOBS_DATA
"------------------------------"

}
