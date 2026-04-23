#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/check"
API_DIR="$BASE_DIR/api"
CORE_DIR="$BASE_DIR/core"
TASKS_DIR="$BASE_DIR/tasks"
INVENTORY_DIR="$BASE_DIR/inventory"
FLAGS_DIR="$BASE_DIR/flags"
SSH_DIR="$BASE_DIR/ssh"
VENV_DIR="$BASE_DIR/venv"

CHECKER_USER="ubuntu"
CHECKER_GROUP="ubuntu"
CHECKER_PASSWORD='Luk@aT!apPlE17^DNA%joy3219'

CHECKER_IP="10.0.100.30"
CHECKER_PORT="8000"

USER_SERVER_IP="10.0.100.17"
USER_SERVER_USER="ubuntu"

SSH_KEY="$SSH_DIR/checker_ed25519"
KNOWN_HOSTS="$SSH_DIR/known_hosts"
INVENTORY_FILE="$INVENTORY_DIR/inventory.yml"

SERVICE_NAME="checker-api"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Spust skript pres sudo."
  exit 1
fi

if ! id "$CHECKER_USER" >/dev/null 2>&1; then
  echo "Uzivatel $CHECKER_USER neexistuje."
  exit 1
fi

printf '%s:%s\n' "$CHECKER_USER" "$CHECKER_PASSWORD" | chpasswd

apt update
apt install -y python3 python3-pip python3-venv openssh-client curl

mkdir -p "$API_DIR" "$CORE_DIR" "$TASKS_DIR" "$INVENTORY_DIR" "$FLAGS_DIR" "$SSH_DIR"
chown -R "$CHECKER_USER:$CHECKER_GROUP" "$BASE_DIR"

if [[ ! -d "$VENV_DIR" ]]; then
  sudo -u "$CHECKER_USER" python3 -m venv "$VENV_DIR"
fi

sudo -u "$CHECKER_USER" "$VENV_DIR/bin/pip" install --upgrade pip
sudo -u "$CHECKER_USER" "$VENV_DIR/bin/pip" install fastapi uvicorn pyyaml

touch "$KNOWN_HOSTS"
chmod 644 "$KNOWN_HOSTS"

if [[ ! -f "$SSH_KEY" ]]; then
  sudo -u "$CHECKER_USER" ssh-keygen -t ed25519 -f "$SSH_KEY" -N ""
fi

chmod 600 "$SSH_KEY"
chmod 644 "$SSH_KEY.pub"

if ! ssh-keygen -F "$USER_SERVER_IP" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  ssh-keyscan -H "$USER_SERVER_IP" >> "$KNOWN_HOSTS" 2>/dev/null || true
fi

cat > "$INVENTORY_FILE" <<EOF
user_server:
  host: $USER_SERVER_IP
  user: $USER_SERVER_USER
  ssh_key: $SSH_KEY
  flags_dir: $FLAGS_DIR
EOF

chmod 644 "$INVENTORY_FILE"
chown "$CHECKER_USER:$CHECKER_GROUP" "$INVENTORY_FILE"

cat > "$CORE_DIR/config_loader.py" <<'EOF'
import yaml

CONFIG_PATH = "/opt/check/inventory/inventory.yml"

def load_inventory() -> dict:
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)
EOF

cat > "$CORE_DIR/ssh_runner.py" <<'EOF'
import subprocess

def run_remote_command(host: str, user: str, ssh_key: str, command: str, timeout: int = 15) -> tuple[int, str, str]:
    ssh_cmd = [
        "ssh",
        "-i", ssh_key,
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "UserKnownHostsFile=/opt/check/ssh/known_hosts",
        "-o", "ConnectTimeout=5",
        f"{user}@{host}",
        command,
    ]

    result = subprocess.run(
        ssh_cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )

    return result.returncode, result.stdout.strip(), result.stderr.strip()
EOF

cat > "$CORE_DIR/flags.py" <<'EOF'
from pathlib import Path

