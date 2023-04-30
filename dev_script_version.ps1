# v0.3  ----------------------------------------------------------------------
# ----------------------  CUSTOM CONFIG  -------------------------------------

$GROUP = 'CocaCola'
$BASE_URL = 'https://push.example.com'
$SERVER = $env:COMPUTERNAME # SET CUSTOM NAME IF DESIRED

# ----------------------------------------------------------------------------
# ----------------------  GENERIC USEFUL STUFF  ------------------------------
# ----------------------------------------------------------------------------

# WHEN USING HTTPS THIS FORCES TLS 1.2 INSTEAD OF POWERSHELL DEFAULT 1.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# USING EPOCH TIME, SECONDS SINCE 1.1.1970, UTC
Function GetUnixTimeUTC([AllowNull()][Nullable[DateTime]] $ttt) {
    if (!$ttt) { return 0 }
    [int]$unixtime = (get-date -Date $ttt.ToUniversalTime() -UFormat %s).`
    Substring(0,10)
    return $unixtime
}

# ----------------------------------------------------------------------------
# ----------------------  REPOSITORY INFO  -----------------------------------
# ----------------------------------------------------------------------------

$Repos = Get-VBRBackupRepository
foreach ($Repo in $Repos)
{

$TOTALSIZE = $Repo.GetContainer().CachedTotalSpace.InBytes
$FREESPACE = $Repo.GetContainer().CachedFreeSpace.InBytes

# PROMETHEUS REQUIRES LINUX LINE ENDINGS, SO \r\n IS REPLACED WITH \n
# ALSO POWERSHELL FEATURE "Here-Strings" IS USED, @""@ DEFINES BLOCK OF TEXT
# THE EMPTY LINE IS REQUIRED
$body = @"
veeam_repo_total_size_bytes $TOTALSIZE
veeam_repo_free_space_bytes $FREESPACE

"@.Replace("`r`n","`n")

# --------------  SEND DATA TO PUSHGATEWAY  -------------------------

Invoke-RestMethod `
    -Method PUT `
    -Uri "$BASE_URL/metrics/job/veeam_repo_report/instance/$Repo.Id/group/ `
          $GROUP/server/$SERVER/name/$Repo.Name" `
    -Body $body

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

$LastSession = $Job.FindLastSession()
#$LastSessionLog = $LastSession.Logger.GetLog().UpdatedRecords.Title

# --------------  GET JOB ID, JOB NAME, JOB TYPE  -------------------

$JOB_ID = $Job.Id
$JOB_NAME = $Job.Name
$JOB_TYPE = $Job.JobType

# --------------  GET JOB START AND STOP TIME -----------------------

$START_TIME_UTC_EPOCH = GetUnixTimeUTC($LastSession.progress.StartTimeLocal)
$STOP_TIME_UTC_EPOCH = GetUnixTimeUTC($LastSession.progress.StopTimeLocal)

# --------------  GET JOB LAST RESULT--------------------------------

# OFFICIAL VBR RESULT CODES: SUCCESS=0 | WARNING=1 | FAILED=2 | RUNNING=-1
# ADDED: DISABLED_OR_NOT_SCHEDULED=99 | RUNNING_FULL_OR_SYNT_FULL_BACKUP=-11
$LAST_SESSION_RESULT_CODE = $Job.GetLastResult().value__

# Options.JobOptions.RunManually -
#   TRUE IF THE JOB HAS UNCHECKED CHECKBOX - Run the job automatically
# IsScheduleEnabled -
#   FALSE IF THE JOB IS SET TO DISABLED
if ($Job.Options.JobOptions.RunManually) { $LAST_SESSION_RESULT_CODE = 99}
if (!$Job.IsScheduleEnabled) { $LAST_SESSION_RESULT_CODE = 99}

# TO VISUALIZE WHEN THE JOB RUN HAPPENED IN GRAPH
# AND TO DISTINGUISH FULL BACKUP OR A FULL SYNTHETIC BACKUP RUNS
$SecondsAgo = (GetUnixTimeUTC(Get-Date)) - $STOP_TIME_UTC_EPOCH
if ($SecondsAgo -le 3600) {

    # ------  JOB RUN ENDED WITHIN THE LAST HOUR  ---------

    $LAST_SESSION_RESULT_CODE = -1

    # ------  CHECK IF FULL SYNTHETIC  --------------------

    $LastSessionTasks = Get-VBRTaskSession -Session $LastSession
    $LastTasksLogs = $LastSessionTasks.Logger.GetLog().UpdatedRecords.Title
    $SyntText = 'Synthetic full backup created successfully'

    if ($LastTasksLogs -Contains $SyntText) { $LAST_SESSION_RESULT_CODE = -11 }

    # ------  CHECK IF FULL BACKUP  -----------------------

    foreach ($task in $LastSessionTasks) {
      if ($task.IsFullMode) { $LAST_SESSION_RESULT_CODE = -11 }
    }

}

# --------------  GET JOB DATA SIZE AND BACKUP SZE ------------------

$DATA_SIZE = $LastSession.BackupStats.DataSize
$BACKUP_SIZE = $LastSession.Info.BackupTotalSize

# --------------  SEND DATA TO PUSHGATEWAY  -------------------------

# PROMETHEUS REQUIRES LINUX LINE ENDINGS, SO \r\n IS REPLACED WITH \n
# ALSO POWERSHELL FEATURE "Here-Strings" IS USED, @""@ DEFINES BLOCK OF TEXT
# THE EMPTY LINE IS REQUIRED
$body = @"
veeam_job_result_info $LAST_SESSION_RESULT_CODE
veeam_job_start_time_timestamp_seconds $START_TIME_UTC_EPOCH
veeam_job_end_time_timestamp_seconds $STOP_TIME_UTC_EPOCH
veeam_job_data_size_bytes $DATA_SIZE
veeam_job_backup_size_bytes $BACKUP_SIZE

"@.Replace("`r`n","`n")

# SEND GATHERED DATA TO PROMETHEUS PUSHGATEWAY
Invoke-RestMethod `
    -Method PUT `
    -Uri "$BASE_URL/metrics/job/veeam_job_report/instance/$JOB_ID/group/`
          $GROUP/type/$JOB_TYPE/name/$JOB_NAME/server/$SERVER" `
    -Body $body

}

