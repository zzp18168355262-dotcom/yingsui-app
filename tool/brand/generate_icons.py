#!/usr/bin/env python3
"""影随 / YingSui —— 应用图标生成器。

用途：把选定的图标方案渲染成全平台所需的全部尺寸，直接覆盖到项目里。

用法：
  python3 tool/brand/generate_icons.py --concept C --out <项目根目录>

支持的方案（--concept）：
  C  三音柱（深墨底 + 青/金/紫）
  E  双重弧线（跟读回声）
  F  渐变拖尾

生成内容：
  assets/img/app_icon.png                  1024 源图
  assets/img/app_icon_foreground.png       Android 自适应前景
  android/.../mipmap-*/ic_launcher.png     各密度
  ios/Runner/Assets.xcassets/AppIcon...     iOS 全套
  macos/Runner/Assets.xcassets/AppIcon...   macOS 全套
  windows/runner/resources/app_icon.ico     Windows
  web/icons/*.png、web/favicon.png          Web
"""
import argparse
import json
import os
from PIL import Image, ImageDraw

SCALE = 4  # 高倍超采样，缩放后边缘干净

JADE = (0x00, 0x69, 0x5C)
JADE_LT = (0x3D, 0xD6, 0xC0)
JADE_MID = (0x00, 0x89, 0x7B)
AMBER = (0xF2, 0xA0, 0x07)
AMBER_LT = (0xFF, 0xC2, 0x4B)
VIOLET = (0x7C, 0x5C, 0xFF)
VIOLET_LT = (0xA7, 0x8B, 0xFA)
WHITE = (0xFF, 0xFF, 0xFF)
DARK = (0x12, 0x16, 0x18)


def rounded_mask(size, radius_ratio):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255
    )
    return m


def mix(c0, c1, t):
    return tuple(int(c0[k] + (c1[k] - c0[k]) * t) for k in range(3))


def concept_c(size, background=DARK, mask_ratio=0.235):
    """三音柱：深墨底 + 青/金/紫。"""
    S = size * SCALE
    body = Image.new("RGB", (S, S), background)
    d = ImageDraw.Draw(body)
    heights = (0.30, 0.46, 0.30)
    colors = (JADE_LT, AMBER_LT, VIOLET_LT)
    bw = S * 0.112
    gap = S * 0.082
    x = (S - (bw * 3 + gap * 2)) / 2
    for i, h in enumerate(heights):
        hh = S * h
        d.rounded_rectangle(
            [x, S / 2 - hh / 2, x + bw, S / 2 + hh / 2],
            radius=int(bw / 2),
            fill=colors[i],
        )
        x += bw + gap
    if mask_ratio is None:
        return body.resize((size, size), Image.LANCZOS)
    out = Image.new("RGB", (S, S), WHITE)
    out.paste(body, (0, 0), rounded_mask(S, mask_ratio))
    return out.resize((size, size), Image.LANCZOS)


def concept_e(size, background=DARK, mask_ratio=0.235):
    """双重弧线：两道错位弧 + 白色声源点。"""
    S = size * SCALE
    body = Image.new("RGB", (S, S), background)
    d = ImageDraw.Draw(body)
    lw = int(S * 0.082)
    for rad, col, start, end in (
        (S * 0.205, JADE_LT, 150, 380),
        (S * 0.330, AMBER_LT, 150, 330),
    ):
        d.arc(
            [S / 2 - rad, S / 2 - rad, S / 2 + rad, S / 2 + rad],
            start=start,
            end=end,
            fill=col,
            width=lw,
        )
    r = S * 0.062
    d.ellipse([S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r], fill=WHITE)
    if mask_ratio is None:
        return body.resize((size, size), Image.LANCZOS)
    out = Image.new("RGB", (S, S), WHITE)
    out.paste(body, (0, 0), rounded_mask(S, mask_ratio))
    return out.resize((size, size), Image.LANCZOS)


