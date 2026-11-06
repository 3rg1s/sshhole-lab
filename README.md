<p align="center">
  <img src="assets/sshhole-lab.svg" alt="sshhole-lab logo" width="520">
</p>

<h1 align="center">sshhole-lab</h1>

<p align="center">
  A contained Docker demonstration of an OpenSSH and musl password-authentication issue.
</p>

<p align="center">
  <img alt="Docker Compose" src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white">
  <img alt="OpenSSH 10.2p1 lab" src="https://img.shields.io/badge/OpenSSH-10.2p1-orange">
  <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-green.svg">
</p>

A local-only Docker lab and read-only container audit for the OpenSSH/musl password-authentication issue described by [sshhole.com](https://sshhole.com/).

> **For authorized local research and education only.** The image intentionally builds an affected upstream OpenSSH release with password authentication enabled. Keep it on loopback and shut it down when finished.

## Contents

- `Dockerfile` — builds OpenSSH 10.2p1 against Alpine/musl with PAM disabled; verifies the upstream source archive checksum.
- `sshd_config` — enables password authentication for the disposable lab account.
- `compose.yaml` — runs the SSH service on loopback in a private Docker network, with no host mounts.
- `check_sshhole.py` — read-only heuristic audit of running Docker containers.
- `verify-lab.sh` — optional isolated Docker client that checks the lab behavior using a 300-character password.

## What this repo demonstrates

- A Docker-only audit that checks running containers for relevant sshd configuration and account indicators.
- A deliberately vulnerable OpenSSH 10.2p1 lab image built against musl with PAM disabled.
- A manual SSH test against the lab, bound to loopback only (port `2222` by default; configurable).

The audit is a heuristic, not a vulnerability verdict. Vendors may backport fixes without changing the upstream version string. Review the installed package revision and vendor advisory before treating a result as confirmed. Its current account checks summarize `/etc/shadow`; directory accounts without a shadow entry are not fully characterized by those counters.

## Safety and scope

The compose file publishes the SSH port only on the loopback interface. The service is attached to an internal Docker network and has no host filesystem mounts. Do not change the bind address to `0.0.0.0` or expose this lab to a network. The audit only inspects running Docker containers; it does not alter them. It needs Docker access and runs `docker exec` as root inside each running container to read sshd settings and account metadata.

## Build and run

Requires Docker Compose and network access during image build to fetch the pinned OpenSSH source release. The archive is checked against the SHA256 published in the [OpenSSH release notes](https://www.openssh.org/releasenotes.html). The Alpine base tag receives upstream updates; this is a behavior demonstration, not a reproducible system image.

```sh
docker compose build
docker compose up -d
```

If local port `2222` is already in use, choose another loopback port (for example `2223`):

```sh
export SSHOLE_HOST_PORT=2223
docker compose up -d
```

Connect to the intentionally vulnerable, disposable lab:

```sh
ssh -p "${SSHOLE_HOST_PORT:-2222}" \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  auditdirectory@127.0.0.1
```

The lab creates the locked `auditdirectory` account and a separate local SHA-512 password hash to supply the salt path involved in the finding. `AllowUsers` restricts SSH access to `auditdirectory`. In the password prompt, use a 300-character string to reproduce the local behavior. The lab is disposable; do not reuse real credentials. Stop the lab with:

```sh
docker compose down
```

This stops and removes only this Compose project's container and private Docker network. It does not remove the built image or touch host files. It will not stop separately created containers.

### Verify inside Docker

If your local environment blocks connections from host tools to Docker's published loopback port, run the optional verifier inside the same isolated Docker network:

```sh
docker compose --profile verify run --rm verify-lab
```

It makes one test login to this lab only and should print the lab account's `id`. The verifier image is disposable; this command removes its container when it exits and keeps the image for reuse.

## Run the audit

From this repository directory:

```sh
python3 check_sshhole.py
```

The script requires Docker access and reports on running containers only. It does not run SSH login attempts, change container state, or inspect stopped containers. Its account counters look at `/etc/shadow`; directory accounts without a shadow entry are not fully characterized by those counters. Treat every result as an indicator to investigate, not as a confirmed finding or proof of safety.

## Finding summary

The issue requires a specific combination of OpenSSH password authentication, musl, PAM being disabled, an affected upstream build, and a particular account database shape. A version string alone is insufficient to determine exposure because distributions can backport fixes. Consult the upstream [OpenSSH release notes](https://www.openssh.org/releasenotes.html) and your operating-system vendor's advisory for current patch status.

## Limitations

- This lab uses upstream OpenSSH 10.2p1, not a vendor package. It does not model vendor backports.
- The audit is deliberately conservative and may report conditions that need package-level review.
- The lab is not a general-purpose SSH server, benchmark, or production image.
- The project does not provide authorization to test systems you do not own or administer.

## License

MIT. See [LICENSE](LICENSE).
