# /// script
# dependencies = ["Pillow"]
# ///
"""Generate tray icons for TrayForge Flutter from Python icon.py logic."""

from PIL import Image, ImageDraw

ICON_SIZE = 64
_STROKE = 6
_GLOW = 2
OUTPUT_DIR = "assets/icons"


def make_icon(color: tuple[int, int, int]) -> Image.Image:
    """Generate a modern hollow ring icon with subtle glow."""
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    margin = 6
    x1, y1 = margin, margin
    x2, y2 = ICON_SIZE - margin, ICON_SIZE - margin

    # Outer glow ring (larger, semi-transparent)
    glow_color = (*color, 60)
    draw.ellipse(
        [x1, y1, x2, y2],
        outline=glow_color,
        width=_STROKE + _GLOW,
    )

    # Main ring
    draw.ellipse(
        [x1, y1, x2, y2],
        outline=color,
        width=_STROKE,
    )

    # Inner highlight (top-left arc, lighter)
    r, g, b = color
    highlight = (min(r + 60, 255), min(g + 60, 255), min(b + 60, 255), 100)
    draw.arc(
        [x1 + 2, y1 + 2, x2 - 2, y2 - 2],
        start=200,
        end=340,
        fill=highlight,
        width=_STROKE,
    )

    return img


GREEN = (76, 175, 80)
YELLOW = (255, 193, 7)
RED = (244, 67, 54)


def main():
    import os

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    make_icon(GREEN).save(f"{OUTPUT_DIR}/icon-green.png", format="PNG")
    print("Saved icon-green.png")

    make_icon(YELLOW).save(f"{OUTPUT_DIR}/icon-yellow.png", format="PNG")
    print("Saved icon-yellow.png")

    make_icon(RED).save(f"{OUTPUT_DIR}/icon-red.png", format="PNG")
    print("Saved icon-red.png")


if __name__ == "__main__":
    main()
