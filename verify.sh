#!/usr/bin/env bash
# Verify both walls are active. Run the KVM probe with sudo.
set -u
fail=0

echo "== Docker =="
if docker info 2>/dev/null | grep -qiE 'Cannot connect'; then
    echo "docker daemon not running (skipping probe)"
else
    img=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | head -1)
    if [ -z "$img" ]; then
        echo "no local image to probe with; check config instead:"
        cat /etc/docker/daemon.json 2>/dev/null || echo "MISSING /etc/docker/daemon.json"
    else
        docker run --rm --entrypoint sh "$img" -c \
          'grep Cpus_allowed_list /proc/self/status'
    fi
fi

echo "== systemd slice configs =="
for u in docker.slice machine.slice; do
    printf '%-14s AllowedCPUs=%s\n' "$u" \
      "$(systemctl show -p AllowedCPUs --value $u)"
done

echo "== KVM (machine.slice) =="
if [ "$(id -u)" -eq 0 ]; then
    systemd-run --slice=machine.slice --scope sh -c \
      'grep Cpus_allowed_list /proc/self/status' | tail -1
else
    echo "re-run with sudo for a live machine.slice probe"
fi
