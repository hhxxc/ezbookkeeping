"""同步仓库根目录的 nas_nestkeep_autosync.sh 到 NAS 部署目录。

NestKeep 发版自动跟版脚本（cron 每 10 分钟轮询 Docker Hub 发版镜像 digest，
自动解包 IPA + 更新清单到 data/nestkeep）。本脚本负责把仓库里的最新版本
同步到 NAS，并幂等安装 /etc/crontab 任务行（NAS 无 crontab 命令，任务统一
在 /etc/crontab，root 运行）。

用法：
    python scripts/nas_sync_nestkeep.py

配置方式（凭据文件等）见 scripts/nas_config.py 头部说明。
注意：hhxxc 对 hhxxc 用户的 sudo 免密，crontab 操作走 sudo。
"""

import os
import sys

import paramiko  # 需 pip install paramiko

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nas_config  # noqa: E402

LOCAL_SCRIPT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                             "..", "nas_nestkeep_autosync.sh"))
REMOTE_SCRIPT = f"{nas_config.DEPLOY_DIR}/nestkeep_autosync.sh"
CRONTAB_PATH = "/etc/crontab"
CRON_MARK = "nestkeep_autosync"
# 与 /etc/crontab 现有格式一致（六段 + user + cmd，tab 分隔）
CRON_LINE = "*/10\t*\t*\t*\t*\troot\t/bin/sh /volume2/docker/ezbk/nestkeep_autosync.sh > /dev/null 2>&1"

if not os.path.isfile(LOCAL_SCRIPT):
    print(f"==> 找不到 {LOCAL_SCRIPT}")
    sys.exit(1)

cred_path = nas_config.resolve_creds(sys.argv[1:])
_, port, user, password = nas_config.parse_creds(cred_path)
cli = paramiko.SSHClient()
cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())

hosts = nas_config.NAS_HOSTS
if nas_config.connect_any(cli, port, user, password, hosts) is None:
    print("==> 所有候选地址均无法连接（可用 NAS_HOSTS 环境变量指定，逗号分隔）")
    sys.exit(1)

out, err = nas_config.ssh_exec(cli, f"test -f '{REMOTE_SCRIPT}' && echo EXISTS || echo ABSENT")
if "EXISTS" in out:
    backup = f"{REMOTE_SCRIPT}.bak.{int(__import__('time').time())}"
    out, err = nas_config.ssh_exec(cli, f"cp '{REMOTE_SCRIPT}' '{backup}' && ls -la '{backup}'")
    print("==> 备份旧脚本：")
    print(out or err)

nas_config.upload_file(cli, LOCAL_SCRIPT, REMOTE_SCRIPT)

out, err = nas_config.ssh_exec(cli, f"bash -n '{REMOTE_SCRIPT}' && echo SYNTAX_OK")
if "SYNTAX_OK" not in out:
    print("==> 语法检查失败：", err)
    sys.exit(1)
print("==> 语法检查通过")

out, err = nas_config.ssh_exec(cli, f"chmod +x '{REMOTE_SCRIPT}'")

# crontab 幂等安装（/etc/crontab，DSM 无用户 crontab 命令）
out, _ = nas_config.ssh_exec(cli, f"sudo grep -qF '{CRON_MARK}' {CRONTAB_PATH} && echo EXISTS || echo ABSENT")
if "EXISTS" in out:
    print("==> /etc/crontab 已有该任务，跳过安装")
else:
    cmd = ("sudo sh -c 'printf \"%s\\n\" \"" + CRON_LINE.replace('"', '\\"') + "\" >> " + CRONTAB_PATH + "'")
    out, err = nas_config.ssh_exec(cli, cmd)
    if err.strip():
        print("==> crontab 安装失败：", err[:300])
        sys.exit(1)
    out, _ = nas_config.ssh_exec(cli, "sudo systemctl restart crond 2>/dev/null && echo RESTARTED || sudo /usr/syno/bin/synoservicectl --restart crond")
    print("==> crond:", out.strip())

out, _ = nas_config.ssh_exec(cli, f"sudo grep -c '{CRON_MARK}' {CRONTAB_PATH}")
print(f"==> /etc/crontab 中任务数: {out.strip()}")

cli.close()
print("==> 完成。日志：/volume2/docker/ezbk/nk_autosync.log")
