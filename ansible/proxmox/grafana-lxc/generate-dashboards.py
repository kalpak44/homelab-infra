#!/usr/bin/env python3
# Writes the Grafana dashboards under roles/grafana/files/. Edit this, rerun it, and commit
# its output: the JSON is generated and never edited by hand.
#
#   python3 ansible/proxmox/grafana-lxc/generate-dashboards.py
#
# host.json and host-proxmox.json are templates: the role writes one copy per inventory
# host, with __HOST__ replaced, so a new LXC or VM gets its own board with no edit here.
import json
import pathlib

OUT = pathlib.Path(__file__).resolve().parent / "roles/grafana/files"
DS = {"type": "prometheus", "uid": "prometheus"}

FS_REAL = 'fstype=~"ext4|xfs|btrfs|zfs",mountpoint!~"/boot.*"'
# Container and pod interfaces carry traffic the physical or bridge interface already
# counts, so including them doubles every byte.
NET_REAL = 'device!~"lo|veth.*|fwbr.*|fwln.*|fwpr.*|tap.*|cni.*|flannel.*|docker.*|br-.*"'


class Board:
    def __init__(self):
        self.panels = []
        self.y = 0
        self._id = 0

    def add(self, panel, w, h, x=0, newline=False):
        self._id += 1
        panel["id"] = self._id
        panel["gridPos"] = {"h": h, "w": w, "x": x, "y": self.y}
        self.panels.append(panel)
        if newline:
            self.y += h

    def row(self, title):
        self.add({"type": "row", "title": title, "collapsed": False, "panels": []}, 24, 1,
                 newline=True)


def target(expr, ref="A", legend=None, instant=False, fmt=None):
    t = {"datasource": DS, "expr": expr, "refId": ref, "editorMode": "code"}
    if legend:
        t["legendFormat"] = legend
    if instant:
        t["instant"], t["range"] = True, False
    if fmt:
        t["format"] = fmt
    return t


def steps(warn, crit):
    return {"mode": "absolute", "steps": [{"color": "green", "value": None},
                                          {"color": "orange", "value": warn},
                                          {"color": "red", "value": crit}]}


BLUE = {"mode": "absolute", "steps": [{"color": "blue", "value": None}]}


def stat(title, expr, unit, thresholds=BLUE, desc=None, gauge=False, decimals=None):
    d = {"unit": unit, "thresholds": thresholds}
    if gauge:
        d["min"], d["max"] = 0, 100
    if decimals is not None:
        d["decimals"] = decimals
    p = {"type": "gauge" if gauge else "stat", "title": title, "datasource": DS,
         "targets": [target(expr, instant=True)],
         "fieldConfig": {"defaults": d, "overrides": []},
         "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                     "colorMode": "value", "graphMode": "none", "textMode": "value",
                     "showThresholdMarkers": True}}
    if desc:
        p["description"] = desc
    return p


def series(title, targets, unit, maxv=None, desc=None, stack=False, fill=10):
    d = {"unit": unit, "custom": {"lineWidth": 1, "fillOpacity": fill, "showPoints": "never",
                                  "stacking": {"mode": "normal" if stack else "none"}}}
    if maxv is not None:
        d["min"], d["max"] = 0, maxv
    p = {"type": "timeseries", "title": title, "datasource": DS, "targets": targets,
         "fieldConfig": {"defaults": d, "overrides": []},
         "options": {"legend": {"displayMode": "table", "placement": "bottom",
                                "calcs": ["lastNotNull", "max"]},
                     "tooltip": {"mode": "multi", "sort": "desc"}}}
    if desc:
        p["description"] = desc
    return p


def table(title, targets, rename, order, overrides, desc, sort, hidden=()):
    exclude = {"Time": True}
    exclude.update({h: True for h in hidden})
    return {"type": "table", "title": title, "description": desc, "datasource": DS,
            "targets": targets,
            "transformations": [
                {"id": "merge", "options": {}},
                {"id": "organize", "options": {"excludeByName": exclude,
                                               "renameByName": rename, "indexByName": order}}],
            "options": {"showHeader": True, "cellHeight": "sm", "sortBy": sort,
                        "footer": {"show": False}},
            "fieldConfig": {"defaults": {"custom": {"align": "auto", "filterable": True}},
                            "overrides": overrides}}


