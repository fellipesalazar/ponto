"""Desenha o ícone do Ponto e salva como .icns.

Uso: python make_icon.py caminho/AppIcon.icns
"""
import math
import sys

from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.icns"

S = 1024
SS = 4  # desenha 4x maior e reduz, pra borda ficar lisa
N = S * SS
img = Image.new("RGBA", (N, N), (0, 0, 0, 0))

# Base no formato dos ícones do macOS: quadrado arredondado com margem.
m = 100 * SS
r = 185 * SS
box = (m, m, N - m, N - m)

# Degradê azul de cima pra baixo.
grad = Image.new("RGBA", (N, N))
gd = ImageDraw.Draw(grad)
top, bottom = (64, 156, 255), (10, 92, 224)
for y in range(N):
    t = min(1, max(0, (y - m) / (N - 2 * m)))
    c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    gd.line([(0, y), (N, y)], fill=c + (255,))
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle(box, radius=r, fill=255)

# Sombra suave embaixo.
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle((m, m + 14 * SS, N - m, N - m + 14 * SS), radius=r, fill=(0, 0, 0, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(18 * SS))
img = Image.alpha_composite(img, shadow)
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)
cx = cy = N // 2
R = 270 * SS

# Mostrador branco.
d.ellipse((cx - R, cy - R, cx + R, cy + R), fill=(255, 255, 255, 255))

# Marcas das horas.
ink = (16, 60, 140, 255)
for h in range(12):
    a = math.radians(h * 30)
    big = h % 3 == 0
    r1 = R - (58 if big else 44) * SS
    r2 = R - 26 * SS
    w = (16 if big else 9) * SS
    d.line(
        [(cx + r1 * math.sin(a), cy - r1 * math.cos(a)), (cx + r2 * math.sin(a), cy - r2 * math.cos(a))],
        fill=ink,
        width=w,
    )


def hand(angle_deg, length, width, color):
    a = math.radians(angle_deg)
    x, y = cx + length * math.sin(a), cy - length * math.cos(a)
    d.line([(cx, cy), (x, y)], fill=color, width=width)
    rr = width // 2
    d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=color)


# Ponteiros em 9:00.
hand(270, 120 * SS, 30 * SS, ink)
hand(0, 185 * SS, 22 * SS, ink)
d.ellipse((cx - 26 * SS, cy - 26 * SS, cx + 26 * SS, cy + 26 * SS), fill=ink)
d.ellipse((cx - 10 * SS, cy - 10 * SS, cx + 10 * SS, cy + 10 * SS), fill=(255, 149, 0, 255))

icon = img.resize((S, S), Image.LANCZOS)
icon.save(out, format="ICNS", sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
print("ícone salvo em", out)
