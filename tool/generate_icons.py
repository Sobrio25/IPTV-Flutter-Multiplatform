"""Generates the IPTV Player launcher icons for every platform.

Usage: python tool/generate_icons.py   (requires Pillow)
The drawing mirrors _AppLogoPainter in lib/main.dart.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
MASTER = 1024
SS = 4  # supersampling factor

BG_TOP = (16, 56, 67)
BG_BOTTOM = (8, 20, 26)
BODY = (11, 38, 46)
SCREEN = (13, 139, 127)
BORDER = (235, 251, 255)
ACCENT = (255, 162, 74)
PLAY = (255, 255, 255)


def draw_master(rounded: bool) -> Image.Image:
    side = MASTER * SS
    gradient = Image.new("RGB", (1, side))
    for y in range(side):
        t = y / (side - 1)
        gradient.putpixel(
            (0, y),
            tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)),
        )
    background = gradient.resize((side, side)).convert("RGBA")

    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, side - 1, side - 1),
        radius=round(side * 0.22) if rounded else 0,
        fill=255,
    )
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    image.paste(background, (0, 0), mask)

    draw = ImageDraw.Draw(image)
    # The glyph occupies the central 72% so adaptive/round masks never clip it.
    scale = side * 0.72
    offset = side * 0.14

    def p(x: float, y: float) -> tuple[float, float]:
        return (offset + x * scale, offset + (y + 0.05) * scale)

    stroke = round(scale * 0.05)
    # Antenna
    for end_x in (0.36, 0.64):
        draw.line([p(0.50, 0.17), p(end_x, 0.04)], fill=BORDER, width=stroke)
        ex, ey = p(end_x, 0.04)
        r = stroke / 2
        draw.ellipse((ex - r, ey - r, ex + r, ey + r), fill=BORDER)
    # TV body + screen
    draw.rounded_rectangle(
        (*p(0.08, 0.17), *p(0.92, 0.74)), radius=round(scale * 0.13), fill=BODY
    )
    draw.rounded_rectangle(
        (*p(0.135, 0.225), *p(0.865, 0.685)),
        radius=round(scale * 0.08),
        fill=SCREEN,
        outline=BORDER,
        width=stroke,
    )
    # Play triangle
    draw.polygon([p(0.43, 0.34), p(0.43, 0.57), p(0.61, 0.455)], fill=PLAY)
    # Base
    draw.rounded_rectangle(
        (*p(0.38, 0.78), *p(0.62, 0.83)), radius=round(scale * 0.025), fill=ACCENT
    )
    return image.resize((MASTER, MASTER), Image.LANCZOS)


def save(image: Image.Image, path: Path, size: int, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((size, size), Image.LANCZOS)
    if opaque:
        resized = resized.convert("RGB")
    resized.save(path)


def main() -> None:
    rounded = draw_master(rounded=True)
    square = draw_master(rounded=False)

    save(rounded, ROOT / "assets" / "logo.png", 1024)

    android = ROOT / "android/app/src/main/res"
    for density, size in {
        "mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192,
    }.items():
        save(rounded, android / f"mipmap-{density}" / "ic_launcher.png", size)

    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, size in {
        "20x20@1x": 20, "20x20@2x": 40, "20x20@3x": 60,
        "29x29@1x": 29, "29x29@2x": 58, "29x29@3x": 87,
        "40x40@1x": 40, "40x40@2x": 80, "40x40@3x": 120,
        "60x60@2x": 120, "60x60@3x": 180,
        "76x76@1x": 76, "76x76@2x": 152,
        "83.5x83.5@2x": 167, "1024x1024@1x": 1024,
    }.items():
        target = ios / f"Icon-App-{name}.png"
        if target.exists() or name != "1024x1024@1x":
            save(square, target, size, opaque=True)

    macos = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save(rounded, macos / f"app_icon_{size}.png", size)

    web = ROOT / "web"
    save(rounded, web / "favicon.png", 32)
    save(rounded, web / "icons" / "Icon-192.png", 192)
    save(rounded, web / "icons" / "Icon-512.png", 512)

    ico = ROOT / "windows/runner/resources/app_icon.ico"
    ico.parent.mkdir(parents=True, exist_ok=True)
    rounded.save(
        ico, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)]
    )


if __name__ == "__main__":
    main()
