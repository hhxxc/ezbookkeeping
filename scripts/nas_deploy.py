"""SSH 到 NAS 重建 ezBookkeeping 容器（跑 /volume2/docker/ezbk/deploy.sh）。

用法：python scripts/nas_deploy.py [凭据文件路径] [--host <IP>]
凭据文件默认取用户桌面的「REDACTED nas hhs.txt」，格式：IP 端口 用户 密码。
凭据不入库；本机无 sshpass，用 paramiko（已装）做非交互 SSH。

NAS 的局域网地址会变（历史用过 REDACTED / REDACTED），所以按顺序探测：
命令行 --host > 环境变量 NESTKEEP_NAS_HOST > 凭据文件里的 IP > 内置候选地址。
"""
import os, sys, time
import paramiko

CRED_FILE = r"REDACTED"
DEPLOY_CMD = "bash /volume2/docker/ezbk/deploy.sh 2>&1; echo EXIT_CODE=$?"
# 历史出现过的 NAS 局域网地址，凭据文件里的 IP 连不上时依次尝试
HOST_CANDIDATES = ['REDACTED', 'REDACTED', 'REDACTED', 'REDACTED']

args = sys.argv[1:]
explicit_host = None
if '--host' in args:
    i = args.index('--host')
    if i + 1 < len(args):
        explicit_host = args[i + 1]
        del args[i:i + 2]

cred_path = args[0] if args else CRED_FILE
with open(cred_path, encoding="utf-8") as f:
    parts = f.read().split()
cred_ip, port, user, password = parts[0], int(parts[1]), parts[2], parts[3]

hosts = []
if explicit_host:
    hosts.append(explicit_host)
if os.environ.get('NESTKEEP_NAS_HOST'):
    hosts.append(os.environ['NESTKEEP_NAS_HOST'])
hosts.append(cred_ip)
hosts.extend(HOST_CANDIDATES)

client = None
for host in dict.fromkeys(hosts):  # 去重保序
    try:
        print(f"==> 尝试连接 {host}:{port}")
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(host, port=port, username=user, password=password, timeout=12)
        print(f"==> 已连接 {host}")
        client = c
        break
    except Exception as e:
        print(f"    失败：{type(e).__name__}: {e}")

if client is None:
    print("==> 所有候选地址均无法连接，请确认 NAS 开机且地址可达（可用 --host 指定）")
    sys.exit(1)

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