def gauge_cell(field, warn, crit):
    return {"matcher": {"id": "byName", "options": field}, "properties": [
        {"id": "unit", "value": "percent"}, {"id": "min", "value": 0},
        {"id": "max", "value": 100}, {"id": "decimals", "value": 1},
        {"id": "thresholds", "value": steps(warn, crit)},
        {"id": "custom.cellOptions",
         "value": {"type": "gauge", "mode": "basic", "valueDisplayMode": "text"}}]}


def unit_cell(field, unit, decimals=1):
    return {"matcher": {"id": "byName", "options": field}, "properties": [
        {"id": "unit", "value": unit}, {"id": "decimals", "value": decimals}]}


def thin_pool(b):
    tp = "lvm_thin_pool"
    b.row("Storage pool (local-lvm)")
    b.add(stat("Pool data used", f"100 * max({tp}_data_used_ratio)", "percent", steps(75, 90),
               "Every guest disk lives in this pool. When it fills, every guest writing to it "
               "stalls at once.", gauge=True), 6, 6, 0)
    b.add(stat("Pool metadata used", f"100 * max({tp}_metadata_used_ratio)", "percent",
               steps(70, 85), "The pool also stops when its metadata fills, however much data "
               "space is left. Snapshots consume it fastest.", gauge=True), 6, 6, 6)
    b.add(stat("Pool free", f"max({tp}_size_bytes * (1 - {tp}_data_used_ratio))", "bytes",
               desc="Data space not yet written to by any guest."), 6, 6, 12)
    b.add(stat("Provisioned to guests", f"100 * max({tp}_provisioned_bytes / {tp}_size_bytes)",
               "percent", steps(90, 100), "Sum of the guests' virtual disk sizes against the "
               "pool. Above 100% the pool is overcommitted: it can fill while every guest still "
               "reports free space."), 6, 6, 18, newline=True)
    b.add(series("Pool usage", [target(f"100 * max({tp}_data_used_ratio)", "A", "data"),
                                target(f"100 * max({tp}_metadata_used_ratio)", "B", "metadata")],
                 "percent", 100), 24, 7, newline=True)


def dashboard(uid, title, desc, panels, tags, templating=None, links=None):
    return {"uid": uid, "title": title, "description": desc, "tags": tags,
            "timezone": "browser", "schemaVersion": 39, "version": 1, "editable": False,
            "refresh": "1m", "time": {"from": "now-24h", "to": "now"},
            "templating": {"list": templating or []}, "links": links or [], "panels": panels}


HOSTS_LINK = [{"title": "All hosts", "type": "link", "url": "/d/homelab-hosts",
               "icon": "dashboard", "targetBlank": False}]


# --- One host ---------------------------------------------------------------------------