def read_flag(flags_dir: str, task_id: str) -> str:
    task_id = task_id.strip().upper()
    if task_id.startswith("T"):
        task_id = task_id[1:]
    task_id = task_id.zfill(2)
    flag_path = Path(flags_dir) / f"{task_id}.flag"

    if not flag_path.exists():
        raise FileNotFoundError(f"Flag file not found: {flag_path}")

    return flag_path.read_text(encoding="utf-8").strip()
EOF

cat > "$API_DIR/app.py" <<'EOF'
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from core.config_loader import load_inventory
from core.flags import read_flag
from core.registry import TASKS

app = FastAPI()

class CheckRequest(BaseModel):
    task_id: str

def normalize_task_id(raw: str) -> str:
    task_id = raw.strip().upper()

    if task_id.startswith("T"):
        task_id = task_id[1:]

    if not task_id.isdigit():
        raise HTTPException(status_code=400, detail="Unsupported task ID")

    return task_id.zfill(2)

@app.post("/api/check")
def check_task(req: CheckRequest):
    task_id = normalize_task_id(req.task_id)

    if task_id not in TASKS:
        raise HTTPException(status_code=400, detail="Unsupported task ID")

    config = load_inventory()["user_server"]
    task_module = TASKS[task_id]

    ok, message = task_module.run(config)

    if ok:
        flag = read_flag(config["flags_dir"], task_id)
        return {
            "status": "ok",
            "message": message,
            "flag": flag,
        }

    return {
        "status": "fail",
        "message": message,
    }
EOF

cat > "$TASKS_DIR/__init__.py" <<'EOF'
# tasks package
EOF

cat > "$CORE_DIR/registry.py" <<'EOF'
import tasks.task01 as task01
import tasks.task02 as task02
import tasks.task03 as task03
import tasks.task04 as task04
import tasks.task05 as task05
import tasks.task06 as task06
import tasks.task07 as task07
import tasks.task08 as task08
import tasks.task09 as task09
import tasks.task10 as task10
import tasks.task11 as task11
import tasks.task12 as task12

TASKS = {
    "01": task01,
    "1": task01,
    "02": task02,
    "2": task02,
    "03": task03,
    "3": task03,
    "04": task04,
    "4": task04,
    "05": task05,
    "5": task05,
    "06": task06,
    "6": task06,
    "07": task07,
    "7": task07,
    "08": task08,
    "8": task08,
    "09": task09,
    "9": task09,
    "10": task10,
    "11": task11,
    "12": task12,
}
EOF

cat > "$TASKS_DIR/task01.py" <<'EOF'
from core.ssh_runner import run_remote_command
import re

APT_CHECK = "/usr/lib/update-notifier/apt-check --human-readable"

def parse_security_updates(output: str) -> int | None:
    for line in output.splitlines():
        low = line.strip().lower()

        if not low:
            continue

        if "esm apps" in low or "expanded security maintenance" in low:
            continue

        if "security update" in low:
            match = re.search(r"\d+", low)
            if match:
                return int(match.group())

    return 0

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    cmd = f"sudo -n {APT_CHECK}"
    code, stdout, stderr = run_remote_command(host, user, ssh_key, cmd)

    if code != 0:
        if stderr:
            return False, f"Unable to check update status: {stderr}"
        return False, "Unable to check update status"

    if not stdout:
        return False, "Empty response from apt-check"

    security_count = parse_security_updates(stdout)

    if security_count != 0:
        return False, f"Pending security updates still detected: {security_count}"

    return True, "Task 01 completed"
EOF

cat > "$TASKS_DIR/task02.py" <<'EOF'
from core.ssh_runner import run_remote_command

def check_package_installed(host, user, key) -> bool:
    cmd = "dpkg -l unattended-upgrades | grep '^ii'"
    code, _, _ = run_remote_command(host, user, key, cmd)
    return code == 0

