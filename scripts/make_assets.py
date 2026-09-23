"""Builds the app icon and header art from Resources/mascot-source.png,
and the menu bar icon from Resources/menubar-source.png."""
import os, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "Resources")
src = Image.open(os.path.join(ROOT, "mascot-source.png")).convert("RGBA")
mascot = src.crop(src.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())


def squircle(size, inset):
    """macOS app icon shape: rounded square, corner radius ~22.5% of the body."""
    s, i = size * 4, inset * 4
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((i, i, s - i, s - i), radius=(s - 2 * i) * .225, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def icon(size=1024):
    inset = 100 * size // 1024
    body = size - 2 * inset
    canvas = Image.new("RGBA", (size, size))

    # deep indigo gradient with a cool glow behind the ghost, echoing its eyes
    grad = Image.new("RGBA", (size, size))
    top, bottom = (40, 46, 92), (10, 12, 26)
    for y in range(size):
        t = y / size
        grad.paste(tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,), (0, y, size, y + 1))
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((size * .22, size * .18, size * .78, size * .74), fill=(92, 128, 255, 150))
    grad = Image.alpha_composite(grad, glow.filter(ImageFilter.GaussianBlur(size * .11)))

    # faint top rim highlight
    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(rim).ellipse((inset, inset - body * .55, size - inset, inset + body * .45), fill=(255, 255, 255, 18))
    grad = Image.alpha_composite(grad, rim.filter(ImageFilter.GaussianBlur(size * .02)))
    canvas.paste(grad, (0, 0), squircle(size, inset))

    # ghost, with a soft light halo so the dark body separates from the background
    h = int(body * .80)
    w = int(mascot.width * h / mascot.height)
    m = mascot.resize((w, h), Image.LANCZOS)
    x, y = (size - w) // 2 + int(body * .02), inset + (body - h) // 2 + int(body * .01)
    halo = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    halo.paste((150, 175, 255, 110), (x, y), m.getchannel("A"))
    canvas = Image.alpha_composite(canvas, halo.filter(ImageFilter.GaussianBlur(size * .025)))
    canvas.alpha_composite(m, (x, y))
    return canvas


def menu_icon(height):
    """Template icon from the line-art mascot. macOS tints it to match the menu bar.
    The lines are thickened first: shrunk as-is they drop under a pixel and go grey."""
    a = Image.open(os.path.join(ROOT, "menubar-source.png")).convert("RGBA").getchannel("A")
    a = a.crop(a.point(lambda v: 255 if v > 40 else 0).getbbox()).filter(ImageFilter.MaxFilter(13))
    out = Image.new("RGBA", a.size, (0, 0, 0, 0))
    out.putalpha(a)
    return out.resize((round(a.width * height / a.height), height), Image.LANCZOS)


if __name__ == "__main__":

    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.makedirs(iconset)
        for pt in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px = pt * scale
                icon(px).save(os.path.join(iconset, f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(ROOT, "AppIcon.icns")], check=True)

    menu_icon(18).save(os.path.join(ROOT, "MenuIcon.png"))
    menu_icon(36).save(os.path.join(ROOT, "MenuIcon@2x.png"))

    header = mascot.copy()
    header.thumbnail((400, 400), Image.LANCZOS)
    header.save(os.path.join(ROOT, "Mascot.png"))
    print("assets written")