def concept_f(size, background=(0xF8, 0xF9, 0xFA), mask_ratio=0.235):
    """渐变拖尾：三条同形横条由实到虚 + 琥珀点。"""
    S = size * SCALE
    body = Image.new("RGB", (S, S), background)
    d = ImageDraw.Draw(body)
    bw = S * 0.50
    bh = S * 0.115
    x = (S - bw) / 2
    y0 = S * 0.245
    gap = S * 0.075
    r = int(bh / 2)
    shades = (JADE, mix(JADE, WHITE, 0.45), mix(JADE, WHITE, 0.72))
    for i in range(3):
        y = y0 + i * (bh + gap)
        d.rounded_rectangle([x, y, x + bw, y + bh], radius=r, fill=shades[i])
    rr = S * 0.062
    cx = x + bw + rr * 0.35
    cy = y0 + 2 * (bh + gap) + bh + rr * 1.15
    d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=AMBER)
    if mask_ratio is None:
        return body.resize((size, size), Image.LANCZOS)
    out = Image.new("RGB", (S, S), WHITE)
    out.paste(body, (0, 0), rounded_mask(S, mask_ratio))
    return out.resize((size, size), Image.LANCZOS)


CONCEPTS = {"C": concept_c, "E": concept_e, "F": concept_f}

# Android 各密度下的启动图标边长（px）
ANDROID_DENSITIES = {
    "mdpi": 48, "hdpi": 72, "xhdpi": 96,
    "xxhdpi": 144, "xxxhdpi": 192,
}
WEB_SIZES = {"Icon-192.png": 192, "Icon-512.png": 512,
             "Icon-maskable-192.png": 192, "Icon-maskable-512.png": 512}


def write(path, img):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("  " + os.path.relpath(path))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--concept", required=True, choices=sorted(CONCEPTS))
    ap.add_argument("--out", required=True, help="项目根目录")
    args = ap.parse_args()

    fn = CONCEPTS[args.concept]
    root = os.path.abspath(args.out)
    print(f"方案 {args.concept} → {root}")

    # 源图（含圆角，用于展示）
    write(os.path.join(root, "assets/img/app_icon.png"), fn(1024))
    # Android 自适应前景：不带圆角、图形缩小留安全边距
    write(os.path.join(root, "assets/img/app_icon_foreground.png"),
          fn(1024, mask_ratio=None))

    # Android
    for name, px in ANDROID_DENSITIES.items():
        write(os.path.join(root, f"android/app/src/main/res/mipmap-{name}/ic_launcher.png"),
              fn(px))

    # iOS / macOS：直接依据各自 Contents.json 生成。
    # 不能硬编码文件名 —— Apple 的命名里带「实际像素尺寸」
    # （如 Icon-App-20x20@2x.png），与 pt 值不同；
    # 名字写错会导致图标显示为空白。
    for asset_rel in (
        "ios/Runner/Assets.xcassets/AppIcon.appiconset",
        "macos/Runner/Assets.xcassets/AppIcon.appiconset",
    ):
        asset_dir = os.path.join(root, asset_rel)
        manifest = os.path.join(asset_dir, "Contents.json")
        if not os.path.isfile(manifest):
            print(f"  ! 跳过 {asset_rel}：没有 Contents.json")
            continue
        with open(manifest, encoding="utf-8") as fh:
            spec = json.load(fh)
        for entry in spec.get("images", []):
            fname = entry.get("filename")
            if not fname:
                continue
            size = entry.get("size", "0x0")
            scale = entry.get("scale", "1x")
            try:
                w = float(size.split("x")[0])
                s = float(scale.rstrip("x"))
            except ValueError:
                continue
            px = int(round(w * s))
            if px <= 0:
                continue
            write(os.path.join(asset_dir, fname), fn(px))

    # Windows ICO
    ico = os.path.join(root, "windows/runner/resources/app_icon.ico")
    os.makedirs(os.path.dirname(ico), exist_ok=True)
    fn(256).save(ico, sizes=[(16, 16), (32, 32), (48, 48), (64, 64),
                             (128, 128), (256, 256)])
    print("  " + os.path.relpath(ico))

    # Web
    for name, px in WEB_SIZES.items():
        write(os.path.join(root, "web/icons", name), fn(px))
    write(os.path.join(root, "web/favicon.png"), fn(32))

    print("完成。记得同步更新各平台 Contents.json（如已存在则无需改动）。")


if __name__ == "__main__":
    main()
