#!/usr/bin/env python3
"""Read-only Docker audit for the sshhole.com OpenSSH/musl finding.

Inspects running containers only. It does not attempt SSH logins, change
container state, or write anything except this script when you save it.
"""

import json
import re
import shutil
import subprocess
import sys


REMOTE = r'''set +e
if ! command -v sshd >/dev/null 2>&1; then
  echo 'SSHD=absent'
  exit 0
fi
echo 'SSHD=present'
sshd_running=no
for comm in /proc/[0-9]*/comm; do
  [ -r "$comm" ] || continue
  IFS= read -r process_name < "$comm"
  if [ "$process_name" = 'sshd' ]; then sshd_running=yes; break; fi
done
echo "SSHD_RUNNING=$sshd_running"
if ls /lib/ld-musl-*.so.1 /lib/ld-musl-*.so 2>/dev/null | grep -q .; then
  echo 'LIBC=musl'
elif ldd --version 2>&1 | grep -qi musl; then
  echo 'LIBC=musl'
else
  echo 'LIBC=other-or-unknown'
fi
echo "VERSION=$(sshd -V 2>&1 | head -n 1)"
CFG=$(sshd -T 2>/dev/null)
if [ -n "$CFG" ]; then
  echo "$CFG" | awk '$1 == "usepam" {print "USEPAM=" $2} $1 == "passwordauthentication" {print "PASSAUTH=" $2}'
else
  echo 'EFFECTIVE_CONFIG=unavailable'
fi
if [ -r /etc/shadow ]; then
  awk -F: 'BEGIN {star=0; real=0} $2 == "*" {star++} $2 ~ /^\$[0-9A-Za-z]+\$/ {real++} END {print "STAR_LOCKED_ACCOUNTS=" star; print "HASHED_PASSWORD_ACCOUNTS=" real}' /etc/shadow
else
  echo 'SHADOW=unreadable'
fi
'''


def docker(args, *, timeout=20):
    return subprocess.run(
        ["docker", *args], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout, check=False
    )


def inspect_container(container_id, name):
    result = docker(["exec", "--user", "0", container_id, "sh", "-c", REMOTE], timeout=30)
    if result.returncode != 0 and not result.stdout.strip():
        return {"name": name, "id": container_id[:12], "status": "inspection-error",
                "detail": result.stderr.strip() or f"docker exec exited {result.returncode}"}
    fields = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields[key] = value

    version_match = re.search(r"OpenSSH_(\d+)\.(\d+)(?:p(\d+))?", fields.get("VERSION", ""))
    patched_release = bool(version_match and tuple(map(int, (version_match.group(1), version_match.group(2), version_match.group(3) or 0))) >= (10, 6, 2))
    if fields.get("SSHD") == "absent":
        status = "no sshd binary"
    elif fields.get("SSHD_RUNNING") != "yes":
        status = "sshd installed but not running; configuration is assessed, but no active sshd process was found"
    elif fields.get("LIBC") != "musl":
        status = "not affected by this finding (libc is not musl, or unknown)"
    elif patched_release:
        status = "OpenSSH version at or above 10.6p2 reported (vendor backports may need package-level confirmation)"
    elif fields.get("USEPAM", "").lower() == "yes":
        status = "not affected by this finding (PAM enabled)"
    elif fields.get("PASSAUTH", "").lower() != "yes":
        status = "mitigated by effective password-authentication setting"
    elif fields.get("STAR_LOCKED_ACCOUNTS", "0").isdigit() and int(fields["STAR_LOCKED_ACCOUNTS"]) > 0 and fields.get("HASHED_PASSWORD_ACCOUNTS", "0").isdigit() and int(fields["HASHED_PASSWORD_ACCOUNTS"]) > 0:
        status = "potentially exposed: all reported prerequisites appear present; verify vendor package backports"
    else:
        status = "potentially exposed: musl, no PAM, and password auth; account state incomplete or prerequisites not confirmed"
    return {"name": name, "id": container_id[:12], "status": status, **fields,
            **({"detail": result.stderr.strip()} if result.stderr.strip() else {})}


def main():
    if not shutil.which("docker"):
        print("Error: docker CLI was not found on PATH.", file=sys.stderr)
        return 2
    try:
        result = docker(["ps", "--format", "{{.ID}}\t{{.Names}}"])
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"Error: could not query Docker: {exc}", file=sys.stderr)
        return 2
    if result.returncode != 0:
        print(f"Error: docker ps failed: {result.stderr.strip()}", file=sys.stderr)
        return 2

    containers = [line.split("\t", 1) for line in result.stdout.splitlines() if "\t" in line]
    report = []
    for container_id, name in containers:
        try:
            report.append(inspect_container(container_id, name))
        except (OSError, subprocess.TimeoutExpired) as exc:
            report.append({"name": name, "id": container_id[:12], "status": "inspection-error", "detail": str(exc)})
    print(json.dumps({"scope": "running Docker containers", "read_only": True, "containers": report}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