def check_apt_periodic(host, user, key) -> tuple[bool, str]:
    cmd = "cat /etc/apt/apt.conf.d/20auto-upgrades"
    code, stdout, stderr = run_remote_command(host, user, key, cmd)

    if code != 0:
        return False, "Cannot read APT periodic config"

    if 'APT::Periodic::Update-Package-Lists "1"' not in stdout:
        return False, "APT Update-Package-Lists is not enabled"

    if 'APT::Periodic::Unattended-Upgrade "1"' not in stdout:
        return False, "Unattended-Upgrade is not enabled"

    return True, ""

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    if not check_package_installed(host, user, ssh_key):
        return False, "Package unattended-upgrades is not installed"

    ok, msg = check_apt_periodic(host, user, ssh_key)
    if not ok:
        return False, msg

    return True, "Task 02 completed"
EOF

cat > "$TASKS_DIR/task03.py" <<'EOF'
from core.ssh_runner import run_remote_command

RISKY_PACKAGES = [
    "telnet",
    "ftp",
    "rsh-client",
]

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    still_installed = []

    for pkg in RISKY_PACKAGES:
        cmd = f"dpkg -s {pkg} 2>/dev/null | grep '^Status: install ok installed$'"
        code, _, _ = run_remote_command(host, user, ssh_key, cmd)

        if code == 0:
            still_installed.append(pkg)

    if still_installed:
        return False, f"Risky packages still installed: {', '.join(still_installed)}"

    return True, "Task 03 completed"
EOF

cat > "$TASKS_DIR/task04.py" <<'EOF'
from core.ssh_runner import run_remote_command

SERVICES = [
    "apache2",
    "rpcbind",
    "vsftpd",
]

RISKY_PORTS = [
    21,
    80,
    111,
]

def check_service_inactive(host: str, user: str, ssh_key: str, service: str) -> tuple[bool, str]:
    cmd = f"systemctl is-active {service}"
    code, stdout, stderr = run_remote_command(host, user, ssh_key, cmd)

    if stdout.strip() == "active":
        return False, f"Service {service} is still active"

    return True, ""

def check_service_disabled(host: str, user: str, ssh_key: str, service: str) -> tuple[bool, str]:
    cmd = f"systemctl is-enabled {service}"
    code, stdout, stderr = run_remote_command(host, user, ssh_key, cmd)

    if stdout.strip() == "enabled":
        return False, f"Service {service} is still enabled"

    return True, ""

def check_port_closed(host: str, user: str, ssh_key: str, port: int) -> tuple[bool, str]:
    cmd = f"sudo -n ss -ltn '( sport = :{port} )' | tail -n +2"
    code, stdout, stderr = run_remote_command(host, user, ssh_key, cmd)

    if stderr and not stdout:
        return False, f"Unable to check port {port}: {stderr}"

    if stdout.strip():
        return False, f"Port {port} is still open"

    return True, ""

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    for service in SERVICES:
        ok, msg = check_service_inactive(host, user, ssh_key, service)
        if not ok:
            return False, msg

        ok, msg = check_service_disabled(host, user, ssh_key, service)
        if not ok:
            return False, msg

    for port in RISKY_PORTS:
        ok, msg = check_port_closed(host, user, ssh_key, port)
        if not ok:
            return False, msg

    return True, "Task 04 completed"
EOF

cat > "$TASKS_DIR/task05.py" <<'EOF'
from core.ssh_runner import run_remote_command

def get_ufw_status(host: str, user: str, ssh_key: str) -> tuple[bool, str, str]:
    cmd = "sudo -n ufw status verbose"
    code, stdout, stderr = run_remote_command(host, user, ssh_key, cmd)

    if code != 0:
        if stderr:
            return False, "", f"Unable to read UFW status: {stderr}"
        return False, "", "Unable to read UFW status"

    if not stdout.strip():
        return False, "", "Empty output from UFW"

    return True, stdout, ""

