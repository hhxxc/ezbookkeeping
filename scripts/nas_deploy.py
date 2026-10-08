"""SSH 到 NAS 重建 ezBookkeeping 容器（跑 /volume2/docker/ezbk/deploy.sh）。

用法：python scripts/nas_deploy.py [凭据文件路径] [SSH地址]
凭据文件默认取用户桌面的「REDACTED nas hhs.txt」，格式：IP 端口 用户 密码。
凭据不入库；本机无 sshpass，用 paramiko（已装）做非交互 SSH。

注意：NAS 的局域网地址会随路由器网段变化（历史用过 REDACTED / REDACTED），
故第二个参数可显式指定地址；不指定时用环境变量 NESTKEEP_NAS_HOST，再回退到凭据文件里的 IP
与内置候选地址列表。
"""
import os
import sys, time
import paramiko

CRED_FILE = r"REDACTED"
DEPLOY_CMD = "bash /volume2/docker/ezbk/deploy.sh 2>&1; echo EXIT_CODE=$?"
# NAS SSH 地址候选（按顺序尝试）
HOST_CANDIDATES = ["REDACTED", "REDACTED", "192.168.3.198"]

cred_path = sys.argv[1] if len(sys.argv) > 1 else CRED_FILE
with open(cred_path, encoding="utf-8") as f:
    parts = f.read().split()
cred_ip, port, user, password = parts[0], int(parts[1]), parts[2], parts[3]

hosts = []
if len(sys.argv) > 2:
    hosts.append(sys.argv[2])
if os.environ.get("NESTKEEP_NAS_HOST"):
    hosts.append(os.environ["NESTKEEP_NAS_HOST"])
hosts.append(cred_ip)
hosts.extend(HOST_CANDIDATES)

client = None
last_err = None
for host in dict.fromkeys(hosts):  # 去重保序
    try:
        print(f"==> 尝试连接 {host}:{port}")
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(host, port=port, username=user, password=password, timeout=12)
        print(f"==> 已连接 {host}")
        break
    except Exception as e:
        last_err = e
        print(f"    失败：{e}")
        client = None
if client is None:
    raise SystemExit(f"所有候选地址均无法连接 NAS：{last_err}")

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
