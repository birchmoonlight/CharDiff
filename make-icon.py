#!/usr/bin/env python3
"""生成 CharDiff 的应用图标（鳄梨）。

原图是 Inkscape 手搓的 avocado.svg（210×210）。本脚本按同一组几何重画成各档尺寸，
不缩放——PIL 缩小会糊，每档按真实尺寸画一遍边最锐。

构图：
  果肉：  铺满整张画布的超椭圆（角半径 46.9），绿 #74A641
  下行：  两个大圆 r=46.667，cx=58.333 / 151.667，cy=142.333，浅绿 #D0D754，
         两个在中线 105.0 精确相切
  上行：  两个小圆 r=37.333，cx=49 / 142.333，cy=49，果核棕 #584422，
         左缘与下行大圆对齐（11.667），两个之间留 18.667 的缝
"""
import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

# avocado.svg 里的坐标（画布 210×210）。
BOX = 210.0
FLESH = "#74A641"
BIG = "#D0D754"  # 下行大圆
PIT = "#584422"  # 上行小圆，果核色

RADIUS = 46.9

BIG_CX = (58.333328, 151.66667)
BIG_CY = 142.33318
BIG_R = 46.666656

SMALL_CX = (48.999996, 142.33333)
SMALL_CY = 48.999992
SMALL_R = 37.333332


def _rgb(color: str) -> tuple[int, int, int, int]:
    return tuple(int(color[i : i + 2], 16) for i in (1, 3, 5)) + (255,)


def make_icon(size: int) -> Image.Image:
    k = size / BOX
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 果肉铺满整张画布；没有它，四个圆浮在透明背景上不成鳄梨。
    draw.rounded_rectangle([0, 0, size, size], radius=RADIUS * k, fill=_rgb(FLESH))

    for cx in BIG_CX:
        draw.ellipse(
            [(cx - BIG_R) * k, (BIG_CY - BIG_R) * k, (cx + BIG_R) * k, (BIG_CY + BIG_R) * k],
            fill=_rgb(BIG),
        )

    for cx in SMALL_CX:
        draw.ellipse(
            [(cx - SMALL_R) * k, (SMALL_CY - SMALL_R) * k,
             (cx + SMALL_R) * k, (SMALL_CY + SMALL_R) * k],
            fill=_rgb(PIT),
        )

    return img


ICONS = [16, 32, 64, 128, 256, 512, 1024]


def write_iconset(dest: Path) -> None:
    """iconutil 要一个 .iconset 目录：每个尺寸一张 png，2 倍图带 @2x。"""
    dest.mkdir(parents=True, exist_ok=True)
    for size in ICONS:
        for scale, suffix in [(1, ""), (2, "@2x")]:
            make_icon(size * scale).save(dest / f"icon_{size}x{size}{suffix}.png")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    out = Path(args.out)
    if out.suffix == ".icns":
        # 1024 的 png 顺手也留一份，软件里预览用。
        make_icon(args.size).save(out.with_suffix(".png"))
        tmp = Path(tempfile.mkdtemp())
        try:
            iconset = tmp / "AppIcon.iconset"
            write_iconset(iconset)
            subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out)], check=True)
        finally:
            shutil.rmtree(tmp)
        print(f"已生成 {out}（鳄梨，{len(ICONS)} 档尺寸）")
    else:
        make_icon(args.size).save(out)
        print(f"已生成 {out}（鳄梨，{args.size}×{args.size}）")


if __name__ == "__main__":
    main()