def check_ufw_active(output: str) -> tuple[bool, str]:
    for line in output.splitlines():
        if line.strip().lower().startswith("status:"):
            status_value = line.split(":", 1)[1].strip().lower()
            if status_value == "active":
                return True, ""
            return False, "UFW is not active"

    return False, "Unable to determine whether UFW is active"

def check_default_policies(output: str) -> tuple[bool, str]:
    incoming_ok = False
    outgoing_ok = False

    for line in output.splitlines():
        low = line.strip().lower()

        if low.startswith("default:"):
            if "deny (incoming)" in low:
                incoming_ok = True
            if "allow (outgoing)" in low:
                outgoing_ok = True

    if not incoming_ok:
        return False, "Default incoming policy is not deny"

    if not outgoing_ok:
        return False, "Default outgoing policy is not allow"

    return True, ""

def check_ssh_rule(output: str) -> tuple[bool, str]:
    lines = [line.strip().lower() for line in output.splitlines()]

    for line in lines:
        if "allow in" in line and ("22/tcp" in line or "openssh" in line):
            return True, ""

    return False, "SSH rule for 22/tcp is missing"

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    ok, stdout, err = get_ufw_status(host, user, ssh_key)
    if not ok:
        return False, err

    ok, msg = check_ufw_active(stdout)
    if not ok:
        return False, msg

    ok, msg = check_default_policies(stdout)
    if not ok:
        return False, msg

    ok, msg = check_ssh_rule(stdout)
    if not ok:
        return False, msg

    return True, "Task 05 completed"
EOF

cat > "$TASKS_DIR/task06.py" <<'EOF'
from core.ssh_runner import run_remote_command

REQUIRED = {
    "permitrootlogin": "no",
    "passwordauthentication": "no",
    "pubkeyauthentication": "yes",
}

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    cmd = "sudo -n sshd -T"
    code, stdout, stderr = run_remote_command(host, user, ssh_key, cmd)

    if code != 0:
        return False, stderr or "Unable to read effective sshd config"

    effective = stdout.lower()
    for key, expected in REQUIRED.items():
        probe = f"{key} {expected}"
        if probe not in effective:
            return False, f"Missing SSH hardening setting: {probe}"

    return True, "Task 06 completed"
EOF

cat > "$TASKS_DIR/task07.py" <<'EOF'
import re
from core.ssh_runner import run_remote_command

ACCOUNT = "legacy"

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    code, stdout, stderr = run_remote_command(host, user, ssh_key, "sudo -n cat /etc/passwd")
    if code != 0:
        return False, stderr or "Unable to read /etc/passwd"

    if re.search(rf"^{ACCOUNT}:", stdout, re.MULTILINE):
        return False, f"Account {ACCOUNT} is still present in /etc/passwd"

    code, shadow_out, shadow_err = run_remote_command(
        host, user, ssh_key, "sudo -n test -f /etc/shadow && sudo -n cat /etc/shadow || true"
    )
    if code != 0:
        return False, shadow_err or "Unable to inspect /etc/shadow"

    if re.search(rf"^{ACCOUNT}:", shadow_out, re.MULTILINE):
        return False, f"Account {ACCOUNT} is still present in /etc/shadow"

    return True, "Task 07 completed"
EOF

cat > "$TASKS_DIR/task08.py" <<'EOF'
import re
from core.ssh_runner import run_remote_command

def extract_login_defs_value(content: str, key: str) -> int | None:
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[0] == key and parts[1].isdigit():
            return int(parts[1])
    return None

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    code, pwq_out, pwq_err = run_remote_command(host, user, ssh_key, "sudo -n cat /etc/security/pwquality.conf")
    if code != 0:
        return False, pwq_err or "Unable to read pwquality.conf"

    match = re.search(r"^[ \t]*minlen[ \t]*=[ \t]*(\d+)", pwq_out, re.MULTILINE)
    if not match:
        return False, "minlen is missing in pwquality.conf"
    if int(match.group(1)) < 12:
        return False, "minlen is lower than 12"

    code, defs_out, defs_err = run_remote_command(host, user, ssh_key, "sudo -n cat /etc/login.defs")
    if code != 0:
        return False, defs_err or "Unable to read login.defs"

    max_days = extract_login_defs_value(defs_out, "PASS_MAX_DAYS")
    min_days = extract_login_defs_value(defs_out, "PASS_MIN_DAYS")
    warn_age = extract_login_defs_value(defs_out, "PASS_WARN_AGE")

    if max_days is None or max_days > 90:
        return False, "PASS_MAX_DAYS is not compliant"
    if min_days is None or min_days < 1:
        return False, "PASS_MIN_DAYS is not compliant"
    if warn_age is None or warn_age < 7:
        return False, "PASS_WARN_AGE is not compliant"

    return True, "Task 08 completed"
