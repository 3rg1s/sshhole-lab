#!/bin/sh
set -eu

askpass=/tmp/sshhole-askpass
cat > "$askpass" <<'EOF'
#!/bin/sh
case "${SSHOLE_TEST_KIND:-}" in
  short) printf '%s' 'definitely-not-the-password' ;;
  a) printf '%300s' '' | tr ' ' 'A' ;;
  b) printf '%300s' '' | tr ' ' 'B' ;;
  *) exit 2 ;;
esac
EOF
chmod 700 "$askpass"

export DISPLAY=:0
export SSH_ASKPASS="$askpass"
export SSH_ASKPASS_REQUIRE=force

ssh_lab() {
  SSHOLE_TEST_KIND="$1" /usr/bin/ssh -n -T -p 2222 \
    -o ConnectTimeout=5 \
    -o NumberOfPasswordPrompts=1 \
    -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o KbdInteractiveAuthentication=no \
    auditdirectory@vulnerable-ssh id
}

print_password() {
  character="$1"
  printf 'Password input (%s repeated 300 times):\n' "$character"
  for _ in 1 2 3; do
    printf '%100s\n' '' | tr ' ' "$character"
  done
}

printf 'Short control password: definitely-not-the-password\n'
if ssh_lab short >/dev/null 2>&1; then
  echo 'Short wrong password: unexpectedly accepted' >&2
  exit 1
fi
echo 'Short wrong password: rejected'

# OpenSSH briefly penalizes a source after a failed authentication.
sleep 6

for kind in a b; do
  case "$kind" in
    a) label='300 A characters' ;;
    b) label='300 B characters' ;;
  esac
  case "$kind" in
    a) print_password A ;;
    b) print_password B ;;
  esac
  if output="$(ssh_lab "$kind" 2>/dev/null)"; then
    printf '%s: accepted\n' "$label"
    printf '%s\n' "$output"
  else
    printf '%s: unexpectedly rejected\n' "$label" >&2
    exit 1
  fi
done
