# Veeam B&R dashboard

###### guide-by-example

![logo](https://i.imgur.com/EEExOB0.png)

-----------------

# Purpose

Centralized **monitoring dashboard** with **alerts** for Veeam B&R.<br>
Works with community edition.
Relatively easily adjusted to any backup solution that can report basic info.

* [Veeam Backup & Replication Community Edition](
https://www.veeam.com/virtual-machine-backup-solution-free.html)
* [Prometheus](https://prometheus.io/)
* [Grafana](https://grafana.com/)

A **powershell script** periodically runs on machines running VBR,
gathering information about backup-jobs and repositories.
This info gets pushed to a **prometheus pushgateway**, where it gets scraped
in to prometheus.
Grafana **dashboard** then visualizes the gathered information.<br>

![dashboard_pic](https://i.imgur.com/9HO1ktb.png)

<details>
<summary><h1>Basic info on Veeam Backup & Replication</h1></summary>

* VBR is installed on a windows machine. Can be physical or virtual.
* It needs a repository where to store backups.
  Can be local drives, network storage, cloud,..
* Job logs are in `C:\ProgramData\Veeam\Backup`
* Various types of jobs are created that regularly run, creating backups.

#### Virtual machines backup

* [Official documentation](https://helpcenter.veeam.com/docs/backup/vsphere/backup.html)

For Hyper-V / VMware.<br>
Veeam has admin credentails for the hypervisor.
It initiates the backup process at schedule, creates a snapshot of a VM,
process the VM's data, copies them in to a repository, deletes the snapshot.<br>
VM's data are stored in a single file, `vbk` for full backup,
`vib` for incremental backup.<br>
Veeam by default creates weekly
[synthetic full backup,](https://helpcenter.veeam.com/docs/backup/vsphere/synthetic_full_hiw.html)
which combines previous backups in to a new standalone `vbk`.

#### Fileshare backup

* [Official documentation](https://helpcenter.veeam.com/docs/backup/vsphere/file_share_support.html)

For network shares, called also just `File Backup`.<br>
Differs from VM backup in a way files are stored, no vbk and vib files,
but bunch of `vblob` files.<br>
Also, long term retention requires an archive repository,
not available in community edition.

#### Agent backup - Managed by server 

* [Official documentation](https://helpcenter.veeam.com/docs/backup/agents/agents_job.html)

For physical machines, intented for the ones that run 24/7
and should be always accessible by Veeam.<br>
Very similar to VMs backup. The VBR server initiates the backup,
the agent that is installed on the machine creates VSS snapshot,
and data end up in a repository, either in a `vbk` file or `vib` file.

#### Agent backup - Managed by agent - Backup policy

* [Official documentation](https://helpcenter.veeam.com/docs/backup/agents/agents_policy.html)

Intended for use with workstations that dont have regular connectivity
with the VBR server. VBR installs an agent on the machine,
hands it XML configuration, a **backup policy**, that tells it how and where
to regularly backup and then its hands off, the agent is in charge.<br>
Veeam periodically tries to sync the current policy settings with the already
deployed agents during protection group rescans.

This one was bit tricky to monitor, as job's history contains not just backup
sessions, but also the policy updates.
Some extra steps are needed in the powershell script to get backup runs without
policy updates.
</details>

---
---

<details>
<summary><h1>Prometheus and Grafana Setup in Docker</h1></summary>

[Here](https://github.com/DoTheEvo/selfhosted-apps-docker/tree/master/prometheus_grafana_loki)
is a guide-by-example for monitoring using Prometheus, Grafana, Loki.
Might be useful as it goes in to more details.

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
* **Pushgateway** - web server ready to receive pushed information.
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
    image: grafana/grafana:9.5.2
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
GF_SERVER_ROOT_URL=https://grafana.example.com
# GRAFANA EMAIL SETTINGS
GF_SMTP_ENABLED=true
GF_SMTP_HOST=smtp-relay.sendinblue.com:587
GF_SMTP_USER=example@gmail.com
GF_SMTP_PASSWORD=xzu0dfFhn3eqa
startTLS_policy=NoStartTLS
# GRAFANA CUSTOM SETTINGS
# DATE FORMATS SWITCHED TO NAMES OF THE DAYS OF THE WEEK
#GF_DATE_FORMATS_INTERVAL_HOUR = dddd
#GF_DATE_FORMATS_INTERVAL_DAY = dddd
```

The containers must be on a **custom named docker network**,
along with caddy reverse proxy. This allows **hostname resolution**.</br>
The network name is set in the `.env` file, in `DOCKER_MY_NETWORK` variable.</br>
If one does not exist yet: `docker network create caddy_net`

In the `.env` file, there are also two date settings for grafana commented out.
Uncomment to show full name of days in the week instead of exact date.<br>

## prometheus.yml

[Official documentation.](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)

A config file for prometheus, bind mounted in to the prometheus container.<br>
Of note is **honor_labels** set to true,
which means that **conflicting labels**, like `job`, set during push
are kept over labels set by `prometheus.yml` for that scrape job.
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
* In Preferences > Datasources set `http://prometheus:9090` for url.<br>
  Save and test should be green.
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
* labels in url are used to pass strings info and to mark the metrics
* The idea what
 [job and instance](https://prometheus.io/docs/concepts/jobs_instances/) represent.
  In pushgateway I guess the job is still just overal main idea
  and instance is about final unique, err instance.


Prometheus requires linux [line endings.](
https://github.com/prometheus/pushgateway/issues/144)<br>
The "\`n" in the `$body` is to simulate it in windows powershell.

Also in powershell the grave(backtick) character - \` 
is for [escaping stuff](https://ss64.com/ps/syntax-esc.html)<br>
Here it is also used to escape new line. This allows breaking a command
in to multiple easier to read lines.
Though it caused issues, introducing space where it should not be,
thats why `-uri` is always full length in the final script.
God damn fragile powershell.

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

So theres the proof of concept of being able to send data to pushgateway
and visualize them in grafana

### PromQL basics

[Here's](https://github.com/DoTheEvo/selfhosted-apps-docker/tree/master/prometheus_grafana_loki#promql-basics)
my basic understanding.<br>
How prometheus stores data, how to query, difference between instant vector
and range vector, some links.

</details>

---
---

# The powershell script

![script_pic](https://i.imgur.com/0u6ebWn.png)

**The Script: [veeam_prometheus_info_push.ps1](https://github.com/DoTheEvo/veeam-prometheus-grafana/blob/main/veeam_prometheus_info_push.ps1)**

The script itself should be pretty informative with the comments in it.<br>

Tested with VBR **v12**<br>
Might work with v11, except for agent-based backups as there were bugs
in new cmdlets in that version.

<details>
<summary>Changelog</summary>

* v0.4
  * added $ErrorActionPreference = "Stop"
    which will terminate script's execution on any error
  * job run time window calculation changed from the endtime to startime
  * detection of a job being a full backup is now separate part and
    done after the backup ends
* v0.3
  * huge rewrite
* v0.2
  * added pushing of repository disk usage info
  * changed metrics name to include units
  * general cleanup
* v0.1 - the initial script

</details>

#### Get-VBRJob and Get-VBRComputerBackupJob

Veeam is now warning with every use of `Get-VBRJob` cmdlet that 
future versions will not be returning agent-based backup jobs.
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
Also agent based backups needed a rewrite of their return values,
as they used different ones.

#### Job run visualization

To better show backup run the script checks when the job started,
if it was within the last hour, the result is set to `-1` or `-11`.<br>
This visualization is not precise and can be shifted one time block in time.

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

<details>
<summary>What happens under the hood:</summary>

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

</details>

# Pushgateway

![pic_pushgateway](https://i.imgur.com/64Fqzfd.png)

Pushed data can be checked On Pushgateway's url.

To delete all data from pushgateway

* from web interface theres a button
* `curl -X PUT 10.0.19.4:9091/api/v1/admin/wipe`
* `curl -X PUT https://push.example.com/api/v1/admin/wipe`

### Periodily wiping clean the pushgateway

Without any action the pushed metrics sit on the pushgateway **forever**.
[This is intentional.](https://github.com/prometheus/pushgateway/issues/19)<br>
To better visualize possible lack of new reports coming in,
it be wise to wipe the pushgateway clean daily.

For this the dockerhost can have a simple systemd service and a timer.

<details>
<summary>How to setup systemd pushgateway_wipe.service</summary>

In `/etc/systemd/system/`

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

</details>

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

To delete metrics of an instance or group

* `curl -X POST -g 'https://prom.example.com/api/v1/admin/tsdb/delete_series?match[]={instance=~"^Backup.Copy.Job.*"}'`
* `curl -X POST -g 'https://prom.example.com/api/v1/admin/tsdb/delete_series?match[]={group=~"CocaCola"}'`

Theres no white space in the query, so dots are used.

# Grafana dashboard

![dashboard](https://i.imgur.com/FjpN76I.png)

The json file in this repo can be imported in to grafana.

* [VBR_dashboard_v2.json](https://github.com/DoTheEvo/veeam-prometheus-grafana/blob/main/VBR_dashboard_v2.json)
* Dashboards > New > Import > paste json

Changelog

* v2 - changed the initial time ranges, fixed last run and last report times
* v1 - the initial dashboard 

To set the dashboard to be shown right away when visiting the domain<br>
User (right top corner) > Profile > Home Dashboard > Set > Save

<details>
<summary><h1>Steps to manually recreate dashboard</h1></summary>

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
    `time()-last_over_time(veeam_job_end_time_timestamp_seconds{job="veeam_job_report"}[30d])`
  * `last_report`<br>
    `time()-last_over_time(push_time_seconds{job="veeam_job_report"}[30d])`
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
* Panel options > Title = `Job's Details`
* Thresholds > delete whatever is there; set Base to be transparent
* Now the table will be modified using overrides<br>
  So that columns can be targeted separatly.
* **Overrides**
* Fields with name matching regex = `/Last Run|Runtime|Last Report/`<br>
  Standard options > Unit = `seconds (s)`<br>
  Standard options > Decimals = `0`
* Fields with name matching regex = `/Data Size|Backup Size/`<br>
  Standard options > Unit = `bytes(SI)`<br>
* Fields with name = `Result` > Value mappings<br>
  * Value Mapping:
    * 0 = Successful; Green
    * 1 = Warning; Yellow
    * 2 = Failed; Red
    * -1 = Running; Blue
    * -11 = Full Backup; Purple
    * 99 = Disabled | Unscheduled; Grey
    * the colors should be muted by transparency ~0.4
  * Cell options > Cell type
    * `Colored background`
    * `Gradient`
* Fields with name = `Group` > Value mappings<br>
  * Value Mapping:
    * 0 = water; Green
    * 1 = CocaCola; Yellow
    * 2 = beer; Red
    * the colors should be muted by transparency ~0.3
  * Cell options > Cell type
    * `Colored background`
    * `Gradient`
* Save and look.
* Adjusting column width will be creating overrides for that column.<br>
  Just to be aware, as it might be weird seeing like 12 overrides afterwards.

</details>

----
----

# Grafana alerts

![email_alert](https://i.imgur.com/Y01YoBw.png)

Grafana alerts help with the reliability and danger of a failure going unnoticed.<br>
Especially considering the dynamic nature of this setup, meaning that if reporting
stops for any reason, after some time there is no indication that a job
even existed, let alone failed.

Before getting to alerts, first the delivery mechanism and policy.

### Contact points

Grafana > Alerting > Contact points

##### email

Just needs corectly set some smtp stuff in the `.env` file for grafana,
as can be seen in the setup section.<br>
The contact point already exists, named `grafana-default-email`.<br>
Can be tested if it actually works when editing the contact point.


##### ntfy

Push notifications for a phone or desktop using selfhosted [ntfy](https://ntfy.sh/).<br>
Detailed setup of running ntfy as a docker container
[here.](https://github.com/DoTheEvo/selfhosted-apps-docker/tree/master/gotify-ntfy-signal#grafana-to-ntfy)<br>

* New contact point
* Name = `ntfy`
* Integration = `Webhook`
* URL = `https://ntfy.example.com/veeam`<br>
  or if grafana-to-ntfy is already setup on the same docker network,
  then URL = `http://grafana-to-ntfy:8080`
* plain ntfy does not need credentials,<br>
  grafana-to-ntfy needs the ones from its `.env` file set.
* Disable resolved message = check
* Test
* Save

Issue I noticed now in testing with ntfy, is that if you get multiple failures
it wont deliver. Could be solved by not letting it send the complex grafana
json full of dynamic values, but just some generic static text about a failure.<br>
Will eventually look in to it, or report it to the dev.

### Notification policies 

Editing the `Default policy`, making sure the contact point is the correct one
is enough if just one contact point is planned to be used. Like just email.

Of note are `Timing options` inside policy, that sets how often a firing alarm
will resend notification. Default is 4h, +5m for group interval.

To fire notification on multiple contact points,
for alerts in `veeam_alerts` folder:

* Within the `Default policy` adding `+ New nested policy`.
* Matching labels: `grafana_folder` `=` `veeam_alerts`<br>
  Select `Contact point` - `grafana-default-email`<br>
  Enable - `Continue matching subsequent sibling nodes`<br>
  Which means that after matching, it will continue to look for 
  other policies that would also match
* Do the same again for a new nested policy, but use contact point to `ntfi`.

The `Default policy` is applied only if no other policy fits.

## Alerts

Currently these alerts are not long term tested.<br>
They should work, but should be considered in development.

<details>
<summary><h3>Alert rule - Backup Failed or Warning</h3></summary>

- **1 Set an alert rule name**
  - Rule name = `veaam_backup_failed_or_warning`
- **2 Set a query and alert condition**
  - **A** - Prometheus; set Last 2d
    - Options > Min step = 15m
    - switch from builder to code
    - `veeam_job_result_info{job="veeam_job_report"}`
  - **B** - Reduce
    - Function = Last
    - Input = A
    - Mode = Strict
  - **C** - Treshold
    - Input = B
    - is within range 0 to 3 (it's [not inclusive](https://github.com/grafana/grafana/issues/19193))
    - Make this the alert condition
- **3 Alert evaluation behavior**
  - Folder = "veeam_alerts"
  - Evaluation group (interval) = "one_hour"<br>
  - Evaluation interval = 1h
  - For = 0s
  - Configure no data and error handling
    - Alert state if no data or all values are null = OK
- **4 Add details for your alert rule**
  - Metrics labels can be used here
- **5 Notifications**
  - nothing
- Save and exit

</details>

<details>
<summary><h3>Alert rule - Repo is 85% full</h3></summary>

- **1 Set an alert rule name**
  - Rule name = `veaam_repo_full`
- **2 Set a query and alert condition**
  - **A** - Prometheus; set Last 2d
    - Options > Min step = 15m
    - switch from builder to code
      ```
      (veeam_repo_total_size_bytes{job="veeam_repo_report"}
      - veeam_repo_free_space_bytes{job="veeam_repo_report"})
      / ((veeam_repo_total_size_bytes{job="veeam_repo_report"}) /100)
      ```
  - **B** - Reduce
    - Function = Last
    - Input = A
    - Mode = Strict
  - **C** - Treshold
    - Input = B
    - is above `84`
    - Make this the alert condition
- **3 Alert evaluation behavior**
  - Folder = "veeam_alerts"
  - Evaluation group (interval) = "one_hour"<br>
  - Evaluation interval = 1h
  - For = 0s
  - Configure no data and error handling
    - Alert state if no data or all values are null = OK
- **4 Add details for your alert rule**
  - Metrics labels can be used here
- **5 Notifications**
  - nothing
- Save and exit

</details>

<details>
<summary><h3>Alert rule - No report for 5 days</h3></summary>

- **1 Set an alert rule name**
  - Rule name = `veaam_noreport_five_days`
- **2 Set a query and alert condition**
  - **A** - Prometheus; set Last 30 days (now-30d to now)
    - switch from builder to code
      `time()-last_over_time(push_time_seconds{job="veeam_job_report"}[30d])`
  - **B** - Reduce
    - Function = Last
    - Input = A
    - Mode = Strict
  - **C** - Treshold
    - Input = B
    - is above `432000`
    - Make this the alert condition
- **3 Alert evaluation behavior**
  - Folder = "veeam_alerts"
  - Evaluation group (interval) = "twelve_hours"<br>
  - Evaluation interval = 12h
  - For = 0s
  - Configure no data and error handling
    - Alert state if no data or all values are null = Error
- **4 Add details for your alert rule**
  - nothing
- **5 Notifications**
  - nothing
- Save and exit

</details>

<details>
<summary><h3>Alert rule - No backup done for 5 days</h3></summary>

- **1 Set an alert rule name**
  - Rule name = `veaam_nobackup_five_days`
- **2 Set a query and alert condition**
  - **A** - Prometheus; set Last 30 days (now-30d to now)
    - switch from builder to code
      `time()-last_over_time(veeam_job_end_time_timestamp_seconds{job="veeam_job_report"}[30d])`
  - **B** - Reduce
    - Function = Last
    - Input = A
    - Mode = Strict
  - **C** - Treshold
    - Input = B
    - is above `432000`
    - Make this the alert condition
- **3 Alert evaluation behavior**
  - Folder = "veeam_alerts"
  - Evaluation group (interval) = "twelve_hours"<br>
  - Evaluation interval = 12h
  - For = 0s
  - Configure no data and error handling
    - Alert state if no data or all values are null = Error
- **4 Add details for your alert rule**
  - Metrics labels can be used here<br>
    nothing
- **5 Notifications**
  - nothing
- Save and exit

</details>