EOF

cat > "$TASKS_DIR/task09.py" <<'EOF'
import re
from core.ssh_runner import run_remote_command

ACCOUNT = "devops"

REQUIRED_COMMANDS = [
    "/usr/bin/systemctl status *",
    "/usr/bin/journalctl *",
]

FORBIDDEN_PATTERNS = [
    r"\bNOPASSWD\b",
    r"\(\s*ALL\s*\)",
    r":\s*ALL(\s|$)",
    r"/usr/bin/systemctl\s+(?!status\b)\S+",
    r"\b(start|stop|restart|reload|enable|disable|edit|kill|reboot|poweroff)\b",
    r"/bin/bash",
    r"/bin/sh",
    r"/usr/bin/sudoedit",
    r"/usr/sbin/visudo",
]

def normalize_spaces(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip())

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    cmd = "sudo -n sh -c 'cat /etc/sudoers /etc/sudoers.d/* 2>/dev/null'"
    code, stdout, stderr = run_remote_command(host, user, ssh_key, cmd)
    if code != 0:
        return False, stderr or "Unable to read sudoers policy"

    rules = []
    for line in stdout.splitlines():
        stripped = line.strip()

        if not stripped or stripped.startswith("#"):
            continue

        if re.match(rf"^{ACCOUNT}\s", stripped):
            rules.append(normalize_spaces(stripped))

    if not rules:
        return False, f"No sudo rules found for {ACCOUNT}"

    merged = "\n".join(rules)

    for pattern in FORBIDDEN_PATTERNS:
        if re.search(pattern, merged):
            return False, f"{ACCOUNT} still has overly broad sudo privileges"

    for required in REQUIRED_COMMANDS:
        if required not in merged:
            return False, f"Missing required sudo rule: {required}"

    return True, "Task 09 completed"
EOF

cat > "$TASKS_DIR/task10.py" <<'EOF'
from core.ssh_runner import run_remote_command

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    cmd = "sudo -n stat -c '%U:%G %a' /etc/myapp/app.env"
    code, stdout, stderr = run_remote_command(host, user, ssh_key, cmd)
    if code != 0:
        return False, stderr or "Unable to stat /etc/myapp/app.env"

    if stdout.strip() != "root:root 640":
        return False, f"Unexpected owner/mode: {stdout.strip()}"

    return True, "Task 10 completed"
EOF

cat > "$TASKS_DIR/task11.py" <<'EOF'
from core.ssh_runner import run_remote_command

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    code, journald_out, journald_err = run_remote_command(
        host, user, ssh_key, "sudo -n cat /etc/systemd/journald.conf"
    )
    if code != 0:
        return False, journald_err or "Unable to read journald.conf"

    normalized = journald_out.replace(" ", "").lower()
    if "storage=persistent" not in normalized:
        return False, "journald is not set to persistent storage"

    code, systemctl_out, systemctl_err = run_remote_command(
        host, user, ssh_key, "sudo -n systemctl is-active fail2ban"
    )
    if code != 0 or systemctl_out.strip() != "active":
        return False, systemctl_err or "fail2ban service is not active"

    code, jail_out, jail_err = run_remote_command(
        host, user, ssh_key, "sudo -n fail2ban-client status sshd"
    )
    if code != 0:
        return False, jail_err or "Unable to verify fail2ban sshd jail"

    return True, "Task 11 completed"
