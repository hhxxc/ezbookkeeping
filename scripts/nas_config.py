"""NAS 部署脚本的通用配置与 SSH 助手（不含任何作者个人环境信息）。

个人定制方式（二选一，均不会提交到仓库）：
  1. 环境变量：NAS_CRED_FILE / NAS_HOSTS / NAS_DEPLOY_DIR
  2. 创建 scripts/nas_config.local.py，定义同名变量覆盖（已加入 .gitignore）

凭据文件格式：一行四个字段，空格分隔：IP 端口 用户 密码
⚠️ 密码/Key 一律不要写进任何会被 git 跟踪的文件。

需要自行获取的东西：
  - NAS SSH 账号密码（群晖：控制面板 > 终端机和 SNMP 启用 SSH）
  - LLM API Key（识别/语音记账用，如硅基流动 https://siliconflow.cn，见 deploy.sh 提示）
"""

import base64
import os
import time

# ---- 可被环境变量 / nas_config.local.py 覆盖的配置 ----

# NAS SSH 凭据文件路径（IP 端口 用户 密码）。默认无，必须自行提供
CRED_FILE = os.environ.get("NAS_CRED_FILE", "")

# NAS 的 SSH 可达地址（本机网段可能变化时填多个，逗号分隔）
NAS_HOSTS = [h for h in os.environ.get(
    "NAS_HOSTS", "").split(",") if h]

# NAS 上部署目录（docker-compose 数据 + 脚本所在处）
DEPLOY_DIR = os.environ.get("NAS_DEPLOY_DIR", "/volume2/docker/ezbk")

# ---- 尝试加载本地个人配置覆盖 ----
try:
    from nas_config_local import *  # noqa: F401,F403
except ImportError:
    pass

# ---- SSH 助手 ----


def parse_creds(path):
    """解析凭据文件 -> (ip, port, user, password)"""
    with open(path, encoding="utf-8") as f:
        parts = f.read().split()
    if len(parts) < 4:
        raise SystemExit(f"凭据文件格式不对（需 IP 端口 用户 密码）：{path}")
    return parts[0], int(parts[1]), parts[2], parts[3]


def resolve_creds(argv):
    """从 命令行参数 > 环境变量 > 本地覆盖配置 解析凭据文件路径。"""
    positional = [a for a in argv if not a.startswith("--")]
    path = positional[0] if positional else CRED_FILE
    if not path:
        raise SystemExit(
            "未配置 NAS 凭据文件。请任选其一：\n"
            "  1. python scripts/nas_deploy.py <凭据文件路径>\n"
            "  2. 设置环境变量 NAS_CRED_FILE=<路径>\n"
            "  3. 创建 scripts/nas_config.local.py 定义 CRED_FILE（已 gitignore）\n"
            "凭据文件内容格式：IP 端口 用户 密码（一行，空格分隔）"
        )
    return path


def ssh_exec(cli, cmd, timeout=120):
    _, so, se = cli.exec_command(cmd, timeout=timeout)
    out = so.read().decode("utf-8", "replace")
    err = se.read().decode("utf-8", "replace")
    return out, err


def upload_file(cli, local_path, remote_path, chunk_size=48 * 1024):
    """把本地文件传到 NAS。群晖默认禁用 SFTP 子系统，故用 base64 分块经 exec 通道写入。

    注意：命令长度受 NAS sshd / shell 限制（实测 ~64KB 以上会被截断），
    故 chunk_size 取 48KB（base64 后约 64KB），并在末尾做整文件大小校验。
    """
    total = os.path.getsize(local_path)
    print(f"==> 上传 {os.path.basename(local_path)} ({total/1024:.1f} KB) -> {remote_path}")
    ssh_exec(cli, f": > '{remote_path}'")
    sent = 0
    with open(local_path, "rb") as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            b64 = base64.b64encode(chunk).decode("ascii")
            out, err = ssh_exec(
                cli, f"printf '%s' '{b64}' | base64 -d >> '{remote_path}'", timeout=120)
            if err.strip():
                print("\n[warn]", err[:200])
            sent += len(chunk)
            pct = sent * 100 // total
            print(f"\r    {sent}/{total} ({pct}%)", end="", flush=True)
    print()
    out, _ = ssh_exec(cli, f"wc -c < '{remote_path}'")
    try:
        remote_size = int(out.strip())
    except ValueError:
        remote_size = -1
    if remote_size != total:
        raise SystemExit(f"上传校验失败：本地 {total} 字节，远端 {remote_size} 字节")
    print("==> 上传完成（大小校验通过）")


def connect_any(cli, port, user, password, hosts):
    """依次尝试连接候选地址，返回 (client, host) 或 None。"""
    for host in dict.fromkeys(hosts):
        try:
            print(f"==> 尝试连接 {host}:{port}")
            cli.connect(host, port=port, username=user,
                        password=password, timeout=12)
            print(f"==> 已连接 {host}")
            return cli, host
        except Exception as e:
            print(f"    失败：{type(e).__name__}: {e}")
    return None
