"""生成安卓启动图标（传统图标 + Android 8+ 自适应图标前景）。"""
from PIL import Image, ImageDraw

TEAL = (45, 212, 191)
AMBER = (246, 167, 35)
BG = (11, 18, 28)
ROOT = __import__("pathlib").Path(__file__).resolve().parent.parent  # android/
RES = ROOT / "res"

LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
FG = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
S = 8  # 超采样倍数


def draw_clock(size, transparent):
    s = size * S
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0) if transparent else BG + (255,))
    d = ImageDraw.Draw(img)

    if not transparent:
        # 圆角深色底
        r = int(s * 0.22)
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=r, fill=BG)

    cw = s * (0.60 if transparent else 0.84)
    ch = cw * 0.46
    cx, cy = s / 2, s / 2
    x0 = cx - cw / 2
    y0 = cy - ch / 2
    gap = cw * 0.10
    bw = (cw - gap) / 2
    rad = ch * 0.22

    d.rounded_rectangle([x0, y0, x0 + bw, y0 + ch], radius=rad, fill=TEAL)
    d.rounded_rectangle([x0 + bw + gap, y0, x0 + cw, y0 + ch], radius=rad, fill=AMBER)

    # 时间条
    bar_h = ch * 0.14
    bar_y = y0 + ch * 0.60
    bar_w = bw * 0.52
    for bx in (x0 + (bw - bar_w) / 2, x0 + bw + gap + (bw - bar_w) / 2):
        d.rounded_rectangle([bx, bar_y, bx + bar_w, bar_y + bar_h], radius=bar_h / 2, fill=BG)

    # 中间按钮
    r2 = ch * 0.62
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=(240, 246, 255))
    r3 = r2 * 0.56
    d.ellipse([cx - r3, cy - r3, cx + r3, cy + r3], fill=(10, 17, 26))

    return img.resize((size, size), Image.LANCZOS)


for dens, px in LEGACY.items():
    out = RES / f"mipmap-{dens}"
    out.mkdir(parents=True, exist_ok=True)
    draw_clock(px, transparent=False).save(out / "ic_launcher.png")

for dens, px in FG.items():
    out = RES / f"mipmap-{dens}"
    out.mkdir(parents=True, exist_ok=True)
    draw_clock(px, transparent=True).save(out / "ic_fg.png")

print("icons ok")
