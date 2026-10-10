"""同步仓库根目录的 deploy.sh（及本地覆盖 deploy.local.sh，如有）到 NAS 部署目录。

群晖默认禁用 SFTP，用 base64 分块上传（helpers 见 nas_config.py）。
用法：
    python scripts/nas_sync_deploy.py            # 仅上传+语法检查
    python scripts/nas_sync_deploy.py --deploy   # 上传后重建容器（跑 deploy.sh）

配置方式（凭据文件等）见 scripts/nas_config.py 头部说明。
"""

import os
import sys
import time

import paramiko  # 需 pip install paramiko

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nas_config  # noqa: E402

LOCAL_DEPLOY = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..", "deploy.sh")
LOCAL_DEPLOY = os.path.normpath(LOCAL_DEPLOY)
LOCAL_OVERRIDE = os.path.join(os.path.dirname(LOCAL_DEPLOY),
                              "scripts", "deploy.local.sh")
REMOTE_DEPLOY = f"{nas_config.DEPLOY_DIR}/deploy.sh"
REMOTE_OVERRIDE = f"{nas_config.DEPLOY_DIR}/deploy.local.sh"

DO_DEPLOY = "--deploy" in sys.argv

cred_path = nas_config.resolve_creds(sys.argv[1:])
_, port, user, password = nas_config.parse_creds(cred_path)
cli = paramiko.SSHClient()
cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())

hosts = nas_config.NAS_HOSTS
result = nas_config.connect_any(cli, port, user, password, hosts)
if result is None:
    print("==> 所有候选地址均无法连接（可用 NAS_HOSTS 环境变量指定，逗号分隔）")
    sys.exit(1)

# 先备份远端现有脚本（防上传中断成半截文件没法回滚）
backup = f"{REMOTE_DEPLOY}.bak.{int(time.time())}"
out, err = nas_config.ssh_exec(
    cli, f"cp '{REMOTE_DEPLOY}' '{backup}' && ls -la '{backup}'")
print("==> 备份旧脚本：")
print(out or err)

nas_config.upload_file(cli, LOCAL_DEPLOY, REMOTE_DEPLOY)

out, err = nas_config.ssh_exec(cli, f"bash -n '{REMOTE_DEPLOY}' && echo SYNTAX_OK")
if "SYNTAX_OK" not in out:
    print("==> 语法检查失败，回滚：", err)
    nas_config.ssh_exec(cli, f"cp '{backup}' '{REMOTE_DEPLOY}'")
    sys.exit(1)
print("==> 语法检查通过")

# 如有本地个人覆盖文件（deploy.local.sh，gitignored），一并同步
if os.path.isfile(LOCAL_OVERRIDE):
    nas_config.upload_file(cli, LOCAL_OVERRIDE, REMOTE_OVERRIDE)
    out, _ = nas_config.ssh_exec(cli, f"bash -n '{REMOTE_OVERRIDE}' && echo SYNTAX_OK")
    if "SYNTAX_OK" not in out:
        print("==> 覆盖文件语法检查失败，请检查 scripts/deploy.local.sh")
        sys.exit(1)
    print("==> 已同步个人覆盖配置 deploy.local.sh")

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
