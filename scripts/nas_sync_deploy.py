"""同步仓库根目录的 deploy.sh 到 NAS（/volume2/docker/ezbk/deploy.sh）。

群晖禁用 SFTP，复用 nas_publish_nestkeep.py 的 base64 分块上传（upload_file）。
用法：
    C:/Python314/python.exe scripts/nas_sync_deploy.py            # 仅上传+语法检查
    C:/Python314/python.exe scripts/nas_sync_deploy.py --deploy   # 上传后重建容器（跑 deploy.sh）
"""

import sys
import time

sys.path.insert(0, r"D:/ezbk-native-wt/scripts")
import paramiko  # noqa: E402
from nas_publish_nestkeep import CRED_FILE, parse_creds, ssh_exec, upload_file  # noqa: E402

LOCAL_DEPLOY = r"D:/ezbookkeeping-ios/deploy.sh"
REMOTE_DEPLOY = "/volume2/docker/ezbk/deploy.sh"

DO_DEPLOY = "--deploy" in sys.argv

_, port, user, password = parse_creds(CRED_FILE)
cli = paramiko.SSHClient()
cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())

hosts = ["REDACTED", "REDACTED"]
cli_obj = None
for host in hosts:
    try:
        print(f"==> 尝试连接 {host}:{port}")
        cli.connect(host, port=port, username=user, password=password, timeout=12)
        print(f"==> 已连接 {host}")
        cli_obj = cli
        break
    except Exception as e:
        print(f"    失败：{type(e).__name__}: {e}")

if cli_obj is None:
    print("==> 所有候选地址均无法连接")
    sys.exit(1)

# 先备份远端现有脚本（防上传中断成半截文件没法回滚）
backup = f"{REMOTE_DEPLOY}.bak.{int(time.time())}"
out, err = ssh_exec(cli, f"cp '{REMOTE_DEPLOY}' '{backup}' && ls -la '{backup}'")
print("==> 备份旧脚本：")
print(out or err)

upload_file(cli, LOCAL_DEPLOY, REMOTE_DEPLOY)

out, err = ssh_exec(cli, f"bash -n '{REMOTE_DEPLOY}' && echo SYNTAX_OK")
if "SYNTAX_OK" not in out:
    print("==> 语法检查失败，回滚：", err)
    ssh_exec(cli, f"cp '{backup}' '{REMOTE_DEPLOY}'")
    sys.exit(1)
print("==> 语法检查通过")

# 同步备份脚本本身（供后续 --no-pull 等场景核对）
if DO_DEPLOY:
    print("==> 重建容器（deploy.sh 全流程）")
    _, so, se = cli.exec_command(f"bash '{REMOTE_DEPLOY}' 2>&1; echo EXIT_CODE=$?", timeout=540)
    chan = so.channel
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
    print(text[-4000:] if len(text) > 4000 else text)
    print("---")
    print("exit code:", chan.recv_exit_status())

cli.close()