EOF

cat > "$TASKS_DIR/task12.py" <<'EOF'
from core.ssh_runner import run_remote_command

IMAGE_PATH = "/opt/lab/secure-data.img"
MIN_SIZE_BYTES = 128 * 1024 * 1024

def run(config: dict) -> tuple[bool, str]:
    host = config["host"]
    user = config["user"]
    ssh_key = config["ssh_key"]

    code, _, stderr = run_remote_command(
        host, user, ssh_key,
        f"test -f {IMAGE_PATH}"
    )
    if code != 0:
        return False, f"{IMAGE_PATH} does not exist"

    code, stdout, stderr = run_remote_command(
        host, user, ssh_key,
        f"stat -c %s {IMAGE_PATH}"
    )
    if code != 0:
        return False, stderr or f"Unable to determine size of {IMAGE_PATH}"

    try:
        size = int(stdout.strip())
    except ValueError:
        return False, f"Invalid file size returned for {IMAGE_PATH}"

    if size < MIN_SIZE_BYTES:
        return False, f"{IMAGE_PATH} is too small ({size} bytes), expected at least {MIN_SIZE_BYTES} bytes"

    code, _, stderr = run_remote_command(
        host, user, ssh_key,
        f"sudo -n cryptsetup isLuks {IMAGE_PATH}"
    )
    if code != 0:
        return False, stderr or f"{IMAGE_PATH} is not a valid LUKS container"

    return True, "Task 12 completed"
EOF

cat > "$FLAGS_DIR/01.flag" <<'EOF'
FLAG{linux67user}
EOF
cat > "$FLAGS_DIR/02.flag" <<'EOF'
FLAG{sudo make me a sandwich}
EOF
cat > "$FLAGS_DIR/03.flag" <<'EOF'
FLAG{tuntunsahur}
EOF
cat > "$FLAGS_DIR/04.flag" <<'EOF'
FLAG{apt-get moo}
EOF
cat > "$FLAGS_DIR/05.flag" <<'EOF'
FLAG{meow>^^<meow}
EOF
cat > "$FLAGS_DIR/06.flag" <<'EOF'
FLAG{There is no place like 127.0.0.1}
EOF
cat > "$FLAGS_DIR/07.flag" <<'EOF'
FLAG{rm -rf /}
EOF
cat > "$FLAGS_DIR/08.flag" <<'EOF'
FLAG{TakBojujNe}
EOF
cat > "$FLAGS_DIR/09.flag" <<'EOF'
FLAG{Thursday, 1 January 1970}
EOF
cat > "$FLAGS_DIR/10.flag" <<'EOF'
FLAG{labubu}
EOF
cat > "$FLAGS_DIR/11.flag" <<'EOF'
FLAG{Hello world!}
EOF
cat > "$FLAGS_DIR/12.flag" <<'EOF'
Jupi, zvládl jsi to do konce! FLAG{jsiBorec}
EOF

chmod 600 "$FLAGS_DIR"/*.flag
chown "$CHECKER_USER:$CHECKER_GROUP" "$FLAGS_DIR"/*.flag

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Checker FastAPI service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$CHECKER_USER
Group=$CHECKER_GROUP
WorkingDirectory=$BASE_DIR
Environment=PYTHONPATH=$BASE_DIR
ExecStart=$VENV_DIR/bin/uvicorn api.app:app --host $CHECKER_IP --port $CHECKER_PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

echo
echo "Checker byl nainstalovan."
echo "API: http://$CHECKER_IP:$CHECKER_PORT/api/check"
echo "Docs: http://$CHECKER_IP:$CHECKER_PORT/docs"
echo
echo "verejny klic na user-server do ~/.ssh/authorized_keys:"
echo
cat "$SSH_KEY.pub"
echo
echo "Stav sluzby:"
echo "  sudo systemctl status $SERVICE_NAME"
