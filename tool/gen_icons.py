"""根据设计稿“应用图标”生成各平台图标。用法：python3 tool/gen_icons.py"""
import json
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RED = (0xDC, 0x10, 0x31, 255)
# 主题色（与应用内“主题色”一致）：名称 → RGBA
THEMES = {
    'red': (0xDC, 0x10, 0x31, 255),
    'blue': (0x2F, 0x7D, 0xE1, 255),
    'teal': (0x14, 0x91, 0x7F, 255),
    'orange': (0xD9, 0x68, 0x0A, 255),
    'graphite': (0x63, 0x63, 0x66, 255),
}
WHITE = (255, 255, 255, 255)
SS = 4  # 超采样倍数


def _mark(draw, s, ox, oy, scale, fg, cut):
    """绘制云朵与声波。坐标为设计稿 100×100 视图下的值。"""
    def tx(x, y):
        # translate(50 50) scale(1.12) translate(-50 -49)
        return (ox + (50 + (x - 50) * 1.12) * scale * s, oy + (50 + (y - 49) * 1.12) * scale * s)

    def rrect(x, y, w, h, r, color):
        x0, y0 = tx(x, y)
        x1, y1 = tx(x + w, y + h)
        draw.rounded_rectangle([x0, y0, x1, y1], radius=r * 1.12 * scale * s, fill=color)

    def circle(cx, cy, r, color):
        x, y = tx(cx, cy)
        rr = r * 1.12 * scale * s
        draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=color)

    rrect(22, 50, 56, 22, 11, fg)
    circle(42, 48, 13, fg)
    circle(60, 42, 16, fg)
    rrect(38, 49, 6, 14, 3, cut)
    rrect(47, 44, 6, 24, 3, cut)
    rrect(56, 47, 6, 18, 3, cut)


def icon(size, rounded=True, bg=RED, fg=WHITE, padding=0.0):
    """完整图标：圆角方块 + 图形。padding 为四周留白比例（用于 macOS / 可遮罩图标）。"""
    s = size * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    inner = s * (1 - 2 * padding)
    off = s * padding
    if rounded:
        d.rounded_rectangle([off, off, off + inner, off + inner], radius=inner * 0.225, fill=bg)
    else:
        d.rectangle([0, 0, s, s], fill=bg)
    unit = inner / 100 / SS
    _mark(d, SS, off, off, unit * 1, fg, bg)
    return img.resize((size, size), Image.LANCZOS)


def foreground(size, cut=RED):
    """Android 自适应图标前景：108dp 画布，图形占中间 ~62%。"""
    s = size * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    inner = s * 0.62
    off = (s - inner) / 2
    _mark(d, SS, off, off, inner / 100 / SS, WHITE, cut)
    return img.resize((size, size), Image.LANCZOS)


def themed_variants():
    """每种主题色一套图标：桌面端运行时切换窗口图标，Android 通过 activity-alias 切换桌面图标。"""
    res = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
    colors = ['<?xml version="1.0" encoding="utf-8"?>', '<resources>',
              '    <color name="ic_launcher_background">#DC1031</color>']
    for name, rgba in THEMES.items():
        img = icon(512, bg=rgba)
        save(img, 'assets', 'icon', 'themes', f'{name}.png')
        img.save(os.path.join(ROOT, 'assets', 'icon', 'themes', f'{name}.ico'),
                 sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
        for density, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
            save(icon(px, bg=rgba), 'android', 'app', 'src', 'main', 'res', f'mipmap-{density}', f'ic_launcher_{name}.png')
        for density, px in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}.items():
            save(foreground(px, cut=rgba), 'android', 'app', 'src', 'main', 'res', f'mipmap-{density}', f'ic_launcher_foreground_{name}.png')
        with open(os.path.join(res, 'mipmap-anydpi-v26', f'ic_launcher_{name}.xml'), 'w') as f:
            f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                    f'    <background android:drawable="@color/ic_launcher_bg_{name}"/>\n'
                    f'    <foreground android:drawable="@mipmap/ic_launcher_foreground_{name}"/>\n'
                    f'    <monochrome android:drawable="@mipmap/ic_launcher_foreground_{name}"/>\n'
                    '</adaptive-icon>\n')
        colors.append(f'    <color name="ic_launcher_bg_{name}">#{rgba[0]:02X}{rgba[1]:02X}{rgba[2]:02X}</color>')
    colors.append('</resources>')
    with open(os.path.join(res, 'values', 'ic_launcher_background.xml'), 'w') as f:
        f.write('\n'.join(colors) + '\n')


def save(img, *parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def main():
    save(icon(1024), 'assets', 'icon', 'app_icon.png')
    save(icon(1024, rounded=False), 'assets', 'icon', 'app_icon_square.png')

    # Android
    for name, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        save(icon(px), 'android', 'app', 'src', 'main', 'res', f'mipmap-{name}', 'ic_launcher.png')
    for name, px in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}.items():
        save(foreground(px), 'android', 'app', 'src', 'main', 'res', f'mipmap-{name}', 'ic_launcher_foreground.png')
    anydpi = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res', 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    values = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res', 'values')
    os.makedirs(values, exist_ok=True)
    themed_variants()

    # Windows
    ico = icon(256)
    ico.save(os.path.join(ROOT, 'windows', 'runner', 'resources', 'app_icon.ico'),
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    # Linux（运行时加载）
    save(icon(256), 'linux', 'runner', 'resources', 'app_icon.png')

    # Web
    save(icon(32), 'web', 'favicon.png')
    save(icon(192), 'web', 'icons', 'Icon-192.png')
    save(icon(512), 'web', 'icons', 'Icon-512.png')
    save(icon(192, rounded=False), 'web', 'icons', 'Icon-maskable-192.png')
    save(icon(512, rounded=False), 'web', 'icons', 'Icon-maskable-512.png')

    # macOS / iOS：按 Contents.json 生成
    for base, rounded, pad in [
        (os.path.join(ROOT, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'), True, 0.1),
        (os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'), False, 0.0),
    ]:
        cj = os.path.join(base, 'Contents.json')
        if not os.path.exists(cj):
            continue
        for img in json.load(open(cj))['images']:
            fn = img.get('filename')
            if not fn:
                continue
            pt = float(img['size'].split('x')[0])
            scale = int(img.get('scale', '1x').replace('x', ''))
            px = int(round(pt * scale))
            im = icon(px, rounded=rounded, padding=pad)
            if not rounded:
                im = im.convert('RGB')
            im.save(os.path.join(base, fn))


if __name__ == '__main__':
    main()
