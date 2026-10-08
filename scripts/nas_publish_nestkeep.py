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
    ap.add_argument("--no-upload-ipa", action="store_true",
                    help="只更新 latest.json，不上传 IPA 文件")
    args = ap.parse_args()

    version = args.version.lstrip("vV")
    tag = "v" + version

    # 1) 准备本地 IPA
    ipa_path = args.ipa
    if not ipa_path and not args.no_upload_ipa:
        ipa_path = download_ipa_from_release(version, os.path.join(os.getcwd(), "dist-ipa"))
    if ipa_path and not os.path.isfile(ipa_path):
        raise SystemExit(f"找不到 IPA：{ipa_path}")

    # 2) 组装清单
    ipa_gh_url = args.github_ipa_url or release_ipa_url(version)
    manifest = {
        "version": version,
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

    sftp = cli.open_sftp()

    if ipa_path and not args.no_upload_ipa:
        remote_ipa = f"{REMOTE_DIR}/{os.path.basename(ipa_path)}"
        size = os.path.getsize(ipa_path)
        print(f"==> 上传 IPA {os.path.basename(ipa_path)} ({size/1024:.1f} KB) -> {remote_ipa}")
        t0 = time.time()
        sftp.put(ipa_path, remote_ipa)
        print(f"    完成，用时 {time.time()-t0:.1f}s")
        # 只保留最新的 IPA，避免目录膨胀
        sftp.chmod(remote_ipa, 0o644)
        sftp.close()
        sftp = cli.open_sftp()
        keep = os.path.basename(ipa_path)
        for name in sftp.listdir(REMOTE_DIR):
            if name.lower().endswith(".ipa") and name != keep:
                print(f"    清理旧包 {name}")
                sftp.remove(f"{REMOTE_DIR}/{name}")

    # 写 latest.json（临时文件 -> 原子改名，避免读到半截）
    tmp = f"{REMOTE_DIR}/.latest.json.tmp"
    with sftp.open(tmp, "w") as f:
        f.write(json.dumps(manifest, ensure_ascii=False, indent=2))
    sftp.chmod(tmp, 0o644)
    sftp.rename(tmp, f"{REMOTE_DIR}/latest.json")
    sftp.close()

    # 4) 验证：容器内可读 + 后端接口可访问
    docker = "/usr/local/bin/docker"
    print("==> 验证（目录内容）")
    _, so, se = cli.exec_command(f"ls -la '{REMOTE_DIR}'", timeout=30)
    print(so.read().decode("utf-8", "replace"))

    print("==> 验证后端接口（容器内 curl）")
    _, so, se = cli.exec_command(
        f"{docker} exec ezbookkeeping sh -c "
        f"'wget -qO- http://127.0.0.1:15080/api/nestkeep/latest.json || "
        f"curl -s http://127.0.0.1:15080/api/nestkeep/latest.json'", timeout=60)
    body = so.read().decode("utf-8", "replace")
    err = se.read().decode("utf-8", "replace")
    print(body or err)
    cli.close()

    print()
    print("==> 完成。手机侧更新入口：")
    print(f"    {PUBLIC_BASE}/api/nestkeep/latest.json")


if __name__ == "__main__":
    main()
