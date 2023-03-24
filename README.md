# Veeam B&R dashboard for prometheus

###### guide-by-example

![logo](https://i.imgur.com/xScE6fL.png)

-----------------

**WORK IN PROGRESS**<br>
**WORK IN PROGRESS**<br>
**WORK IN PROGRESS**

FUck, gonna have to learn more on backup sessions types - 
`windows agen policy` vs `windows agent backup`

cuz what [can happen](https://i.imgur.com/xuIPQaT.png) is that last session job
returned info is on that short little policy shit and the actual backup
can be failing and dashboard would be unaware.<br>
One way to never deal with this is picking Managed by backup server instead of 
Managed by agent...

---------------

# Purpose

Centralized monitoring dashboard for Veeam B&R community edition backup jobs.

* [Veeam Backup & Replication Community Edition](
https://www.veeam.com/virtual-machine-backup-solution-free.html)
* [Prometheus](https://prometheus.io/)
* [Grafana](https://grafana.com/)

A powershell script periodicly runs on machines running Veeam,
gathering information about the backup-jobs using Get-VBRJob cmdlet.
This info gets pushed to a prometheus pushgateway, where it get scraped
in to prometheus. Grafana dashboard then visualizes the gathered information.

![dashboard_pic](https://i.imgur.com/hek3Y7D.png)

# Overview

Components

* machines running Veeam B&R
* scheduled task running powershell script on these machines<br>
  this script is likely the weakest link,
  the least reliable component of the setup
* a dockerhost running containers:
  * promethus
  * pushgateway
  * grafana
  * alertmanager ... to-do 

<details>
<summary><h1>Prometheus and Grafana Setup</h1></summary>

# Files and directory structure

```
/home/
└── ~/
    └── docker/
        └── prometheus/
            │
            ├── grafana/
            ├── grafana-data/
            ├── prometheus-data/
            ├── .env
            ├── docker-compose.yml
            └── prometheus.yml
```

* `grafana/` - a directory containing grafanas configs and dashboards
* `grafana-data/` - a directory where grafana stores its data
* `prometheus-data/` - a directory where prometheus stores its database and data
* `.env` - a file containing environment variables for docker compose
* `docker-compose.yml` - a docker compose file, telling docker how to run the containers
* `prometheus.yml` - a configuration file for prometheus

The 3 files must be provided.</br>
The directories are created by docker compose on the first run.

# docker-compose

Three containers to spin up.</br>

* **Prometheus** - prometheus server, pulling, storing, evaluating metrics
* **Pushgateway** - service ready to receive pushed information at an open port
* **Grafana** - web UI visualization of the collected metrics
  in nice dashboards

`docker-compose.yml`
```yml
services:

  # MONITORING SYSTEM AND THE METRICS DATABASE
  prometheus:
    image: prom/prometheus:v2.41.0
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
      - 9090:9090

  # WEB BASED UI VISUALISATION OF THE METRICS
  grafana:
    image: grafana/grafana:9.3.2
    container_name: grafana
    hostname: grafana
    restart: unless-stopped
    env_file: .env
    user: root
    volumes:
      - ./grafana_data:/var/lib/grafana
      - ./grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/provisioning/datasources:/etc/grafana/provisioning/datasources
    ports:
      - 3000:3000

  pushgateway:
    image: prom/pushgateway:v1.5.1
    container_name: pushgateway
    hostname: pushgateway
    restart: unless-stopped
    command:
      - '--web.enable-admin-api'    
    ports:
      - 9091:9091

networks:
  default:
    name: $DOCKER_MY_NETWORK
    external: true
```

`.env`

```bash
# GENERAL
MY_DOMAIN=example.com
DOCKER_MY_NETWORK=caddy_net
TZ=Europe/Bratislava

# GRAFANA
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=admin
GF_USERS_ALLOW_SIGN_UP=false

# DATE FORMATS SWITCHED TO THEN NAMES OF THE DAYS OF THE WEEK
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

* /prometheus/**prometheus.yml**

[Official documentation.](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)

A config file for prometheus, bind mounted in to prometheus container.

Of note is
**honor_labels** set [to true,](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#scrape_config)
which makes sure that **conflicting labels**, like `job` label, set during push
is kept over label set in `prometheus.yml` for the scrape job.

`prometheus.yml`
```yml
global:
  scrape_interval:     15s
  evaluation_interval: 15s

# A scrape configuration containing exactly one endpoint to scrape.
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

### testing how to push data to pushgateway

* metrics must be floats
* naming [convention](https://prometheus.io/docs/practices/naming/) is to end the metric names with units
* for strings, labels passed in url are used 

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

Windows by default does not allow execution of powershell scripts,
got to `Set-ExecutionPolicy RemoteSigned` in powershell console.

Veeam offers [many cmdlets](https://helpcenter.veeam.com/docs/backup/powershell/cmdlets.html) to use with B&R installation.

* [Get-VBRJob](https://helpcenter.veeam.com/docs/backup/powershell/get-vbrjob.html)<br>
  is the only one used in the script. Not all info for all type of jobs is available.
  But enough for dashboard to visualize current status.
* [Get-VBRBackup](https://helpcenter.veeam.com/docs/backup/powershell/get-vbrbackup.html)<br>
  not used, but played with to get better size and repository info,
  but does not seem to work very well for many jobs
* [Get-VBRBackupSession](https://helpcenter.veeam.com/docs/backup/powershell/get-vbrbackupsession.html)<br>
  not used, but played with to get better info on why job ended with warning or fail

The script itself is pretty readable and comes with comments.

It started being pretty clean.
But with actual use there were errors and missing backups when values queried were null.
And so the script becomes more cluttered with checks if data exists when querying.<br>
Ideally more work should be done on this data validation for better reliability,
to really check every single queried value... but maybe later...  

### DEPLOY.cmd file

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
* DEPLOY.cmd - copies / overwrites-if-newer veeam_prometheus_info_push.ps1 in to C:\Scripts
* DEPLOY.cmd - imports taskscheduler xml task named veeam_prometheus_info_push
* TASKSCHEDULER - the task executes every hour with random delay of 30 seconds
* TASKSCHEDULER - runs with the highest privileges as user - SYSTEM (S-1-5-18)

# Pushgateway

![pic_pushgateway](https://i.imgur.com/4GZIu8g.png)

Ideally one uses a subdomain and https for pushgateway, for that:

* have subdomain `push.example.com` and DNS record aiming at the servers public IP
* caddy runs as reverse proxy, means it is completely in charge of traffic
  coming on 80 and 443.<br>
  The rule from the reverse proxy section in this Readme applies,
  so if something comes at `push.example.com` it gets redirected to <dockerhost>:9091
* the `$base_url` in the script is `https://push.example.com`
* the script contains a line at the begging to switch to TLS 1.2 from powershells
  default 1.0
* should now work

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
```INI
[Unit]
Description=wipe clean prometheus pushgateway

[Service]
Type=simple
ExecStart=curl -X PUT https://push.example.com/api/v1/admin/wipe
```

`pushgateway_wipe.timer`
```INI
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

To query something just write plain metrics name, like `veeam_job_result`.
But in the table tab it shows you by default only the result from a recent
time window. You can switch to what date you want query too apply,
or switch to graph view and set range to few weeks.

More targeted query, with the use of regex, signified by `=~`

  * `veeam_job_result{instance=~"Backup Copy Job.*"}`

To delete all metrics on prometheus

  * `curl -X POST -g 'http://10.0.19.4:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~".*"}'`

To delete metrics based off instance or group

* `curl -X POST -g 'https://prom.example.com/api/v1/admin/tsdb/delete_series?match[]={instance=~"^Backup.Copy.Job.*"}'`
* `curl -X POST -g 'https://prom.example.com/api/v1/admin/tsdb/delete_series?match[]={group=~"cocacola"}'`

Theres no white space in the query, so dots are used.

# Grafana dashboads

![panel-status-history](https://i.imgur.com/okwj9hJ.png)

First panel is for seeing last X days and result of backups, at quick glance

* new dashboard > new panel
* status history
* select labels job = veeam_report; select metric - veeam_job_result
* query options - min interval 1m, or 10m, or 1h, or 1d<br>
  this value sets the size of rectangle in status history panel
* transform - regex by name - `.+instance="([^"]*).*`
* panel title - Veeam History
* status history > show values - never
* Value mapping and Thresholds
  * 0 - green - Successful
  * 1 - yellow - Warning
  * 2 - red - Failed
  * -1 - blue - running
  * -2 - black - Disabled | Unscheduled

![panel-table](https://i.imgur.com/THUmrWq.png)

Second panel is with more info, the most important is "Last Report"

* new panel
* table
* select labels job = veeam_report; select metric - push_time_seconds<br>
  switch from builder to code and `round(time()-push_time_seconds{job="veeam_report"})`<br>
* options - format - table; type - instant;  
* rename query from $A to push_time_seconds
* new query
* select labels job = veeam_report; select metric - veeam_job_duration
* options - format - table; type - instant
* rename query from $A to veeam_job_duration
* new query
* select labels job = veeam_report; select metric - veeam_job_totalsize
* options - format - table; type - instant;
* rename query from $A to veeam_job_totalsize
* transform - outer join - field name = instance
* transform - organize fields - hide time and any other useless columns, rename headers
* table - standard options - units - seconds; decimals - 0
* override - fields with names - size - standard option - units - bytes(SI)


-----

deletion of all data on prometheus and on pushgateway

its useful for learning, but requires opening API in the compose file
so if not in use remove lines containing `- '--web.enable-admin-api'`
      
* `curl -X POST -g 'http://10.0.19.4:9090/api/v1/admin/tsdb/delete_series?match[]={__name__=~".*"}'`
* `curl -X PUT 10.0.19.4:9091/api/v1/admin/wipe`

