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
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

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
After=docker.service cloud-final.service network-online.target
Wants=network-online.target
ConditionPathExists=/etc/workspaced/agent.env

[Service]
ExecStartPre=-/usr/bin/docker rm -f workspaced-supervisor
ExecStart=/usr/bin/docker run --rm --name workspaced-supervisor --network host \
  -v /etc/workspaced:/etc/workspaced -v /var/lib/workspaced:/var/lib/workspaced \
  --cap-drop ALL --read-only --security-opt no-new-privileges $supervisor
ExecStop=/usr/bin/docker stop workspaced-supervisor
Restart=always
RestartSec=10

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