def host_board(proxmox):
    sel = 'job=~"hosts|node",host="__HOST__"'
    fs = f"{sel},{FS_REAL}"
    net = f"{sel},{NET_REAL}"
    b = Board()

    b.row("Now")
    b.add(stat("CPU busy", f'100 * (1 - avg(rate(node_cpu_seconds_total{{{sel},mode="idle"}}[5m])))',
               "percent", steps(70, 90), "Last 5 minutes, across this host's CPUs.", gauge=True),
          4, 6, 0)
    b.add(stat("Memory used", f"100 * (1 - max(node_memory_MemAvailable_bytes{{{sel}}}) / "
               f"max(node_memory_MemTotal_bytes{{{sel}}}))", "percent", steps(80, 92),
               "Memory the kernel could not hand to a new process without swapping. Page cache "
               "it can drop does not count.", gauge=True), 4, 6, 4)
    b.add(stat("Disk used", f"100 * (1 - sum(node_filesystem_avail_bytes{{{fs}}}) / "
               f"sum(node_filesystem_size_bytes{{{fs}}}))", "percent", steps(75, 90),
               "Every real filesystem on this host together; the Disk space panel splits them.",
               gauge=True), 4, 6, 8)
    b.add(stat("CPUs", f'count(node_cpu_seconds_total{{{sel},mode="idle"}})', "none",
               desc="What this guest is given. lxcfs reports a container's own limit.",
               decimals=0), 3, 3, 12)
    b.add(stat("RAM", f"max(node_memory_MemTotal_bytes{{{sel}}})", "bytes", decimals=1),
          3, 3, 15)
    b.add(stat("Disk", f"sum(node_filesystem_size_bytes{{{fs}}})", "bytes", decimals=1),
          3, 3, 18)
    b.add(stat("Disk free", f"sum(node_filesystem_avail_bytes{{{fs}}})", "bytes", decimals=1),
          3, 3, 21)
    b.y += 3
    b.add(stat("Load (5m)", f"max(node_load5{{{sel}}})", "none", decimals=2,
               desc="A container reports the node's load average, not its own."), 3, 3, 12)
    b.add(stat("Memory free", f"max(node_memory_MemAvailable_bytes{{{sel}}})", "bytes",
               decimals=1), 3, 3, 15)
    b.add(stat("Swap used", f"max(node_memory_SwapTotal_bytes{{{sel}}} - "
               f"node_memory_SwapFree_bytes{{{sel}}})", "bytes", decimals=1), 3, 3, 18)
    b.add(stat("Up for", f"time() - max(node_boot_time_seconds{{{sel}}})", "s", decimals=0,
               desc="A container reports the node's boot time, not its own start."), 3, 3, 21,
          newline=True)

    b.row("CPU and memory")
    b.add(series("CPU", [target(
        f"100 * sum by (mode) (rate(node_cpu_seconds_total{{{sel},mode!=\"idle\"}}[$__rate_interval])) "
        f"/ scalar(count(node_cpu_seconds_total{{{sel},mode=\"idle\"}}))", "A", "{{mode}}")],
        "percent", 100, "Share of this host's CPUs, by what they were busy with.", stack=True,
        fill=40), 12, 8, 0)
    b.add(series("Load", [target(f"max(node_load1{{{sel}}})", "A", "1m"),
                          target(f"max(node_load5{{{sel}}})", "B", "5m"),
                          target(f"max(node_load15{{{sel}}})", "C", "15m"),
                          target(f'count(node_cpu_seconds_total{{{sel},mode="idle"}})', "D", "CPUs")],
                 "none", None, "Sustained load above the CPU line means work is queueing."),
          12, 8, 12, newline=True)
    b.add(series("Memory", [
        target(f"max(node_memory_MemTotal_bytes{{{sel}}}) - max(node_memory_MemAvailable_bytes{{{sel}}})",
               "A", "used"),
        target(f"max(node_memory_Cached_bytes{{{sel}}}) + max(node_memory_Buffers_bytes{{{sel}}})",
               "B", "cache and buffers"),
        target(f"max(node_memory_MemTotal_bytes{{{sel}}})", "C", "total")],
        "bytes", None, "Used excludes cache the kernel drops on demand, which is why used and "
        "cache can together exceed what looks free."), 12, 8, 0)
    b.add(series("Swap", [
        target(f"max(node_memory_SwapTotal_bytes{{{sel}}} - node_memory_SwapFree_bytes{{{sel}}})",
               "A", "used"),
        target(f"max(node_memory_SwapTotal_bytes{{{sel}}})", "B", "total")], "bytes"),
        12, 8, 12, newline=True)

    b.row("Disk")
    b.add(table("Disk space", [
        target(f"max by (mountpoint) (node_filesystem_size_bytes{{{fs}}})", "A", instant=True, fmt="table"),
        target(f"max by (mountpoint) (node_filesystem_size_bytes{{{fs}}} - node_filesystem_avail_bytes{{{fs}}})",
               "B", instant=True, fmt="table"),
        target(f"max by (mountpoint) (node_filesystem_avail_bytes{{{fs}}})", "C", instant=True, fmt="table"),
        target(f"100 * (1 - max by (mountpoint) (node_filesystem_avail_bytes{{{fs}}}) / "
               f"max by (mountpoint) (node_filesystem_size_bytes{{{fs}}}))", "D", instant=True, fmt="table")],
        {"mountpoint": "Mount", "Value #A": "Size", "Value #B": "Used", "Value #C": "Free",
         "Value #D": "Used %"},
        {"mountpoint": 0, "Value #A": 1, "Value #B": 2, "Value #C": 3, "Value #D": 4},
        [gauge_cell("Used %", 75, 90), unit_cell("Size", "bytes"), unit_cell("Used", "bytes"),
         unit_cell("Free", "bytes")],
        "Free is what an unprivileged process can still write, so it already excludes the "
        "space ext4 reserves for root.", [{"displayName": "Used %", "desc": True}]),
        12, 8, 0)
    b.add(series("Disk used", [target(
        f"max by (mountpoint) (node_filesystem_size_bytes{{{fs}}} - node_filesystem_avail_bytes{{{fs}}})",
        "A", "{{mountpoint}}")], "bytes"), 12, 8, 12, newline=True)
    b.add(series("Disk I/O", [
        target(f"sum(rate(node_disk_read_bytes_total{{{sel}}}[$__rate_interval]))", "A", "read"),
        target(f"-sum(rate(node_disk_written_bytes_total{{{sel}}}[$__rate_interval]))", "B", "write")],
        "Bps", None, "Write is drawn below zero. A container sees the node's disks, so this is "
        "the whole node's I/O there."), 12, 8, 0)
    b.add(series("Network", [
        target(f"sum(rate(node_network_receive_bytes_total{{{net}}}[$__rate_interval]))", "A", "in"),
        target(f"-sum(rate(node_network_transmit_bytes_total{{{net}}}[$__rate_interval]))", "B", "out")],
        "Bps", None, "Out is drawn below zero."), 12, 8, 12, newline=True)

    if proxmox:
        thin_pool(b)

    return dashboard("host-__HOST__", "__HOST__",
                     "CPU, memory, disk and network of __HOST__.", b.panels,
                     ["homelab", "host"], links=HOSTS_LINK)


