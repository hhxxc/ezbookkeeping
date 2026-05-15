"""
Generate PWA icons and splash screens for the NestKeep (巢记) app.

Fixes:
1. iOS home screen icon black border - icons now fill entire canvas with no transparency
2. Splash screen shows old "ezbookkeeping" branding - regenerated with new nest+eggs logo
"""

import os
import math
from PIL import Image, ImageDraw, ImageFont

# Paths
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBLIC_DIR = os.path.join(BASE_DIR, 'public')
IMG_DIR = os.path.join(PUBLIC_DIR, 'img')
SPLASH_DIR = os.path.join(IMG_DIR, 'splash_screens')
FONT_PATH = 'C:/Windows/Fonts/simhei.ttf'
FONT_PATH_LIGHT = 'C:/Windows/Fonts/STXIHEI.TTF'

# Brand colors
GRADIENT_START = (198, 126, 72)  # #c67e48
GRADIENT_MID = (212, 149, 90)   # #d4955a
GRADIENT_END = (232, 168, 124)  # #e8a87c
NEST_COLOR = (180, 115, 58)     # brown
NEST_HIGHLIGHT = (212, 165, 116)
EGG_COLOR = (255, 255, 255)
EGG_SHADOW = (248, 244, 238)
TEXT_COLOR = (255, 255, 255)


def create_gradient(size, start_color, end_color, angle=135):
    """Create a linear gradient background."""
    w, h = size
    img = Image.new('RGB', size)
    pixels = img.load()

    # Convert angle to direction vector
    rad = math.radians(angle)
    dx = math.cos(rad)
    dy = math.sin(rad)

    for y in range(h):
        for x in range(w):
            # Projection distance along gradient direction
            t = (x * dx + y * dy) / (w * abs(dx) + h * abs(dy))
            t = max(0, min(1, t))

            r = int(start_color[0] + (end_color[0] - start_color[0]) * t)
            g = int(start_color[1] + (end_color[1] - start_color[1]) * t)
            b = int(start_color[2] + (end_color[2] - start_color[2]) * t)

            pixels[x, y] = (r, g, b)

    return img