# ----------------------------------------------------------------------------
# --------------------  AGENT BASED JOBS  ------------------------------------
# ----------------------------------------------------------------------------

$AgentJobs = Get-VBRComputerBackupJob

# FOR EVERY AGENT JOB GATHER BASIC INFO
foreach ($Job in $AgentJobs)
{

# --------------  GET AGENT JOB LAST SESSION  ---------------------------

# CREATE A VARIABLE IDENTIFYING IF THE JOB IS A POLICY OR NOT
$IsPolicy = $False
if ($Job.Mode -eq 'ManagedByAgent') { $IsPolicy = $True }

# NOT ALL POLICY SESSIONS ARE BACKUPS, LOT OF CONFIG UPDATES THERE
# TO FILTER IT TO JUST ACTUAL BACKUPS THE NAME HAS WILDCARDS ADDED
# https://forums.veeam.com/post434804.html
$JobNameForQuery = $Job.Name
if ($IsPolicy) { $JobNameForQuery = '{0}?*' -f $Job.Name }
$Sessions = Get-VBRComputerBackupJobSession -Name $JobNameForQuery
$LastSession = $Sessions[0]

# --------------  GET AGENT JOB ID, NAME, TYPE  ---------------------

$JOB_ID = $Job.Id
$JOB_NAME = $Job.Name

if ($IsPolicy) {
    $JOB_TYPE = 'EpAgentPolicy'
} else {
    $JOB_TYPE = 'EpAgentBackup'
}

# --------------  GET AGENT JOB START AND STOP TIME -----------------

$START_TIME_UTC_EPOCH = GetUnixTimeUTC($LastSession.CreationTime)
$STOP_TIME_UTC_EPOCH = GetUnixTimeUTC($LastSession.EndTime)

# --------------  GET AGENT JOB LAST SESSION RESULT------------------

# AGENT JOBS HAVE DIFFERENT RESULT CODES THAN REGULAR JOBS
#     RUNNING=0 | SUCCESS=1 | WARNING=2 | FAILED=3
# THEREFORE RESULT value__ WILL NOT BE USED, INSTEAD A HASHTABLE TRANSLATION

# HASHTABLE THAT EASES TRANSLATION OF RESULTS FROM A WORD TO A NUMBER
# 'NONE' RESULT APPEARS WHEN THE JOB IS RUNNING
$ResultsTable = @{"Success"=0;"Warning"=1;"Failed"=2;"None"=-1}

# OFFICIAL VBR RESULT CODES: SUCCESS=0 | WARNING=1 | FAILED=2 | RUNNING=-1
# ADDED: DISABLED_OR_NOT_SCHEDULED=99 | RUNNING_FULL_OR_SYNT_FULL_BACKUP=-11
$LAST_SESSION_RESULT_CODE = $ResultsTable[$LastSession.Result.ToString()]

if (!$Job.ScheduleEnabled) { $LAST_SESSION_RESULT_CODE = 99}
if (!$Job.JobEnabled) { $LAST_SESSION_RESULT_CODE = 99}

# TO VISUALIZE WHEN THE JOB RUN HAPPENED IN GRAPH
# AND TO DISTINGUISH FULL BACKUP OR A FULL SYNTHETIC BACKUP RUNS
$SecondsAgo = (GetUnixTimeUTC(Get-Date)) - $STOP_TIME_UTC_EPOCH
if ($SecondsAgo -le 3600) {

    # ------  AGENT JOB RUN ENDED WITHIN THE LAST HOUR  ---

    $LAST_SESSION_RESULT_CODE = -1

    # ------  CHECK IF FULL SYNTHETIC  --------------------

    $LastSessionTasks = Get-VBRTaskSession -Session $LastSession
    $LastTasksLogs = $LastSessionTasks.Logger.GetLog().UpdatedRecords.Title
    $SyntText = 'Synthetic full backup created successfully'

    if ($LastTasksLogs -Contains $SyntText) { $LAST_SESSION_RESULT_CODE = -11 }

    # ------  CHECK IF FULL BACKUP  -----------------------

    $ActiveFullText = 'Active Full backup created'

    if ($LastTasksLogs -Contains $ActiveFullText) {
        $LAST_SESSION_RESULT_CODE = -11
    }

    # foreach ($task in $LastSessionTasks) {
    #   if ($task.IsFullMode) { $LAST_SESSION_RESULT_CODE = -11 }
    # }

}

# --------------  GET AGENT JOB DATA SIZE AND BACKUP SZE -------------

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

# PROMETHEUS REQUIRES LINUX LINE ENDINGS, SO \r\n IS REPLACED WITH \n
# ALSO POWERSHELL FEATURE "Here-Strings" IS USED, @""@ DEFINES BLOCK OF TEXT
# THE EMPTY LINE IS REQUIRED
$body = @"
veeam_job_result_info $LAST_SESSION_RESULT_CODE
veeam_job_start_time_timestamp_seconds $START_TIME_UTC_EPOCH
veeam_job_end_time_timestamp_seconds $STOP_TIME_UTC_EPOCH
veeam_job_data_size_bytes $DATA_SIZE
veeam_job_backup_size_bytes $BACKUP_SIZE

"@.Replace("`r`n","`n")

# SEND GATHERED DATA TO PROMETHEUS PUSHGATEWAY
Invoke-RestMethod `
    -Method PUT `
    -Uri "$BASE_URL/metrics/job/veeam_job_report/instance/$JOB_ID/group/`
          $GROUP/type/$JOB_TYPE/name/$JOB_NAME/server/$SERVER" `
    -Body $body

}