# --- Every host ---------------------------------------------------------------------------

def overview():
    sel = 'job=~"hosts|node"'
    fs = f"{sel},{FS_REAL}"
    b = Board()

    b.row("Hosts")
    host_link = {"matcher": {"id": "byName", "options": "Host"}, "properties": [
        {"id": "links", "value": [{"title": "Open ${__value.raw}",
                                   "url": "/d/host-${__value.raw}"}]}]}
    b.add(table("Hosts", [
        target(f'max by (host, kind) (node_uname_info{{{sel},kind!=""}})', "A", instant=True, fmt="table"),
        target(f'count by (host) (node_cpu_seconds_total{{{sel},mode="idle"}})', "B", instant=True, fmt="table"),
        target(f'100 * (1 - avg by (host) (rate(node_cpu_seconds_total{{{sel},mode="idle"}}[5m])))',
               "C", instant=True, fmt="table"),
        target(f"max by (host) (node_memory_MemTotal_bytes{{{sel}}})", "D", instant=True, fmt="table"),
        target(f"100 * (1 - max by (host) (node_memory_MemAvailable_bytes{{{sel}}}) / "
               f"max by (host) (node_memory_MemTotal_bytes{{{sel}}}))", "E", instant=True, fmt="table"),
        target(f"sum by (host) (node_filesystem_size_bytes{{{fs}}})", "F", instant=True, fmt="table"),
        target(f"sum by (host) (node_filesystem_size_bytes{{{fs}}} - node_filesystem_avail_bytes{{{fs}}})",
               "G", instant=True, fmt="table"),
        target(f"sum by (host) (node_filesystem_avail_bytes{{{fs}}})", "H", instant=True, fmt="table"),
        target(f"100 * (1 - sum by (host) (node_filesystem_avail_bytes{{{fs}}}) / "
               f"sum by (host) (node_filesystem_size_bytes{{{fs}}}))", "I", instant=True, fmt="table")],
        {"host": "Host", "kind": "Kind", "Value #B": "CPUs", "Value #C": "CPU %",
         "Value #D": "RAM total", "Value #E": "RAM used %", "Value #F": "Disk total",
         "Value #G": "Disk used", "Value #H": "Disk free", "Value #I": "Disk used %"},
        {"host": 0, "kind": 1, "Value #B": 2, "Value #C": 3, "Value #D": 4, "Value #E": 5,
         "Value #F": 6, "Value #G": 7, "Value #H": 8, "Value #I": 9},
        [host_link, gauge_cell("CPU %", 70, 90), gauge_cell("RAM used %", 80, 92),
         gauge_cell("Disk used %", 75, 90), unit_cell("RAM total", "bytes"),
         unit_cell("Disk total", "bytes"), unit_cell("Disk used", "bytes"),
         unit_cell("Disk free", "bytes"), unit_cell("CPUs", "none", 0)],
        "Click a host for its own dashboard. CPUs and RAM are what each guest is given, not the "
        "node's: lxcfs reports a container's own limits. Disk sums every real filesystem on "
        "the host. CPU % is the last 5 minutes.",
        [{"displayName": "Host", "desc": False}], hidden=("Value #A",)),
        24, 14, newline=True)

    b.add(table("Filesystems", [
        target(f"max by (host, mountpoint) (node_filesystem_size_bytes{{{fs}}})", "A", instant=True, fmt="table"),
        target(f"max by (host, mountpoint) (node_filesystem_size_bytes{{{fs}}} - node_filesystem_avail_bytes{{{fs}}})",
               "B", instant=True, fmt="table"),
        target(f"max by (host, mountpoint) (node_filesystem_avail_bytes{{{fs}}})", "C", instant=True, fmt="table"),
        target(f"100 * (1 - max by (host, mountpoint) (node_filesystem_avail_bytes{{{fs}}}) / "
               f"max by (host, mountpoint) (node_filesystem_size_bytes{{{fs}}}))", "D", instant=True, fmt="table")],
        {"host": "Host", "mountpoint": "Mount", "Value #A": "Size", "Value #B": "Used",
         "Value #C": "Free", "Value #D": "Used %"},
        {"host": 0, "mountpoint": 1, "Value #A": 2, "Value #B": 3, "Value #C": 4, "Value #D": 5},
        [host_link, gauge_cell("Used %", 75, 90), unit_cell("Size", "bytes"),
         unit_cell("Used", "bytes"), unit_cell("Free", "bytes")],
        "One row per real filesystem, fullest first.",
        [{"displayName": "Used %", "desc": True}]), 24, 12, newline=True)

    thin_pool(b)

    b.row("All hosts over time")
    b.add(series("CPU busy", [target(
        f'100 * (1 - avg by (host) (rate(node_cpu_seconds_total{{{sel},mode="idle"}}[$__rate_interval])))',
        "A", "{{host}}")], "percent", 100), 8, 9, 0)
    b.add(series("Memory used", [target(
        f"100 * (1 - max by (host) (node_memory_MemAvailable_bytes{{{sel}}}) / "
        f"max by (host) (node_memory_MemTotal_bytes{{{sel}}}))", "A", "{{host}}")],
        "percent", 100), 8, 9, 8)
    b.add(series("Disk used", [target(
        f"100 * (1 - max by (host, mountpoint) (node_filesystem_avail_bytes{{{fs}}}) / "
        f"max by (host, mountpoint) (node_filesystem_size_bytes{{{fs}}}))", "A",
        "{{host}} {{mountpoint}}")], "percent", 100), 8, 9, 16, newline=True)

    return dashboard("homelab-hosts", "Homelab hosts",
                     "CPU, memory and disk of every LXC, VM and the Proxmox node.", b.panels,
                     ["homelab", "node_exporter"],
                     links=[{"title": "Hosts", "type": "dashboards", "tags": ["host"],
                             "asDropdown": True, "icon": "external link"}])