def draw_nest_logo(draw, cx, cy, scale):
    """Draw the nest + eggs logo using PIL primitives."""
    s = scale

    # Nest body - semi-ellipse
    nest_top = cy + 10 * s
    nest_rx = 160 * s
    nest_ry = 35 * s

    # Nest bowl (filled semi-ellipse)
    bbox = [
        cx - nest_rx,
        nest_top - nest_ry * 0.5,
        cx + nest_rx,
        nest_top + nest_ry * 2.5
    ]
    draw.ellipse(bbox, fill=(250, 246, 240), outline=(212, 165, 116), width=max(1, int(6 * s)))

    # Nest rim highlight
    highlight_bbox = [
        cx - nest_rx + 8 * s,
        nest_top - nest_ry * 0.5 + 4 * s,
        cx + nest_rx - 8 * s,
        nest_top + nest_ry * 0.8
    ]
    draw.arc(highlight_bbox, 200, 340, fill=(255, 255, 255, 102), width=max(1, int(3 * s)))

    # Nest twig details (darker lines across the nest)
    twig_y_offsets = [15, 35, 55, 70]
    for i, y_off in enumerate(twig_y_offsets):
        line_y = nest_top + y_off * s
        twig_width = nest_rx * (0.9 - i * 0.15)
        draw.arc(
            [cx - twig_width, line_y - 5 * s, cx + twig_width, line_y + 5 * s],
            190, 350,
            fill=(180, 140, 90, 150),
            width=max(1, int((4 - i * 0.5) * s))
        )

    # Nest interior shadow
    shadow_bbox = [
        cx - 120 * s,
        nest_top + 5 * s,
        cx + 120 * s,
        nest_top + 35 * s
    ]
    draw.ellipse(shadow_bbox, fill=(184, 115, 58, 25))

    # Three eggs
    egg_positions = [
        (-55*s, -8*s, -12),  # left
        (0, -18*s, 0),        # center
        (55*s, -6*s, 10),     # right
    ]

    egg_cy = nest_top - 30 * s

    for ex, ey, rotation in egg_positions:
        egg_x = cx + ex
        egg_y = egg_cy + ey
        rx = 28 * s
        ry = 38 * s

        # Egg body
        egg_bbox = [egg_x - rx, egg_y - ry, egg_x + rx, egg_y + ry]

        if rotation != 0:
            # For rotated eggs, draw as a rotated ellipse using a separate image
            egg_img = Image.new('RGBA', (int(rx * 4), int(ry * 4)), (0, 0, 0, 0))
            egg_draw = ImageDraw.Draw(egg_img)
            egg_cx_img = rx * 2
            egg_cy_img = ry * 2
            egg_draw.ellipse(
                [egg_cx_img - rx, egg_cy_img - ry, egg_cx_img + rx, egg_cy_img + ry],
                fill=(255, 255, 255)
            )
            # Highlight
            egg_draw.ellipse(
                [egg_cx_img - rx*0.35, egg_cy_img - ry*0.5,
                 egg_cx_img + rx*0.42, egg_cy_img - ry*0.1],
                fill=(255, 255, 255, 180)
            )
            egg_img = egg_img.rotate(rotation, expand=False, resample=Image.BICUBIC)
            # Paste rotated egg
            paste_x = int(egg_x - egg_img.width / 2)
            paste_y = int(egg_y - egg_img.height / 2)
            # We need to paste onto the main image
            # This is complicated - for simplicity, let's just draw ellipses without rotation
            # since the rotation is subtle
            draw.ellipse(egg_bbox, fill=(255, 255, 255), outline=(240, 235, 230), width=max(1, int(1*s)))
            highlight_bbox = [
                egg_x - rx*0.35, egg_y - ry*0.45,
                egg_x + rx*0.45, egg_y - ry*0.05
            ]
            draw.ellipse(highlight_bbox, fill=(255, 255, 255))
        else:
            draw.ellipse(egg_bbox, fill=(255, 255, 255), outline=(240, 235, 230), width=max(1, int(1*s)))
            # Egg highlight
            highlight_bbox = [
                egg_x - rx*0.38, egg_y - ry*0.48,
                egg_x + rx*0.42, egg_y - ry*0.05
            ]
            draw.ellipse(highlight_bbox, fill=(255, 255, 255))


def load_chinese_font(size):
    """Load a Chinese font, falling back to default."""
    try:
        return ImageFont.truetype(FONT_PATH, size)
    except Exception:
        try:
            return ImageFont.truetype(FONT_PATH_LIGHT, size)
        except Exception:
            return ImageFont.load_default()


def generate_icons():
    """Generate iOS/PWA icons that fill the entire canvas (no transparent padding)."""
    print("Generating icons...")

    icon_sizes = [180, 192, 512]
    filenames = {
        180: 'apple-touch-icon-180.png',
        192: 'nestkeep-logo-192.png',
        512: 'nestkeep-logo-512.png',
    }

    for size in icon_sizes:
        img = create_gradient((size, size), GRADIENT_START, GRADIENT_END)
        draw = ImageDraw.Draw(img, 'RGBA')
        scale = size / 512.0
        draw_nest_logo(draw, size / 2, size / 2 - 15 * scale, scale)

        filepath = os.path.join(IMG_DIR, filenames[size])
        img.save(filepath, 'PNG')
        print(f"  Created {filenames[size]} ({size}x{size})")


