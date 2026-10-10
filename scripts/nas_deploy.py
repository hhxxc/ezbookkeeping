"""SSH 到 NAS 重建 ezBookkeeping 容器（跑 NAS 部署目录下的 deploy.sh）。

用法：python scripts/nas_deploy.py [凭据文件路径] [--host <IP>]
凭据文件格式：IP 端口 用户 密码（一行，空格分隔）。
凭据不入库；本机无 sshpass，用 paramiko（需 pip install paramiko）做非交互 SSH。

配置方式（任选其一，详见 scripts/nas_config.py 头部说明）：
  - 命令行参数 / 环境变量 NAS_CRED_FILE / scripts/nas_config.local.py
  - 候选地址：命令行 --host > 环境变量 NAS_HOSTS > 凭据文件里的 IP > 本地覆盖配置
"""

import os
import sys
import time

import paramiko

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nas_config  # noqa: E402

DEPLOY_CMD = f"bash {nas_config.DEPLOY_DIR}/deploy.sh 2>&1; echo EXIT_CODE=$?"

args = sys.argv[1:]
explicit_host = None
if '--host' in args:
    i = args.index('--host')
    if i + 1 < len(args):
        explicit_host = args[i + 1]
        del args[i:i + 2]

cred_path = nas_config.resolve_creds(args)
cred_ip, port, user, password = nas_config.parse_creds(cred_path)

hosts = []
if explicit_host:
    hosts.append(explicit_host)
hosts.extend(nas_config.NAS_HOSTS)
hosts.append(cred_ip)

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
    if chan.exit_status_ready() and not chan.recv_ready():
        break
    time.sleep(0.3)
while chan.recv_ready():
    buf.append(chan.recv(4096).decode("utf-8", "replace"))
text = "".join(buf)
print(text[-6000:] if len(text) > 6000 else text)
print("---")
print("exit code:", chan.recv_exit_status())
client.close()