# --- Service health ---------------------------------------------------------------------

UP_DOWN = [{"type": "value", "options": {
    "1": {"text": "UP", "color": "green", "index": 0},
    "0": {"text": "DOWN", "color": "red", "index": 1}}}]


def timeline(title, expr, legend, desc):
    return {"type": "state-timeline", "title": title, "description": desc, "datasource": DS,
            "targets": [target(expr, "A", legend)],
            "fieldConfig": {"defaults": {"mappings": UP_DOWN, "color": {"mode": "thresholds"},
                                         "thresholds": {"mode": "absolute", "steps": [
                                             {"color": "red", "value": None},
                                             {"color": "green", "value": 1}]},
                                         "custom": {"fillOpacity": 80, "lineWidth": 0}},
                            "overrides": []},
            "options": {"showValue": "never", "mergeValues": True, "rowHeight": 0.8,
                        "alignValue": "left", "legend": {"showLegend": False},
                        "tooltip": {"mode": "single"}}}


def services():
    b = Board()
    b.add(timeline("Services", "min by (service) (probe_success{job=\"probes\"})", "{{service}}",
                   "One row per service, down while any of its checks fails."),
          24, 8, newline=True)
    b.add(timeline("Checks", "probe_success{job=\"probes\"}", "{{service}} {{probe}} {{instance}}",
                   "Every check on its own row, to see which one took a service down."),
          24, 8, newline=True)
    cert = stat("Certificate expires in",
                "min by (service, instance) ((probe_ssl_earliest_cert_expiry{job=\"probes\"} "
                "- time()) / 86400)", "d", {"mode": "absolute", "steps": [
                    {"color": "red", "value": None}, {"color": "orange", "value": 7},
                    {"color": "green", "value": 14}]},
                "Days until the earliest certificate in the chain expires. certbot renews at "
                "30 days, so anything under that means renewal is failing.", decimals=0)
    cert["targets"][0]["legendFormat"] = "{{instance}}"
    cert["options"]["textMode"] = "value_and_name"
    b.add(cert, 8, 8, 0)
    b.add(series("Response time", [target("probe_duration_seconds{job=\"probes\"}", "A",
                                          "{{service}} {{probe}}")], "s"), 16, 8, 8,
          newline=True)
    return dashboard("homelab-services", "Service health",
                     "Whether each service answers, probed from Prometheus by blackbox_exporter.",
                     b.panels, ["homelab", "blackbox"])


