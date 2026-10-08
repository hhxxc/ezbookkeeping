"""把 NestKeep 原生 App 的 IPA 与新版本清单发布到 NAS，供手机从自有域名更新。

手机在国内环境无法直接访问 github.com，故：
  1. 把 IPA 产物从 GitHub Release/Artifact 下载到本机
  2. 通过 SSH/SFTP 上传到 NAS 的 /volume2/docker/ezbk/nestkeep/ 目录
     （该目录已挂载进容器 -> /ezbookkeeping/data/nestkeep/，重建容器不丢）
  3. 写 latest.json 清单（version / ipaUrl / releaseUrl / notes）

App 侧更新检测优先读 {serverURL}/api/nestkeep/latest.json；
点击下载时走 {serverURL}/api/proxy/github/download?url=<github-ipa-url> 反代，
即「自己的域名中转 GitHub」，全程不需要手机能访问 GitHub。

用法：
    python scripts/nas_publish_nestkeep.py --version 1.6.3 [--ipa 本地IPA路径]
        [--github-ipa-url <直链>] [--notes "更新说明"] [--cred 凭据文件]

  - 不给 --ipa 时，脚本会尝试用 gh 从 GitHub Release tag v<version> 下载对应 IPA；
  - ipaUrl 默认指向 GitHub Release 资产，客户端由后端反代读取。

凭据文件默认取用户桌面的「REDACTED nas hhs.txt」，格式：IP 端口 用户 密码。
凭据不入库；本机无 sshpass，用 paramiko（已装）做非交互 SSH/SFTP。
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time

import paramiko

CRED_FILE = r"REDACTED"
GITHUB_REPO = "hhxxc/ezbookkeeping"
# NAS 上对外发布目录（会挂进容器 /ezbookkeeping/data/nestkeep）
REMOTE_DIR = "/volume2/docker/ezbk/nestkeep"
# 公网入口（ddnsto 隧道）
PUBLIC_BASE = os.environ.get("NESTKEEP_PUBLIC_BASE", "https://example-server.invalid")
# NAS 的 SSH 可达地址（本机所在网段可能变化，按需覆盖）
DEFAULT_SSH_HOST = os.environ.get("NESTKEEP_NAS_HOST", "REDACTED")


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", **kw)


def parse_creds(path):
    with open(path, encoding="utf-8") as f:
        parts = f.read().split()
    if len(parts) < 4:
        raise SystemExit(f"凭据文件格式不对（需 IP 端口 用户 密码）：{path}")
    return parts[0], int(parts[1]), parts[2], parts[3]


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
    t0 = time.time()
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
        raise SystemExit(f"上传大小不一致：本地 {total} / 远端 {remote_size}")
    print(f"    完成，用时 {time.time()-t0:.1f}s（大小校验通过）")


def write_remote_text(cli, text, remote_path):
    """把文本写入远端文件（base64 中转，避免引号转义问题）。"""
    b64 = base64.b64encode(text.encode("utf-8")).decode("ascii")
    tmp = remote_path + ".tmp"
    ssh_exec(cli, f"printf '%s' '{b64}' | base64 -d > '{tmp}' && "
                  f"chmod 644 '{tmp}' && mv -f '{tmp}' '{remote_path}'")


def download_ipa_from_release(version, out_dir):
    """用 gh CLI 从 Release v<version> 下载 IPA 到 out_dir，返回本地路径。"""
    tag = version if version.startswith("v") else "v" + version
    os.makedirs(out_dir, exist_ok=True)
    print(f"==> 下载 Release {tag} 的 IPA 到 {out_dir}")
    r = run(["gh", "release", "download", tag, "--repo", GITHUB_REPO,
             "--pattern", "*.ipa", "--dir", out_dir, "--clobber"])
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr, file=sys.stderr)
        raise SystemExit(f"下载 Release {tag} 失败；可用 --ipa 指定本地 IPA，"
                         f"或确认 tag 与资产名。")
    for name in os.listdir(out_dir):
        if name.lower().endswith(".ipa"):
            return os.path.join(out_dir, name)
    raise SystemExit("下载完成但未找到 .ipa 文件")


def release_ipa_url(version):
    """构造 GitHub Release 里 IPA 资产的直链（若资产名未知则回退到 releases 页）。"""
    tag = version if version.startswith("v") else "v" + version
    r = run(["gh", "release", "view", tag, "--repo", GITHUB_REPO,
             "--json", "assets,url"])
    if r.returncode != 0:
        return None
    try:
        info = json.loads(r.stdout)
    except Exception:
        return None
    for a in info.get("assets", []):
        if a.get("name", "").lower().endswith(".ipa"):
            return a.get("url")  # browser_download_url
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True, help="语义化版本，如 1.6.3")
    ap.add_argument("--ipa", help="本地 IPA 路径（不给则从 GitHub Release 下载）")
    ap.add_argument("--github-ipa-url", help="覆盖 IPA 的 GitHub 直链（默认自动查）")
    ap.add_argument("--notes", default="", help="更新说明")
    ap.add_argument("--cred", default=CRED_FILE, help="NAS 凭据文件")
    ap.add_argument("--host", default=DEFAULT_SSH_HOST, help="NAS SSH 地址")
    ap.add_argument("--flavor", default="dev", choices=["dev", "stable"],
                    help="变体：dev=巢记+ / stable=巢记+ 稳定版。各自写 latest-<flavor>.json，"
                         "App 按自身 Bundle ID 读取本变体清单，避免跨变体互相提示更新")
    ap.add_argument("--no-upload-ipa", action="store_true",
                    help="只更新清单，不上传 IPA 文件")
    args = ap.parse_args()

    version = args.version.lstrip("vV")
    flavor = args.flavor
    # stable 变体的 Release tag 带 -stable 后缀（见 build-native-ios.yml）
    tag = "v" + version + ("-stable" if flavor == "stable" else "")

    # 1) 准备本地 IPA
    ipa_path = args.ipa
    if not ipa_path and not args.no_upload_ipa:
        ipa_path = download_ipa_from_release(tag, os.path.join(os.getcwd(), "dist-ipa"))
    if ipa_path and not os.path.isfile(ipa_path):
        raise SystemExit(f"找不到 IPA：{ipa_path}")

    # 2) 组装清单
    ipa_gh_url = args.github_ipa_url or release_ipa_url(tag)
    manifest = {
        "version": version,
        "variant": flavor,
        "releaseUrl": f"https://github.com/{GITHUB_REPO}/releases/tag/{tag}",
        "notes": args.notes,
    }
    # 客户端下载地址：
    #   - 若同时把 IPA 上传到 NAS，则 ipaUrl 指向 NAS 静态文件（最稳，不经 GitHub）
    #   - 否则指向后端反代 GitHub 的地址
    if ipa_path and not args.no_upload_ipa:
        manifest["ipaUrl"] = f"{PUBLIC_BASE}/api/nestkeep/{os.path.basename(ipa_path)}"
    elif ipa_gh_url:
        manifest["ipaUrl"] = f"{PUBLIC_BASE}/api/proxy/github/download?url={ipa_gh_url}"
    else:
        manifest["ipaUrl"] = f"{PUBLIC_BASE}/api/proxy/github/download"

    print("==> latest.json 内容：")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))

    # 3) 上传到 NAS
    _, port, user, password = parse_creds(args.cred)
    cli = paramiko.SSHClient()
    cli.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"==> 连接 NAS {args.host}:{port}")
    cli.connect(args.host, port=port, username=user, password=password, timeout=20)

    _, so, se = cli.exec_command(
        f"mkdir -p '{REMOTE_DIR}' && chmod 755 '{REMOTE_DIR}'", timeout=30)
    so.read()
    err = se.read().decode("utf-8", "replace")
    if err.strip():
        print("[warn]", err)

    if ipa_path and not args.no_upload_ipa:
        remote_ipa = f"{REMOTE_DIR}/{os.path.basename(ipa_path)}"
        upload_file(cli, ipa_path, remote_ipa)
        # 只保留最新的 IPA，避免目录膨胀
        keep = os.path.basename(ipa_path)
        out, _ = ssh_exec(cli, f"ls -1 '{REMOTE_DIR}'")
        for name in out.splitlines():
            name = name.strip()
            if name.lower().endswith(".ipa") and name != keep:
                print(f"    清理旧包 {name}")
                ssh_exec(cli, f"rm -f '{REMOTE_DIR}/{name}'")

    # 写 latest.json（临时文件 -> 原子改名，避免读到半截）
    write_remote_text(cli, json.dumps(manifest, ensure_ascii=False, indent=2),
                      f"{REMOTE_DIR}/latest.json")

    # 4) 验证：目录内容 + 通过公网域名访问后端接口
    print("==> 验证（NAS 目录内容）")
    out, _ = ssh_exec(cli, f"ls -la '{REMOTE_DIR}'")
    print(out)

    # 容器内 curl（docker 在群晖需 sudo 或完整路径）
    print("==> 验证后端接口（容器内）")
    for dcmd in (
        "/usr/local/bin/docker exec ezbookkeeping sh -c 'wget -qO- http://127.0.0.1:15080/api/nestkeep/latest.json'",
        "sudo /usr/local/bin/docker exec ezbookkeeping sh -c 'wget -qO- http://127.0.0.1:15080/api/nestkeep/latest.json'",
    ):
        body, err = ssh_exec(cli, dcmd, timeout=60)
        if body.strip() and "permission denied" not in (body + err).lower():
            print(body)
            break
    else:
        print("（容器内校验跳过；请以公网接口为准）")
    cli.close()

    # 直接从本机走公网域名验证（最能反映手机侧真实情况）
    print("==> 验证公网接口（本机请求）")
    r = run(["curl", "-s", "--max-time", "20",
             f"{PUBLIC_BASE}/api/nestkeep/latest.json"])
    print(r.stdout.strip() or "(空响应)")

    print()
    print("==> 完成。手机侧更新入口：")
    print(f"    {PUBLIC_BASE}/api/nestkeep/latest.json")
    print(f"    IPA 下载：{manifest['ipaUrl']}")


if __name__ == "__main__":
    main()
