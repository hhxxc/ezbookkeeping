"""SSH 到 NAS 重建 ezBookkeeping 容器（跑 /volume2/docker/ezbk/deploy.sh）。

用法：python scripts/nas_deploy.py [凭据文件路径]
凭据文件默认取用户桌面的「REDACTED nas hhs.txt」，格式：IP 端口 用户 密码。
凭据不入库；本机无 sshpass，用 paramiko（已装）做非交互 SSH。
"""
import sys, time
import paramiko

CRED_FILE = r"REDACTED"
DEPLOY_CMD = "bash /volume2/docker/ezbk/deploy.sh 2>&1; echo EXIT_CODE=$?"

cred_path = sys.argv[1] if len(sys.argv) > 1 else CRED_FILE
with open(cred_path, encoding="utf-8") as f:
    parts = f.read().split()
host, port, user, password = parts[0], int(parts[1]), parts[2], parts[3]

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(host, port=port, username=user, password=password, timeout=20)

stdin, stdout, stderr = client.exec_command(DEPLOY_CMD, timeout=540)
chan = stdout.channel
buf = []
while True:
    while chan.recv_ready():
        buf.append(chan.recv(4096).decode("utf-8", "replace"))
        sys.stdout.flush()
    if chan.exit_status_ready() and not chan.recv_ready():
        break
    time.sleep(0.3)
while chan.recv_ready():
    buf.append(chan.recv(4096).decode("utf-8", "replace"))
out = "".join(buf)
print(out[-4000:] if len(out) > 4000 else out)
print("---")
print("exit code:", chan.recv_exit_status())
client.close()
