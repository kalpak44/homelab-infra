#!/usr/bin/env bash
# Runs once on the build server; everything it leaves behind is in every workspace VM.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# The build server's own first boot may still hold the apt lock.
cloud-init status --wait || true

apt-get update
apt-get -y -o Dpkg::Options::=--force-confold dist-upgrade
apt-get install -y ca-certificates curl unattended-upgrades

# Docker's own repository rather than Ubuntu's docker.io, which lags and has no compose v2.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
# The rootless extras, uidmap and slirp4netns run the agent's own Docker below.
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  docker-ce-rootless-extras uidmap slirp4netns

# live-restore keeps containers running while an unattended upgrade restarts the daemon,
# and the local log driver rotates, so a chatty app cannot fill the disk.
cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "local",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true,
  "no-new-privileges": true
}
JSON
systemctl enable docker.service containerd.service
systemctl restart docker.service

# A VM lives for weeks between snapshot builds, so security fixes and Docker updates
# install on the VM itself.
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
cat > /etc/apt/apt.conf.d/51workspace-docker <<'CONF'
Unattended-Upgrade::Allowed-Origins:: "Docker:${distro_codename}";
CONF

# Fails the build, and so keeps the old snapshot in use, if Docker cannot run a container.
docker run --rm hello-world
docker image rm hello-world
docker compose version

# The harness runs as uid 1000 with this home mounted at the same path, so a bind mount the
# agent asks its Docker for names the same files inside and outside the harness.
useradd --uid 1000 --user-group --create-home --home-dir /home/workspace --shell /usr/sbin/nologin workspace
chmod 0700 /home/workspace
grep -q '^workspace:' /etc/subuid || echo 'workspace:100000:65536' >> /etc/subuid
grep -q '^workspace:' /etc/subgid || echo 'workspace:100000:65536' >> /etc/subgid
# Ubuntu's AppArmor refuses unprivileged user namespaces, which rootless Docker is built on.
if [ ! -e /etc/apparmor.d/usr.bin.rootlesskit ]; then
  cat > /etc/apparmor.d/usr.bin.rootlesskit <<'PROFILE'
abi <abi/4.0>,
include <tunables/global>

/usr/bin/rootlesskit flags=(unconfined) {
  userns,

  include if exists <local/usr.bin.rootlesskit>
}
PROFILE
  apparmor_parser -r /etc/apparmor.d/usr.bin.rootlesskit
fi
# The agent's Docker: rootless, as the workspace user, so what it runs can never reach the
# system daemon the supervisor holds. A user unit under a lingering user manager, because
# rootless containers need the cgroup a user session delegates. Its images live outside the
# home, so a backup of the home never carries them.
install -d -m 0700 -o workspace -g workspace /var/lib/workspace-docker
echo 'd /run/workspace-docker 0700 workspace workspace -' > /etc/tmpfiles.d/workspace-docker.conf
systemd-tmpfiles --create /etc/tmpfiles.d/workspace-docker.conf
cat > /etc/systemd/user/workspace-docker.service <<'UNIT'
[Unit]
Description=Docker for the workspace's agent (rootless)
ConditionUser=workspace

[Service]
Environment=PATH=/usr/bin:/usr/sbin:/bin:/sbin
ExecStart=/usr/bin/dockerd-rootless.sh --data-root /var/lib/workspace-docker/data \
  --host unix:///run/workspace-docker/docker.sock
Delegate=yes
KillMode=mixed
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
UNIT
systemctl --global enable workspace-docker.service
loginctl enable-linger workspace
timeout 60 sh -c 'until [ -S /run/user/1000/bus ]; do sleep 1; done'
systemctl --user -M workspace@ daemon-reload
systemctl --user -M workspace@ start workspace-docker.service
timeout 60 sh -c 'until [ -S /run/workspace-docker/docker.sock ]; do sleep 1; done' || {
  journalctl --user-unit workspace-docker --no-pager; exit 1; }
# Fails the build if the agent's Docker cannot run a container either.
sudo -u workspace DOCKER_HOST=unix:///run/workspace-docker/docker.sock docker run --rm hello-world
sudo -u workspace DOCKER_HOST=unix:///run/workspace-docker/docker.sock docker image rm hello-world
systemctl --user -M workspace@ stop workspace-docker.service

# Pinned to the digest :latest resolves to now, so every VM from this snapshot runs the
# same build until the next one.
supervisor_image=ghcr.io/kalpak44/workspaced-ai-supervisor
docker pull "$supervisor_image:latest"
supervisor="$(docker inspect --format '{{index .RepoDigests 0}}' "$supervisor_image:latest")"
install -d -m 0700 /etc/workspaced /var/lib/workspaced
# Starts only on a VM whose cloud-config wrote its enrollment file, which the build server
# has none of, so the snapshot carries no key and no enrollment.
cat > /etc/systemd/system/workspaced-supervisor.service <<UNIT
[Unit]
Description=workspaced-ai supervisor
Requires=docker.service
Wants=network-online.target user@1000.service
After=docker.service user@1000.service cloud-final.service network-online.target
ConditionPathExists=/etc/workspaced/agent.env

[Service]
# The harness mounts the agent's Docker socket, so it has to exist before the harness starts.
ExecStartPre=/bin/sh -c 'until [ -S /run/workspace-docker/docker.sock ]; do sleep 1; done'
ExecStartPre=-/usr/bin/docker rm -f workspaced-supervisor
# The system socket lets it run the harness; nothing else on the VM gets it.
ExecStart=/usr/bin/docker run --rm --name workspaced-supervisor --network host \
  -v /etc/workspaced:/etc/workspaced -v /var/lib/workspaced:/var/lib/workspaced \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --cap-drop ALL --read-only --security-opt no-new-privileges $supervisor
ExecStop=/usr/bin/docker stop workspaced-supervisor
Restart=always
RestartSec=10
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable workspaced-supervisor.service

# Nothing reaches a VM inbound, so SSH has nothing to serve. Masked rather than removed:
# Packer is connected through it until the build server shuts down.
systemctl mask ssh.service ssh.socket
rm -f /root/.ssh/authorized_keys /etc/ssh/ssh_host_*

# Every VM must boot as a new instance: its own machine id, and cloud-init running again.
cloud-init clean --logs --machine-id
apt-get clean
rm -rf /var/lib/apt/lists/*
journalctl --rotate
journalctl --vacuum-time=1s
