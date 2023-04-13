# Veeam B&R dashboard for prometheus

###### guide-by-example

![logo](https://i.imgur.com/xScE6fL.png)

-----------------

**WORK IN PROGRESS**<br>
**WORK IN PROGRESS**<br>
**WORK IN PROGRESS**

FUck, gonna have to learn more on backup sessions types - 
`windows agent policy` vs `windows agent backup`

cuz what [can happen](https://i.imgur.com/xuIPQaT.png) is that last session job
returned info is on that short little policy shit and the actual backup
can be failing and dashboard would be unaware.<br>
Still learning that all non-nas and non-vms backups are agent based.
No matter if server or agent decides, theres still an agent.

---------------

# Purpose

Centralized **monitoring dashboard** for Veeam B&R community edition backups.<br>

* [Veeam Backup & Replication Community Edition](
https://www.veeam.com/virtual-machine-backup-solution-free.html)
* [Prometheus](https://prometheus.io/)
* [Grafana](https://grafana.com/)

A **powershell script** periodically runs on machines running VBR,
gathering information about the backup-jobs using powershell **cmdlets**.
This info gets pushed to a **prometheus pushgateway**, where it gets scraped
in to prometheus. Grafana **dashboard** then visualizes the gathered information.

![dashboard_pic](https://i.imgur.com/4eW1dJh.png)

# Basic info on Veeam Backup & Replication

There are several types of jobs in VBR

* Virtual Machine backup - Hyper-V / VMware
* File Backup - for network shares
* Agent Backup - for physical windows machine 
  * Managed by a server (agent still does the work) 
  * Managed by an agent

To gather data with powershell `Get-VBRJob` works, but since v10 of VBR
the developers dont want people to use it for agent base backups.<br>
For those the `Get-VBRComputerBackupJob` should be used.

....its unfinished here...

Get-VBRJob

Get-VBRComputerBackupJob

Get-VBRNASBackup

`$jobs = Get-VBRJob -WarningAction SilentlyContinue | where {$_.BackupPlatform.Platform -ne 'ELinuxPhysical' -and $_.BackupPlatform.Platform -ne 'EEndPoint'}`

<details>
<summary><h1>Prometheus and Grafana Setup</h1></summary>

[Here](https://github.com/DoTheEvo/selfhosted-apps-docker/tree/master/prometheus_grafana_loki)
is separate universal guide-by-example for monitoring docker containers with
Prometheus Grafana Loki. Might be useful too.

# Files and directory structure

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

* `grafana/` - a directory containing grafanas configs and dashboards
* `grafana_data/` - a directory where grafana stores its data
* `prometheus_data/` - a directory where prometheus stores its database and data
* `.env` - a file containing environment variables for docker compose
* `docker-compose.yml` - a docker compose file, telling docker how to run the containers
* `prometheus.yml` - a configuration file for prometheus

The 3 files must be provided.</br>
The directories are created by docker compose on the first run.

# docker-compose

Three containers to spin up.</br>

* **Prometheus** - prometheus server, pulling, storing, evaluating metrics
* **Pushgateway** - web server ready to receive pushed information on an open port
* **Grafana** - web GUI visualization of the collected metrics in nice dashboards

Ports are actually mapped to the docker host, to be able to easily access
these by docker-host-ip and port. But if reverse proxy like caddy is used and 
subdomains setup, then `ports` section can be removed or replaced by `expose`.

`docker-compose.yml`
```yml
services:

  prometheus:
    image: prom/prometheus:v2.43.0
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
    image: grafana/grafana:9.4.7
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

**All containers must be on the same network**.</br>
Which is named in the `.env` file.</br>
If one does not exist yet: `docker network create caddy_net`

# Reverse proxy

Caddy v2 is used, details
[here](https://github.com/DoTheEvo/selfhosted-apps-docker/tree/master/caddy_v2).</br>

`Caddyfile`
```
grafana.{$MY_DOMAIN} {
    reverse_proxy grafana:3000
}

push.{$MY_DOMAIN} {
    reverse_proxy pushgateway:9091
}
```

# Prometheus configuration

#### prometheus.yml

[Official documentation.](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)

A config file for prometheus, bind mounted in to prometheus container.

Of note is **honor_labels** set to true,
which makes sure that **conflicting labels** like `job`, set during push
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

# Grafana configuration

* first run login with admin/admin
* in Preferences > Datasources set `http://prometheus:9090` for url<br>
  save and test should be green<br>
* once some values are pushed to prometheus, create a new dashboard...

![prometheus_working_pic_confirmation](https://i.imgur.com/aFKtSTe.png)

</details>

---
---

<details>
<summary><h1>Learning in small steps</h1></summary>

what should work at this moment

* \<docker-host-ip>:3000 - grafana
* \<docker-host-ip>:9090 - prometheus 
* \<docker-host-ip>:9091 - pushgateway 

### learning and testing how to push data to pushgateway

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
Here it is used to escape new line. This allows breaking the command
in to multiple easier to read lines.<br>
This is not related to the previous issue of line endings.

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

![first_put](https://i.imgur.com/9G0QcuT.png)

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

![first_graph](https://i.imgur.com/DLnCWdB.png)

*extra info*<br>
[Examples.](https://prometheus.io/docs/prometheus/latest/querying/examples/)
this command deletes all metrics on prometheus, assuming api is enabled<br>
`curl -X POST -g 'http://10.0.19.4:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~".*"}'`

So theres proof of concept of being able to send data to pushgateway and visualize them in grafana

</details>

---
---

# The powershell script

**The Script: [veeam_prometheus_info_push.ps1](https://github.com/DoTheEvo/veeam-prometheus-grafana/blob/main/veeam_prometheus_info_push.ps1)**

The script should be pretty readable with the comments in it.

Of note are the results codes for backup jobs

* 0 = success
* 1 = warning
* 2 = failed
* -1 =  running
* -2 = disabled or not scheduled<br>
  unlike the rest that come from veeam, this one is manually checked and set

#### DEPLOY.cmd file

The file that eases the installation process

* download [this repo](https://github.com/DoTheEvo/veeam-prometheus-grafana/archive/refs/heads/main.zip)
* extract
* run `DEPLOY.cmd` as administrator
* go edit `C:\Scripts\veeam_prometheus_info_push.ps1`
  to change the `group` name and `base_url`
* done

What happens under the hood:

* DEPLOY.cmd - checks if its run as administrator, ends if not
* DEPLOY.cmd - enables powershell scripts execution on that windows PC
* DEPLOY.cmd - creates directory C:\Scripts if it does not existing
* DEPLOY.cmd - checks if the script already exists, if it does
               renames it with random suffix
* DEPLOY.cmd - copies veeam_prometheus_info_push.ps1 in to C:\Scripts
* DEPLOY.cmd - imports taskscheduler xml task named veeam_prometheus_info_push
* TASKSCHEDULER - the task executes every hour with random delay of 30 seconds
* TASKSCHEDULER - runs with the highest privileges as user - SYSTEM (S-1-5-18)

### Script Change log

* v0.2
  * added pushing of repository disk usage info
  * changed metrics name to include units
  * general cleanup
* v0.1 - the initial script

# Pushgateway

![pic_pushgateway](https://i.imgur.com/4GZIu8g.png)

Ideally one uses a subdomain and https for pushgateway, for that:

* Have subdomain `push.example.com` and DNS record aiming at the servers public IP
* Use [caddy](https://github.com/DoTheEvo/selfhosted-apps-docker/tree/master/caddy_v2)
  as a reverse proxy. It is completely in charge of traffic coming on 80 and 443.<br>
  The rule from the reverse proxy section in this Readme applies,
  so if something comes at `push.example.com` it gets redirected to
  container named pushgateway and port 9091.
* The `$base_url` in the script is `https://push.example.com`
* Should now work.

To delete all data from pushgateway

* from web interface theres a button
* `curl -X PUT 10.0.19.4:9091/api/v1/admin/wipe`
* `curl -X PUT https://push.example.com/api/v1/admin/wipe`

### periodily wiping clean the pushgateway

Without any action the pushed metrics sit on the pushgateway forever.
[This is intentional.](https://github.com/prometheus/pushgateway/issues/19)<br>
But to better visualize the lack of information coming from the machines
there might be some benefit to daily wiping pushgateway clean.

For this the dockerhost can have a simple systemd service and timer.

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

![pic_prometheus](https://i.imgur.com/YzNWZQb.png)

In the compose file the data retention is set to 45 days.

* `--storage.tsdb.retention.time=45d`

Not much really to do once it runs. Checking values and deleting them I guess.<br>
You can access its web interface from LAN side with `<dockerhost>:9090`, or
you can setup web access to it from the outside if you wish.
Same process as with pushgateway or any other webserver accessible through caddy.

[Official documentation on queries](https://prometheus.io/docs/prometheus/latest/querying/basics/)

To query something just write plain metrics name, like `veeam_job_result_info`.
But in the table tab it shows you by default only the result from a recent
time window. You can switch to what date you want query too apply,
or switch to graph view and set range to few weeks.

More targeted query, with the use of regex, signified by `=~`

  * `veeam_job_result_info{instance=~"Backup Copy Job.*"}`

To delete all metrics on prometheus

  * `curl -X POST -g 'http://10.0.19.4:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~".*"}'`

To delete metrics based off instance or group

* `curl -X POST -g 'https://prom.example.com/api/v1/admin/tsdb/delete_series?match[]={instance=~"^Backup.Copy.Job.*"}'`
* `curl -X POST -g 'https://prom.example.com/api/v1/admin/tsdb/delete_series?match[]={group=~"cocacola"}'`

Theres no white space in the query, so dots are used.

# Grafana dashboard

![panel-status-history](https://i.imgur.com/gO6CW7i.png)

Might be bit difficult to make the dashboard right away with too little data
on Prometheus yet. Use small time ranges.

The first panel is for seeing last X days backup history, at quick glance

* Visualization = Status history
* Data source = Prometheus
* Query, switch from builder to code
  `veeam_job_result_info{job="veeam_report"}`
* Query options > Min interval = 1h<br>
  this value sets the "resolution" of status history panel,
  but the push by default is happening only every hour.
* two ways to have nice labels
  * Query > Options > Legend > switch from `Auto` to `Custom`<br>
    Legend = `{{instance}} | {{group}}`
  * Transform > Rename by regex<br>
    Match = `.+group="([^"]*).+instance="([^"]*).*`<br>
    Replace = `$2 | $1`
* Panel > title = Veeam History
* Status history > Show values = never
* Legend > Visibility = off
* Value mapping
  * 0 = Successful; Green
  * 1 = Warning; Yellow
  * 2 = Failed; Red
  * -1 = Running; Blue
  * -2 = Disabled | Unscheduled; Grey

---

![disk-use](https://i.imgur.com/9hNGx9K.png)

The second panel is to get info how full repositories are.<br>
Surprisingly grafana is not as capable as I hoped.
While their example
[shows](https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/bar-gauge/)
exactly what I wanted, they cheated by picking the same max value for all disks.<br>
So unfortunately no nice GB and TB info, just percent.<br>
Tried to [float](https://github.com/grafana/grafana/discussions/66159)
the idea of fixing this in their discussion on github.

* Visualization = Bar gauge
* Data source = Prometheus
* Query, switch from builder to code
  ```
  (veeam_repo_total_size_bytes{job="veeam_report_repo"}
  - veeam_repo_free_space_bytes{job="veeam_report_repo"})
  / ((veeam_repo_total_size_bytes{job="veeam_report_repo"}) /100)
  ```
* Query > Options > Legend > switch from `Auto` to `Custom`<br>
  Legend = ` {{group}} - {{instance}} - {{server}}`
* Panel > title = Repositories Disks Usage
* Bar gauge > Display mode > Basic
* Standard options > Unit = Misc > Percent (0-100)
* Standard options > Min = 0
* Standard options > Max = 100
* Standard options > Decimals = 0
* Thresholds
  * 90 = red
  * 75 = Yellow
  * base = green

---  

![panel-table](https://i.imgur.com/rBU2cJq.png)

The third panel is a table with general jobs info.

* Visualization = Table
* Data source = Prometheus
* Query, switch from builder to code
  `veeam_job_result_info{job="veeam_report"}`
  * Query options > Format = Table<br>
  * Query options > Type = Instant (query button press to show change)
* This results in a table where each job's last result is shown,
  plus labels and their values.<br>
  One could start cleaning it up with a Transform,
  but there are other metrics missing and the time stuff is in absolute values
  instead of X minutes/hours ago.
* So before cleaning much more mess will be added.
* [Rename](https://i.imgur.com/fOGGyW1.gif) the original query
  from `A` to `result`.<br>
  This renaming will be used in all following queries so that the fields
  are distinguishable in transformation later.
* Create following queries, the first line is the new name,
  the second is the query code itself.<br>
  Every query Options are set to **table** and **instant**.
  * `total_size`<br>
    `veeam_job_totalsize_bytes{job="veeam_report"}`
  * `job_runtime`<br>
    `veeam_job_duration_seconds{job="veeam_report"}`
  * `last_job_run`<br>
    `round(time()-veeam_job_end_time_timestamp_seconds{job="veeam_report"})`
  * `last_report`<br>
    `round(time()-push_time_seconds{job="veeam_report"})`
* Now the result is that there are 5 tables, switchable from a drop down menu,
  But they need to be combined in to one table.
* Transform > Join by field > Mode = OUTER; Field = instance
* Now theres one long table with lot of duplication as every query brought 
  labels again. Now to clean it up.
* Transform > Organize fields
  * Hide unwanted fields, rename headers for fields that are kept
  * Hiding anything with number 2, 3, 4, 5 in name works to get bulk of it gone
  * Reorder with drag and drop
* Now to tweak how it all looks and show readable values
* Panel options > Title = empty
* Table > Cell Options > Colored background
* Table > Cell Options > Background display mode = Gradient<br>
  Ignore for now all the colors.
* Standard options > Unit = `seconds (s)`; Decimals = 0<br>
  This makes the three time columns readable.
* Thresholds > delete whatever is there; edit Base to be transparent
* Overrides > Fields with name = Total Size > Add override property >
  Standard options > Unit = bytes(SI)
* Overrides > Fields with name = Result > Value mappings
  * 0 = Successful; Green
  * 1 = Warning; Yellow
  * 2 = Failed; Red
  * -1 = Running; Blue
  * -2 = Disabled | Unscheduled; Grey
* Overrides > Fields with name = Group > Value mappings
  * group name; some color with some transparency to not be too loud
  * group name; some color with some transparency to not be too loud
  * group name; some color with some transparency to not be too loud

----

# googled out shit

* [get repository total size and free size](https://forums.veeam.com/powershell-f26/v11-get-vbrbackuprepository-space-properties-t72415.html)
* https://www.reddit.com/r/Veeam/comments/12a15cu/useful_veeam_toolsscripts/
