"""生成 NestKeep iOS App 图标（全出血 / full-bleed）。

iOS 主屏图标会自己裁剪圆角，所以素材必须是**无边距满幅**的方块——
原始 SVG 有 16px 透明内边距，装到手机上就成了一圈白边。

这里用 Pillow 直接按 SVG 的设计语言重绘：
  - 满幅青绿渐变底（07c160 -> 06ad56）
  - 居中白色实心房子（屋顶三角 + 墙体 + 青绿门）
并输出 AppIcon.appiconset 需要的全部尺寸。

用法：python scripts/gen_nestkeep_appicon.py
"""

import os

from PIL import Image, ImageDraw

OUT_DIR = os.path.join(os.path.dirname(__file__), "..",
                       "ios-app", "NestKeep", "Assets.xcassets",
                       "AppIcon.appiconset")

# iOS 需要的 (pt, scale) 组合；83.5pt 是 iPad Pro 图标，px 会四舍五入成 167
SIZES = [
    (20, 2), (20, 3),
    (29, 2), (29, 3),
    (40, 2), (40, 3),
    (60, 2), (60, 3),
    (20, 1), (29, 1), (40, 1),
    (76, 1), (76, 2),
    (83.5, 2),
    (1024, 1),
]

BG_TOP = (7, 193, 96)      # #07c160
BG_BOTTOM = (6, 173, 86)   # #06ad56
FILL = (255, 255, 255)
DOOR = (7, 193, 96)

# 房子几何（相对 512 画布，与 SVG 的 transform(256,270) 一致）
# 对应 SVG: polygon 0,-130 -130,10 130,10；walls y=10..115；door y=45..115
ROOF = [(-130, 10), (130, 10), (0, -130)]
WALL = (-85, 10, 85, 115)              # x1,y1,x2,y2
DOOR_RECT = (-32, 45, 32, 115)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(size):
    img = Image.new("RGB", (size, size), BG_TOP)
    d = ImageDraw.Draw(img)

    # 竖向渐变（对角线近似：按行插值）
    for y in range(size):
        t = y / max(1, size - 1)
        d.line([(0, y), (size, y)], fill=lerp(BG_TOP, BG_BOTTOM, t))

    s = size / 512.0            # 缩放系数
    ox, oy = 256 * s, 270 * s   # 房子原点在画布中的位置

    def pt(x, y):
        return (ox + x * s, oy + y * s)

    # 屋顶（三角）
    d.polygon([pt(*p) for p in ROOF], fill=FILL)
    # 墙体
    x1, y1, x2, y2 = WALL
    r = max(1, int(6 * s))
    d.rounded_rectangle([pt(x1, y1), pt(x2, y2)], radius=r, fill=FILL)
    # 门
    dx1, dy1, dx2, dy2 = DOOR_RECT
    d.rounded_rectangle([pt(dx1, dy1), pt(dx2, dy2)], radius=max(1, int(6 * s)), fill=DOOR)

    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    made = set()
    for pt_, scale in SIZES:
        px = round(pt_ * scale)
        key = (pt_, scale)
        if key in made:
            continue
        made.add(key)
        img = render(px)
        # 文件名保留原始 pt 写法（83.5 -> 83.5）
        pt_str = f"{pt_:g}"
        name = f"icon-{pt_str}x{pt_str}@{scale}x.png"
        img.save(os.path.join(OUT_DIR, name), "PNG")
        print(f"  {name}  ({px}x{px})")
    print(f"\n共生成 {len(made)} 张图标 -> {os.path.abspath(OUT_DIR)}")


if __name__ == "__main__":
    main()