def generate_splash_screens():
    """Generate all splash screen images with the new branding."""
    print("Generating splash screens...")

    # Device definitions: (name, css_width, css_height, pixel_ratio)
    devices = [
        # iPhones
        ('iPhone_17_Pro_Max__iPhone_16_Pro_Max', 440, 956, 3),
        ('iPhone_17_Pro__iPhone_17__iPhone_16_Pro', 402, 874, 3),
        ('iPhone_17_Air__iPhone_16_Plus__iPhone_15_Pro_Max__iPhone_15_Plus__iPhone_14_Pro_Max', 430, 932, 3),
        ('iPhone_16__iPhone_15_Pro__iPhone_15__iPhone_14_Pro', 393, 852, 3),
        ('iPhone_14_Plus__iPhone_13_Pro_Max__iPhone_12_Pro_Max', 428, 926, 3),
        ('iPhone_16e__iPhone_14__iPhone_13_Pro__iPhone_13__iPhone_12_Pro__iPhone_12', 390, 844, 3),
        ('iPhone_13_mini__iPhone_12_mini__iPhone_11_Pro__iPhone_XS__iPhone_X', 375, 812, 3),
        ('iPhone_11_Pro_Max__iPhone_XS_Max', 414, 896, 3),
        ('iPhone_11__iPhone_XR', 414, 896, 2),
        ('iPhone_8_Plus__iPhone_7_Plus__iPhone_6s_Plus__iPhone_6_Plus', 414, 736, 3),
        ('iPhone_8__iPhone_7__iPhone_6s__iPhone_6__4.7__iPhone_SE', 375, 667, 2),
        ('4__iPhone_SE__iPod_touch_5th_generation_and_later', 320, 568, 2),
        # iPads
        ('13__iPad_Pro_M4', 1032, 1376, 2),
        ('12.9__iPad_Pro', 1024, 1366, 2),
        ('11__iPad_Pro_M4', 834, 1210, 2),
        ('11__iPad_Pro__10.5__iPad_Pro', 834, 1194, 2),
        ('10.9__iPad_Air', 820, 1180, 2),
        ('10.5__iPad_Air', 834, 1112, 2),
        ('10.2__iPad', 810, 1080, 2),
        ('9.7__iPad_Pro__7.9__iPad_mini__9.7__iPad_Air__9.7__iPad', 768, 1024, 2),
        ('8.3__iPad_Mini', 744, 1133, 2),
    ]

    os.makedirs(SPLASH_DIR, exist_ok=True)

    for name, css_w, css_h, ratio in devices:
        portrait_w = css_w * ratio
        portrait_h = css_h * ratio
        landscape_w = css_h * ratio
        landscape_h = css_w * ratio

        for orientation, w, h in [('portrait', portrait_w, portrait_h), ('landscape', landscape_w, landscape_h)]:
            img = create_gradient((w, h), GRADIENT_START, GRADIENT_END)

            # Determine logo scale based on the shorter dimension
            min_dim = min(w, h)
            logo_scale = min_dim / 600.0  # Logo at ~600px reference size

            # Determine logo position (centered, slightly above center to leave room for text)
            logo_cx = w / 2
            logo_cy = h * 0.42

            draw = ImageDraw.Draw(img, 'RGBA')
            draw_nest_logo(draw, logo_cx, logo_cy, logo_scale)

            # Draw "巢记" text below the logo
            chinese_font_size = int(min_dim * 0.1)
            english_font_size = int(min_dim * 0.04)

            try:
                font_chinese = load_chinese_font(chinese_font_size)

                # "巢记" text
                text_bbox = draw.textbbox((0, 0), '巢记', font=font_chinese)
                text_w = text_bbox[2] - text_bbox[0]
                text_h = text_bbox[3] - text_bbox[1]
                text_x = (w - text_w) / 2
                text_y = h * 0.62

                # Text shadow
                draw.text((text_x + 2, text_y + 2), '巢记', fill=(0, 0, 0, 60), font=font_chinese)
                # Text
                draw.text((text_x, text_y), '巢记', fill=TEXT_COLOR, font=font_chinese)

                # "NestKeep" subtitle
                font_english = ImageFont.truetype(FONT_PATH, english_font_size) if os.path.exists(FONT_PATH) else load_chinese_font(english_font_size)
                sub_bbox = draw.textbbox((0, 0), 'NestKeep', font=font_english)
                sub_w = sub_bbox[2] - sub_bbox[0]
                sub_x = (w - sub_w) / 2
                sub_y = text_y + text_h + min_dim * 0.02
                draw.text((sub_x, sub_y), 'NestKeep', fill=(255, 255, 255, 200), font=font_english)

            except Exception as e:
                print(f"  Warning: Could not render text for {name} {orientation}: {e}")

            filename = f'{name}_{orientation}.png'
            filepath = os.path.join(SPLASH_DIR, filename)
            img.save(filepath, 'PNG')
            print(f"  Created {filename} ({w}x{h})")

    print(f"\nTotal: {len(devices) * 2} splash screen images generated")


if __name__ == '__main__':
    generate_icons()
    print()
    generate_splash_screens()
    print("\nDone! All PWA assets generated.")
