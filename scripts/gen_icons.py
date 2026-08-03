# /// script
# dependencies = ["Pillow"]
# ///
"""Generate tray and app icons for trayforge Flutter."""

from pathlib import Path

from PIL import Image, ImageDraw

ICON_SIZE = 64
_STROKE = 6
_GLOW = 2
REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = REPO_ROOT / "assets/icons"
APP_ICON_PATH = REPO_ROOT / "windows/runner/resources/app_icon.ico"
# Windows tray icons need .ico format; include common system sizes.
ICO_SIZES = [(16, 16), (32, 32), (48, 48), (64, 64)]
# App icon embedded in the Windows exe; 256px needed for Explorer/taskbar.
APP_ICON_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def make_icon(color: tuple[int, int, int], size: int = ICON_SIZE) -> Image.Image:
    """Generate a modern hollow ring icon with subtle glow."""
    scale = size / ICON_SIZE
    stroke = round(_STROKE * scale)
    glow = round(_GLOW * scale)
    inset = round(2 * scale)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = round(6 * scale)
    x1, y1 = margin, margin
    x2, y2 = size - margin, size - margin

    # Outer glow ring (larger, semi-transparent)
    glow_color = (*color, 60)
    draw.ellipse(
        [x1, y1, x2, y2],
        outline=glow_color,
        width=stroke + glow,
    )

    # Main ring
    draw.ellipse(
        [x1, y1, x2, y2],
        outline=color,
        width=stroke,
    )

    # Inner highlight (top-left arc, lighter)
    r, g, b = color
    highlight = (min(r + 60, 255), min(g + 60, 255), min(b + 60, 255), 100)
    draw.arc(
        [x1 + inset, y1 + inset, x2 - inset, y2 - inset],
        start=200,
        end=340,
        fill=highlight,
        width=stroke,
    )

    return img


GREEN = (76, 175, 80)
YELLOW = (255, 193, 7)
RED = (244, 67, 54)
# App/window icon colour (matches assets/icon.ico, reused from Python trayforge).
BLUE = (33, 150, 243)


def save_icon(img: Image.Image, name: str) -> None:
    """Save icon as both PNG (for preview) and ICO (for Windows tray)."""
    img.save(OUTPUT_DIR / f"{name}.png", format="PNG")
    img.save(OUTPUT_DIR / f"{name}.ico", format="ICO", sizes=ICO_SIZES)
    print(f"Saved {name}.png + {name}.ico")


def main():
    import os

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    save_icon(make_icon(GREEN), "icon-green")
    save_icon(make_icon(YELLOW), "icon-yellow")
    save_icon(make_icon(RED), "icon-red")

    # App icon for the Windows exe (same blue design as assets/icon.ico).
    app_icon = make_icon(BLUE, 256)
    app_icon.save(APP_ICON_PATH, format="ICO", sizes=APP_ICON_SIZES)
    print(f"Saved {APP_ICON_PATH}")


if __name__ == "__main__":
    main()
