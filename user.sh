#!/usr/bin/env bash
set -euo pipefail

USER_NAME="ubuntu"
USER_HOME="/home/$USER_NAME"

CHECKER_IP="10.0.100.30"
CHECKER_PORT="8000"

SSH_DIR="$USER_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
SUDOERS_USER="/etc/sudoers.d/user"
SUDOERS_DEVOPS="/etc/sudoers.d/devops"
CHECK_TASK="/usr/local/bin/check-task"

echo "[*] Installing required packages..."
apt update
apt install -y curl openssh-server ufw xrdp vsftpd fail2ban

echo "[*] Creating ~/.ssh directory..."
mkdir -p "$SSH_DIR"
chown "$USER_NAME:$USER_NAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ ! -f "$AUTHORIZED_KEYS" ]]; then
    touch "$AUTHORIZED_KEYS"
    chown "$USER_NAME:$USER_NAME" "$AUTHORIZED_KEYS"
    chmod 600 "$AUTHORIZED_KEYS"
fi

echo "[*] Removing unattended-upgrades for task 02 initial state..."
apt remove -y unattended-upgrades || true

echo "[*] Preparing risky packages for task 03..."
apt remove -y telnet ftp rsh-client talk tftp tftpd-hpa 2>/dev/null || true
apt install -y telnet rsh-client talk ftp

echo "[*] Preparing services for task 04..."
apt remove -y vsftpd xrdp 2>/dev/null || true
apt install -y vsftpd xrdp
systemctl enable --now vsftpd
systemctl enable --now xrdp
systemctl disable --now cups 2>/dev/null || true
systemctl disable --now cups-browsed 2>/dev/null || true
systemctl disable --now openvpn 2>/dev/null || true

echo "[*] Preparing UFW for task 05..."
ufw --force disable || true
yes | ufw reset
ufw allow 80/tcp || true

echo "[*] Preparing weak SSH config for task 06..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)

sed -i 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
sed -i 's/^[#[:space:]]*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config || true

grep -q '^PermitRootLogin ' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
grep -q '^PasswordAuthentication ' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
grep -q '^PubkeyAuthentication ' /etc/ssh/sshd_config || echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config

systemctl restart ssh || systemctl restart sshd || true

echo "[*] Preparing legacy user for task 07..."
if ! id legacy >/dev/null 2>&1; then
    useradd -m legacy
fi

echo "[*] Preparing password policy for task 08..."
if [[ -f /etc/security/pwquality.conf ]]; then
    sed -i 's/^[#[:space:]]*minlen[[:space:]]*=.*/minlen = 8/' /etc/security/pwquality.conf || true
    grep -q '^[[:space:]]*minlen[[:space:]]*=' /etc/security/pwquality.conf || echo 'minlen = 8' >> /etc/security/pwquality.conf
fi

if [[ -f /etc/login.defs ]]; then
    sed -i 's/^[#[:space:]]*PASS_MAX_DAYS.*/PASS_MAX_DAYS 99999/' /etc/login.defs || true
    sed -i 's/^[#[:space:]]*PASS_MIN_DAYS.*/PASS_MIN_DAYS 0/' /etc/login.defs || true
    sed -i 's/^[#[:space:]]*PASS_WARN_AGE.*/PASS_WARN_AGE 0/' /etc/login.defs || true

    grep -q '^PASS_MAX_DAYS' /etc/login.defs || echo 'PASS_MAX_DAYS 99999' >> /etc/login.defs
    grep -q '^PASS_MIN_DAYS' /etc/login.defs || echo 'PASS_MIN_DAYS 0' >> /etc/login.defs
    grep -q '^PASS_WARN_AGE' /etc/login.defs || echo 'PASS_WARN_AGE 0' >> /etc/login.defs
fi

echo "[*] Preparing devops user for task 09..."
if ! id devops >/dev/null 2>&1; then
    useradd -m devops
fi

cat > "$SUDOERS_DEVOPS" <<'EOF'
devops ALL=(ALL) NOPASSWD:ALL
EOF
chmod 644 "$SUDOERS_DEVOPS"
chown root:root "$SUDOERS_DEVOPS"

echo "[*] Creating sudoers policy for checker actions..."
cat > "$SUDOERS_USER" <<EOF
$USER_NAME ALL=(root) NOPASSWD: /usr/lib/update-notifier/apt-check
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/apt
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/apt-get
$USER_NAME ALL=(root) NOPASSWD: /usr/sbin/sshd
$USER_NAME ALL=(root) NOPASSWD: /usr/sbin/ufw
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/systemctl
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/test
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/stat
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/ls
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/cat
$USER_NAME ALL=(root) NOPASSWD: /usr/sbin/cryptsetup
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/ss
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/fail2ban-client
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/dpkg
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/grep
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/sh
EOF

chown root:root "$SUDOERS_USER"
chmod 440 "$SUDOERS_USER"

echo "[*] Preparing journald for task 11..."
if [[ -f /etc/systemd/journald.conf ]]; then
    sed -i 's/^[#[:space:]]*Storage=.*/Storage=auto/' /etc/systemd/journald.conf || true
    grep -q '^Storage=' /etc/systemd/journald.conf || echo 'Storage=auto' >> /etc/systemd/journald.conf
fi
systemctl restart systemd-journald || true

echo "[*] Preparing task 12 image placeholder..."
mkdir -p /opt/lab
rm -f /opt/lab/secure-data.img
touch /opt/lab/secure-data.img

echo "[*] Creating check-task helper..."
cat > "$CHECK_TASK" <<EOF
#!/bin/bash
set -euo pipefail

TASK_ID="\${1:-}"

if [[ -z "\$TASK_ID" ]]; then
    echo "Usage: check-task <task-id>"
    exit 1
fi

RESPONSE="\$(curl -sS -X POST http://$CHECKER_IP:$CHECKER_PORT/api/check \\
  -H "Content-Type: application/json" \\
  -d "{\\"task_id\\":\\"\$TASK_ID\\"}")"

STATUS="\$(echo "\$RESPONSE" | python3 -c 'import sys, json; print(json.load(sys.stdin)["status"])')"

if [[ "\$STATUS" == "ok" ]]; then
    MESSAGE="\$(echo "\$RESPONSE" | python3 -c 'import sys, json; print(json.load(sys.stdin)["message"])')"
    FLAG="\$(echo "\$RESPONSE" | python3 -c 'import sys, json; print(json.load(sys.stdin)["flag"])')"
    echo "[OK] \$MESSAGE"
    echo "\$FLAG"
else
    MESSAGE="\$(echo "\$RESPONSE" | python3 -c 'import sys, json; print(json.load(sys.stdin)["message"])')"
    echo "[FAIL] \$MESSAGE"
    exit 1
fi
EOF

chmod 755 "$CHECK_TASK"
chown root:root "$CHECK_TASK"

echo
echo "========================================"
echo "User-server setup completed."
echo
echo "What you still need to do manually:"
echo "1. Insert checker public key into:"
echo "   $AUTHORIZED_KEYS"
echo
echo "2. Make sure file permissions stay:"
echo "   chmod 600 $AUTHORIZED_KEYS"
echo "   chown $USER_NAME:$USER_NAME $AUTHORIZED_KEYS"
echo
echo "3. Test connectivity from checker-server:"
echo "   ssh -i /opt/check/ssh/checker_ed25519 $USER_NAME@$(hostname -I | awk '{print $1}')"
echo
echo "4. Test local checker call:"
echo "   check-task 01"
echo "========================================"
