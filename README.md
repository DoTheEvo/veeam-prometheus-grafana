# Veeam B&R dashboard for prometheus

###### guide-by-example

![logo](https://i.imgur.com/EEExOB0.png)

-----------------

**WORK IN PROGRESS**<br>
**WORK IN PROGRESS**<br>
**BUT ALMOST THERE**

---------------

# Purpose

Centralized **monitoring dashboard** for Veeam B&R community edition backups.<br>
Though relatively easily adjusted to any backup solution.

* [Veeam Backup & Replication Community Edition](
https://www.veeam.com/virtual-machine-backup-solution-free.html)
* [Prometheus](https://prometheus.io/)
* [Grafana](https://grafana.com/)

A **powershell script** periodically runs on machines running VBR,
gathering information about the backup-jobs using powershell **cmdlets**.
This info gets pushed to a **prometheus pushgateway**, where it gets scraped
in to prometheus. Grafana **dashboard** then visualizes the gathered information.

![dashboard_pic](https://i.imgur.com/pRuYTQF.png)

<details>
<summary><h1>Basic info on Veeam Backup & Replication</h1></summary>

* VBR is installed on a windows machine. Can be physical or virtual.
* It needs a repository where to store backups.
  Can be a local drives, network storage, cloud,..
* Various types of jobs are created that regularly run, creating backups.

#### Virtual machines backup

* [Official documentation](https://helpcenter.veeam.com/docs/backup/vsphere/backup.html)

For Hyper-V / VMware.<br>
Veeam has admin credentails for the hypervisor,
it initiates the backup process at schedule, creates a snapshot of a VM,
process the VM's data, copies them in to a repository.<br>
VM's data are stored in a single file, `vkb` for full backup,
`vib` for incremental backup.<br>
Veeam by default creates weekly
[synthetic full backup,](https://helpcenter.veeam.com/docs/backup/vsphere/synthetic_full_hiw.html)
which combines `vib` files in to a new standalone `vbk`.

#### Fileshare backup

* [Official documentation](https://helpcenter.veeam.com/docs/backup/vsphere/file_share_support.html)

For network shares, called also just `File Backup`.<br>
Differs from VM backup in a way files are stored, no vbk and vib files,
but bunch of `vblob` files.<br>
Also long term retention requires an archive repository,
not available in free version.

#### Agent backup - Managed by server 

* [Official documentation](https://helpcenter.veeam.com/docs/backup/agents/agents_job.html)

For physical machines, intented for the ones that run 24/7
and should be always accessible by Veeam.<br>
Very similar to VMs backup. The VBR server initiates the backup,
the agent that is installed on the machine creates VSS snapshot,
and data end up in a repository, either in a `vkb` file or `vib` file.

#### Agent backup - Managed by agent - Backup policy

* [Official documentation](https://helpcenter.veeam.com/docs/backup/agents/agents_policy.html)

Intended for use with workstations that dont have regular connectivity
with the VBR server. VBR installs an agent on the machine,
hands it XML configuration, a **backup policy**, that tells it how and where
to regularly backup and then its hands off, agent is in charge.<br>
Veeam periodically tries to sync the current policy settings with the already
deployed agents during protection group rescans.

This one is bit tricky to monitor. In job history there is a track record
of what went on, but the policy updates are poisoning it.
Some extra steps are taken in powershell script to get backup runs without
policy updates. But as of writting this, there is not yet long enough and
varied enough test cases to have full confidence.<br>
So better keep a closer eye on endpoint policy backups.
</details>

---
---

<details>
<summary><h1>Prometheus and Grafana Setup</h1></summary>

[Here](https://github.com/DoTheEvo/selfhosted-apps-docker/tree/master/prometheus_grafana_loki)
is a separate guide-by-example for monitoring docker containers with
Prometheus Grafana Loki. Might be useful too.

## Files and directory structure

```
/home/
└── ~/
    └── docker/
        └── veeam_monitoring/
            ├── 🗁 grafana_data/
            ├── 🗁 prometheus_data/
            ├── 🗋 .env
            ├── 🗋 docker-compose.yml
            └── 🗋 prometheus.yml
```

* `grafana_data/` - a directory where grafana stores its data
* `prometheus_data/` - a directory where prometheus stores its database and data
* `.env` - a file containing environment variables for docker compose
* `docker-compose.yml` - a docker compose file, telling docker how to run the containers
* `prometheus.yml` - a configuration file for prometheus

The 3 files must be provided.</br>
The directories are created by docker compose on the first run.

## docker-compose

Three containers to spin up.</br>

* **Prometheus** - prometheus server, pulling, storing, evaluating metrics.
* **Pushgateway** - web server ready to receive pushed information on an open port.
* **Grafana** - web GUI visualization of the collected metrics in nice dashboards.

Of note for prometheus container is **data retention** set to 45 days,
and **admin api** being enabled.<br>
Pushgateway has **admin api** enabled too, to be able to execute wipes.

`docker-compose.yml`
```yml
services:

  prometheus:
    image: prom/prometheus:v2.43.1
    container_name: prometheus
    hostname: prometheus
    restart: unless-stopped
    user: root
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=45d'
      - '--web.enable-lifecycle'
      - '--web.enable-admin-api'
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus_data:/prometheus
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:9.5.1
    container_name: grafana
    hostname: grafana
    restart: unless-stopped
    env_file: .env
    user: root
    volumes:
      - ./grafana_data:/var/lib/grafana
    ports:
      - "3000:3000"

  pushgateway:
    image: prom/pushgateway:v1.5.1
    container_name: pushgateway
    hostname: pushgateway
    restart: unless-stopped
    command:
      - '--web.enable-admin-api'    
    ports:
      - "9091:9091"

networks:
  default:
    name: $DOCKER_MY_NETWORK
    external: true
```

`.env`

```bash
# GENERAL
DOCKER_MY_NETWORK=caddy_net
TZ=Europe/Bratislava

# GRAFANA
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=admin
GF_USERS_ALLOW_SIGN_UP=false

# DATE FORMATS SWITCHED TO NAMES OF THE DAYS OF THE WEEK
#GF_DATE_FORMATS_INTERVAL_HOUR = dddd
#GF_DATE_FORMATS_INTERVAL_DAY = dddd
```

In the `.env` above, there are two settings for grafana commented out.
Uncomment if prefering seeing days of the week on the X axis instead of exact date.

**All containers must be on the same network**.</br>
Which is named in the `.env` file.</br>
If one does not exist yet: `docker network create caddy_net`

### prometheus.yml

[Official documentation.](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)

A config file for prometheus, bind mounted in to the prometheus container.<br>
Of note is **honor_labels** set to true,
which sets that **conflicting labels** like `job`, set during push
are kept over labels set in `prometheus.yml` for the scrape job.
[Docs](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#scrape_config).

`prometheus.yml`
```yml
global:
  scrape_interval:     15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'pushgateway-scrape'
    scrape_interval: 60s
    honor_labels: true
    static_configs:
      - targets: ['pushgateway:9091']
```

## Reverse proxy

Caddy v2 is used, details
[here](https://github.com/DoTheEvo/selfhosted-apps-docker/tree/master/caddy_v2).</br>

`Caddyfile`
```php
grafana.{$MY_DOMAIN} {
    reverse_proxy grafana:3000
}

push.{$MY_DOMAIN} {
    reverse_proxy pushgateway:9091
}

# prom.{$MY_DOMAIN} {
#     reverse_proxy prometheus:9090
# }
```

## Start the containers 

* `docker compose up -d`

## Grafana configuration

* First run login with admin/admin.
* In Preferences > Datasources set `http://prometheus:9090` for url<br>
  save and test should be green
* Once some metrics are pushed to prometheus,
  they should be searchable in Explore section in Grafana.

![prometheus_working_pic_confirmation](https://i.imgur.com/hO8eERV.png)

</details>

---
---

<details>
<summary><h1>Learning in small steps</h1></summary>

A section written during first testing

what should work at this moment

* \<docker-host-ip>:3000 - grafana
* \<docker-host-ip>:9090 - prometheus 
* \<docker-host-ip>:9091 - pushgateway 

### Learning and testing how to push data to pushgateway

* metrics must be floats
* naming [convention](https://prometheus.io/docs/practices/naming/)
  is to end the metric names with units
* labels are used to pass strings in the url
* The idea what
 [job and instance](https://prometheus.io/docs/concepts/jobs_instances/) represent.
  In pushgateway I guess the job is still just overal main idea
  and instance is about final undivisable target. Final in sense that if taking disk
  usage data, do you put computer name as instance which can have multiple disk,
  or the disk themselves as instance? IMO the disk..


Prometheus requires linux [line endings.](
https://github.com/prometheus/pushgateway/issues/144)<br>
The "\`n" in the `$body` is to simulate it in windows powershell.

Also in powershell the grave(backtick) character - \` 
is for [escaping stuff](https://ss64.com/ps/syntax-esc.html)<br>
Here it is also used to escape new line. This allows breaking a command
in to multiple easier to read lines.
Though it caused issues, introducing space where it should not be,
thats why `-uri` is always full length in the final script<br>

`test.ps1`
```ps1
$body = "storage_diskC_free_space_bytes 32`n"

Invoke-RestMethod `
    -Method PUT `
    -Uri "http://10.0.19.4:9091/metrics/job/veeam_report/instance/PC1" `
    -Body $body
```

* in the $body we have name of the metrics - `storage_diskC_free_space_bytes`<br>
  and the value of that metrics - `32`<br>
* in the url, after `10.0.19.4:9091/metrics/`, we have two labels defined<br>
 `job=veeam_report` and `instance=PC1`<br>
  note the pattern, name of a label and value of it, they always must be in pair.
  They can be named whatever, but `job` and `instance` are customary

Heres how the data look in prometheus when executing `storage_diskC_free_space_bytes` query

![first_put](https://i.imgur.com/ZycWmHz.png)

The labels help us target the data in grafana.

### first dashobard

* create **new dashboard**, panel
* switch type to **Status history**
* select metric - `storage_diskC_free_space_bytes`
* [query options](https://grafana.com/docs/grafana/next/panels-visualizations/query-transform-data/#query-options)
  * min interval - 1h
  * relative time - now-10h/h
* to not deal with long ugly names add transformation - Rename by regex<br>
  Match - `.+instance="([^"]*).*` - [explained](https://stackoverflow.com/questions/2013124/regex-matching-up-to-the-first-occurrence-of-a-character)<br>
  Replace - `$1`
* can also play with transparency, legend, treshold for pretty colors

should look in the end somewhat like this

![first_graph](https://i.imgur.com/KW3B9dd.png)

*extra info*<br>
[Examples.](https://prometheus.io/docs/prometheus/latest/querying/examples/)
this command deletes all metrics on prometheus, assuming api is enabled<br>
`curl -X POST -g 'http://10.0.19.4:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~".*"}'`

So theres proof of concept of being able to send data to pushgateway and visualize them in grafana

</details>

---
---

# The powershell script

![script_pic](https://i.imgur.com/0u6ebWn.png)

**The Script: [veeam_prometheus_info_push.ps1](https://github.com/DoTheEvo/veeam-prometheus-grafana/blob/main/veeam_prometheus_info_push.ps1)**

Tested on VeeamBackup&Replication **v12**<br>
The script itself should be pretty informative with the comments in it.<br>

<details>
<summary>Changelog</summary>

* v0.3 in development
  * huge rewrite
* v0.2
  * added pushing of repository disk usage info
  * changed metrics name to include units
  * general cleanup
* v0.1 - the initial script

</details>

#### Get-VBRJob and Get-VBRComputerBackupJob

Veeam is now warning with every use of `Get-VBRJob` cmdlet,
that in the future versions it will not be returning agent-based backup jobs.
So to avoid tech debt, the script uses
`Get-VBRComputerBackupJob` and `Get-VBRComputerBackupJobSession`
and got bigger and messier because of it, but should be more ready for that future.

#### Job result codes

* 0 = success
* 1 = warning
* 2 = failed
* -1 =  running
* -11 =  running full backup or full synthetic backup
* 99 = disabled or not scheduled

The double digit ones are addition by the script.<br> 
Also agent based backups needed a rewrite of their values,
as they used different ones.

#### Job run visualization

To better show backup run the script checks when the job ended,
if it was within the last hour, the result is set to `-1` or `-11`.<br>
This means that even 5 minutes long backups are visualized, but might seem
as if they took up an hour.

#### Data size and Backup size

* Data size - The size of the data being backedup.<br>
  There is an issue of being unable to get the correct size for agent based
  backups that target specific folders. If the backup target would be 
  entire machine or a partition, the data would be correct.<br>
  To get at least some approximation, the size of the last vbk file
  multiplied by `1.3` is used in the report.
  `1.3` to account for some compression and deduplication.
* Backup size - the combined size of all backups of the job.


# DEPLOY.cmd file

To ease the deployment.

* Download [this repo.](https://github.com/DoTheEvo/veeam-prometheus-grafana/archive/refs/heads/main.zip)
* Extract.
* Edit `veeam_prometheus_info_push.ps1`<br>
  set `$BASE_URL` and `$GROUP` name.
* Run `DEPLOY.cmd` as an administrator.
* Done.

What happens under the hood:

* DEPLOY.cmd - checks if it runs as an administrator, ends if not.
* DEPLOY.cmd - creates directory `C:\Scripts` if it does not exists.
* DEPLOY.cmd - checks if the script already exists, if it does,
               renames it by adding a random suffix.
* DEPLOY.cmd - copies veeam_prometheus_info_push.ps1 in to `C:\Scripts`.
* DEPLOY.cmd - imports taskscheduler xml task named veeam_prometheus_info_push.
* TASKSCHEDULER - the task executes every 30 minutes, at xx:15 and xx:45,
                  with random delay of 30 seconds.
* TASKSCHEDULER - the task runs with the highest privileges as user - SYSTEM (S-1-5-18).
* DEPLOY.cmd - enables powershell scripts execution on that windows PC.
* DEPLOY.cmd - `Unblock-File` to allow the script execution when not created localy.

# Pushgateway

![pic_pushgateway](https://i.imgur.com/64Fqzfd.png)

On Pushgateway url one can easily check last pushed data.

To delete all data from pushgateway

* from web interface theres a button
* `curl -X PUT 10.0.19.4:9091/api/v1/admin/wipe`
* `curl -X PUT https://push.example.com/api/v1/admin/wipe`

#### periodily wiping clean the pushgateway

Without any action the pushed metrics sit on the pushgateway forever.
[This is intentional.](https://github.com/prometheus/pushgateway/issues/19)<br>
To better visualize possible lack of new reports coming from machines,
it be wise to wipe the pushgateway clean daily.

For this the dockerhost can have a simple systemd service and a timer.

`pushgateway_wipe.service`
```ini
[Unit]
Description=wipe clean prometheus pushgateway

[Service]
Type=simple
ExecStart=curl -X PUT https://push.example.com/api/v1/admin/wipe
```

`pushgateway_wipe.timer`
```ini
[Unit]
Description=wipe clean prometheus pushgateway
 
[Timer]
OnCalendar=00:19:00
 
[Install]
WantedBy=timers.target
```

enable the timer: `sudo systemctl enable pushgateway_wipe.timer`

# Prometheus

![pic_prometheus](https://i.imgur.com/7uFdC6J.png)

In the compose file the data retention is set to 45 days.

* `--storage.tsdb.retention.time=45d`

Not much really to do once it runs. Checking values can be done through grafana,
and for deletion one needs to use api.<br>
But still, one can access its web gui from LAN side with `<dockerhost>:9090`,
or can setup web access to it from the outside like for grafana and pushgateway.

[Official documentation on queries](https://prometheus.io/docs/prometheus/latest/querying/basics/)

To query something just write plain metrics name, like `veeam_job_result_info`.
In the table tab it shows result from a recent time window. Switching to graph
tab allows larger time range.

More targeted query, with the use of regex, signified by `=~`

  * `veeam_job_result_info{instance=~"Backup Copy Job.*"}`

To delete all metrics on prometheus

  * `curl -X POST -g 'http://10.0.19.4:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~".*"}'`

To delete metrics based off instance or group

* `curl -X POST -g 'https://prom.example.com/api/v1/admin/tsdb/delete_series?match[]={instance=~"^Backup.Copy.Job.*"}'`
* `curl -X POST -g 'https://prom.example.com/api/v1/admin/tsdb/delete_series?match[]={group=~"CocaCola"}'`

Theres no white space in the query, so dots are used.

# Grafana dashboard

Grafana usually shows graphs in a time range, like last 24 hours, or last 14 days.
This can be set in the top right corner of the dashboard.
There is a danger that a failure could stop reporting status, and if a check
of the dashboard would happen two weeks later, and grafana is showing last 7 days
there be no indication that a job even existed.<br>
Grafana alerts or prometheus alerts can address this.

![panel-status-history](https://i.imgur.com/2Lfhbdz.png)

### Veeam Status History

The first panel is for seeing last X days backup history, at quick glance

* Visualization = Status history
* Data source = Prometheus
* Query, switch from builder to code
  `veeam_job_result_info{job="veeam_job_report"}`
* Query options > Min interval = 1h<br>
  This sets the "resolution" of status history panel,<br>
  but data are renewed by default only every 30min.<br>
  During the first setup something smaller like 10min looks good.
* two ways to have nice labels
  * Query > Options > Legend > switch from `Auto` to `Custom`<br>
    Legend = `{{name}} | {{group}}`
  * Transform > Rename by regex<br>
    Match = `.+group="([^"]*).+instance="([^"]*).*`<br>
    Replace = `$2 | $1`
* Panel > title = `Veeam Status History`
* Status history > Show values = never
* Legend > Visibility = off
* Value mapping
  * 0 = Successful; Green
  * 1 = Warning; Yellow
  * 2 = Failed; Red
  * -1 = Running; Blue
  * -11 = Full Backup; Purple
  * 99 = Disabled | Unscheduled; Grey

---

![disk-use](https://i.imgur.com/Ijw2WoM.png)

### Repositories Disk Use

This panel shows how full repositories are.

Unfortunately grafana is not as capable as I hoped. While their example
[shows](https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/bar-gauge/)
exactly what I wanted, they cheated by picking the same max value for all disks.
So no nice GB and TB info, just percent.<br>
Tried to [float](https://github.com/grafana/grafana/discussions/66159)
the idea of maybe addressing this in their discussion on github.

* Visualization = Bar gauge
* Data source = Prometheus
* Query, switch from builder to code
  ```
  (veeam_repo_total_size_bytes{job="veeam_repo_report"}
  - veeam_repo_free_space_bytes{job="veeam_repo_report"})
  / ((veeam_repo_total_size_bytes{job="veeam_repo_report"}) /100)
  ```
* Query > Options > Legend > switch from `Auto` to `Custom`<br>
  Legend = `{{name}} | {{server}} | {{group}}`
* Panel > title = `Repositories Disk Use`
* Bar gauge > Display mode > Basic
* Standard options > Unit = Misc > Percent (0-100)
* Standard options > Min = 0
* Standard options > Max = 100
* Standard options > Decimals = 0
* Standard options > Display Name = `${__field.displayName}`<br>
  Needed [if only one repository](https://github.com/grafana/grafana/issues/48983),
  to show the name under the bar.
* Thresholds
  * 90 = red
  * 75 = Yellow
  * base = green

---  

![panel-table](https://i.imgur.com/OCbIiBF.png)

### Job's Details

This panel is a table with more details about jobs.

* Visualization = Table
* Data source = Prometheus
* Query, switch from builder to code
  `veeam_job_result_info{job="veeam_job_report"}`
  * Query options > Format = Table<br>
* This results in a table where each job's last result is shown,
  plus labels and their values.<br>
  One could start cleaning it up with a Transform,
  but there are other metrics missing and the time stuff is in absolute values
  instead of x minutes/hours ago.<br>
  So before cleaning, more mess will be added.
* [Rename](https://i.imgur.com/2CVyvWQ.gif) the original query
  from `A` to `result`.<br>
  This renaming will be used in all following queries so that the fields
  are distinguishable in transformation later.
* Create following queries, the first line is the new name,
  the second is the query code itself.<br>
  Every query has in Options > Type set to **table**.
  * `data_size`<br>
    `veeam_job_data_size_bytes{job="veeam_job_report"}`
  * `backup_size`<br>
    `veeam_job_backup_size_bytes{job="veeam_job_report"}`
  * `restore_points`<br>
    `veeam_job_restore_points_total{job="veeam_job_report"}`
  * `job_runtime`<br>
     ```
     veeam_job_end_time_timestamp_seconds{job="veeam_job_report"} 
     - veeam_job_start_time_timestamp_seconds{job="veeam_job_report"}
     ```
  * `last_job_run`<br>
    `round(time()-veeam_job_end_time_timestamp_seconds{job="veeam_job_report"})`
  * `last_report`<br>
    `round(time()-push_time_seconds{job="veeam_job_report"})`
* Now the results are there in many tables, switchable from a drop down menu,
  but they need to be combined in to one table.
* Transform > Join by field > Mode = OUTER; Field = instance
* Now theres one long table with lot of duplication as every query brought 
  labels again. Now to clean it up.
* Transform > Organize fields
  * Hide unwanted fields<br> 
    Hiding anything with number 2, 3, 4, 5, 6, 7 in name works to get bulk of it gone
  * Rename headers for fields that are kept.
  * Reorder with drag and drop.
* Now to tweak how it all looks and show readable values
* Panel options > Title = 'Job's Details'
* Table > Cell Options > Colored background
* Table > Cell Options > Background display mode = Gradient<br>
  Ignore for now all the colors.
* Standard options > Unit = `seconds (s)`; Decimals = 0<br>
  This makes the three time columns readable.
* Thresholds > delete whatever is there; set Base to be transparent
* Overrides > Fields with name = Data Size > Add override property >
  Standard options > Unit = bytes(SI)
* Overrides > Fields with name = Backup Size > Add override property >
  Standard options > Unit = bytes(SI)
* Overrides > Fields with name = Result > Value mappings
  * 0 = Successful; Green
  * 1 = Warning; Yellow
  * 2 = Failed; Red
  * -1 = Running; Blue
  * -11 = Running full backup; Purple
  * 99 = Disabled | Unscheduled; Grey
* Overrides > Fields with name = Group > Value mappings
  * group name; some color with some transparency to not be too loud
  * group name; some color with some transparency to not be too loud
  * group name; some color with some transparency to not be too loud

----

To set the dashboard to be shown right away when visiting the domain

* User (right top corner) > Profile > Home Dashboard > Set > Save


# Grafana alerts

some day