# --- Traffic ------------------------------------------------------------------------------

REQ = 'traefik_client_requests_total{job="traefik-requests"}'
ERR = 'traefik_client_requests_total{job="traefik-requests",status=~"[45].."}'


def top_table(title, by, field, desc):
    return table(title, [target(f"sort_desc(sum by ({by}) (increase({REQ}[$__range])))", "A",
                                instant=True, fmt="table")],
                 {by: field, "Value": "Requests"}, {by: 0, "Value": 1},
                 [unit_cell("Requests", "short", 0)], desc,
                 [{"displayName": "Requests", "desc": True}])


def traffic():
    rate = f"rate({REQ}[$__rate_interval])"
    b = Board()
    b.add(series("Requests by domain", [target(f"sum by (host) ({rate})", "A", "{{host}}")],
                 "reqps", stack=True, fill=30,
                 desc="Every request Traefik served, stacked by the Host header. A spike shows "
                      "which domain it landed on."), 24, 10, newline=True)
    b.add(series("Public and private", [target(f"sum by (entrypoint) ({rate})", "A",
                                               "{{entrypoint}}")], "reqps"), 12, 8, 0)
    b.add(series("Errors by domain", [target(f"sum by (host) (rate({ERR}[$__rate_interval]))",
                                             "A", "{{host}}")], "reqps",
                 desc="4xx and 5xx only. Scanners show up here as 403s and 404s."), 12, 8, 12,
          newline=True)
    b.add(top_table("Top domains", "host", "Domain", "Requests per domain over the time range."),
          12, 10, 0)
    b.add(top_table("Top clients", "client_ip", "Client",
                    "Requests per source address over the time range. Public traffic arrives "
                    "through the tunnel with the visitor's address."), 12, 10, 12, newline=True)
    return dashboard("homelab-traffic", "Traffic",
                     "Requests through Traefik by domain, entrypoint, status and client.",
                     b.panels, ["homelab", "traefik"])


def write(path, board):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(board, indent=2) + "\n")
    print(f"{path.relative_to(OUT.parent.parent.parent.parent.parent)} {len(board['panels'])} panels")


write(OUT / "dashboards/hosts.json", overview())
write(OUT / "dashboards/services.json", services())
write(OUT / "dashboards/traffic.json", traffic())
write(OUT / "host-dashboards/host.json", host_board(proxmox=False))
write(OUT / "host-dashboards/host-proxmox.json", host_board(proxmox=True))
