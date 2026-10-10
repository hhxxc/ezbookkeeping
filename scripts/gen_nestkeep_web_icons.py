"""生成 Web 端 favicon / touchicon / apple-touch-icon（与 iOS App 图标同一设计）。

设计语言与 scripts/gen_nestkeep_appicon.py（原生 worktree）完全一致：
  - 满幅青绿渐变底（07c160 -> 06ad56）
  - 居中白色实心房子（屋顶三角 + 墙体 + 青绿门）

输出：
  - public/favicon.png              32x32，圆角+透明底（浏览器标签页观感）
  - public/favicon.ico              16/32/48 多尺寸
  - public/touchicon.png            180x180 满幅（遗留文件，保持更新）
  - public/img/apple-touch-icon-180.png  180x180 满幅（iOS 自行裁圆角，勿自带圆角）

用法：python scripts/gen_nestkeep_web_icons.py
"""

import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "public")

BG_TOP = (7, 193, 96)      # #07c160
BG_BOTTOM = (6, 173, 86)   # #06ad56
FILL = (255, 255, 255)
DOOR = (7, 193, 96)

# 房子几何（相对 512 画布，与 nestkeep-logo.svg 的 transform(256,270) 一致）
ROOF = [(-130, 10), (130, 10), (0, -130)]
WALL = (-85, 10, 85, 115)
DOOR_RECT = (-32, 45, 32, 115)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(size):
    """满幅方块（RGB），与 App 图标 render() 同一实现。"""
    img = Image.new("RGB", (size, size), BG_TOP)
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(1, size - 1)
        d.line([(0, y), (size, y)], fill=lerp(BG_TOP, BG_BOTTOM, t))

    s = size / 512.0
    ox, oy = 256 * s, 270 * s

    d.polygon([((ox + x * s), (oy + y * s)) for x, y in ROOF], fill=FILL)
    d.rectangle([ox + WALL[0] * s, oy + WALL[1] * s,
                 ox + WALL[2] * s, oy + WALL[3] * s], fill=FILL)
    d.rectangle([ox + DOOR_RECT[0] * s, oy + DOOR_RECT[1] * s,
                 ox + DOOR_RECT[2] * s, oy + DOOR_RECT[3] * s], fill=DOOR)
    return img


def rounded(img, radius_ratio=0.223):
    """加圆角蒙版（透明底），比例对齐 App 图标 SVG 的 rx/边长=112/512。"""
    size = img.size[0]
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1],
                        radius=round(size * radius_ratio), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main():
    # favicon.png（32x32 圆角）
    rounded(render(256).resize((32, 32), Image.LANCZOS)).save(
        os.path.join(OUT, "favicon.png"))

    # favicon.ico（16/32/48 多尺寸）
    ico_sizes = [16, 32, 48]
    frames = [rounded(render(s * 8).resize((s, s), Image.LANCZOS))
              for s in ico_sizes]
    frames[-1].save(os.path.join(OUT, "favicon.ico"),
                    format="ICO", sizes=[(s, s) for s in ico_sizes])

    # touchicon.png / apple-touch-icon-180.png（180 满幅，iOS 自裁圆角）
    full = render(180)
    full.save(os.path.join(OUT, "touchicon.png"))
    full.save(os.path.join(OUT, "img", "apple-touch-icon-180.png"))

    print("done: favicon.png / favicon.ico / touchicon.png / img/apple-touch-icon-180.png")


if __name__ == "__main__":
    main()
