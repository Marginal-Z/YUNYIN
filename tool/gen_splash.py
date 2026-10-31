#!/usr/bin/env python3
"""生成 Android 12 以下系统启动图中的云朵位图（drawable-*/splash_cloud.png）。

云朵与 Android 12 起的系统启动图标（drawable/splash_icon.xml）以及启动动画（lib/features/splash/splash.dart）
使用同一套几何：Logo 画布 72 × 62（x 14..86，y 18..80），云朵宽 56 个单位。
系统启动图标中云朵宽 56 × 1.6667 ≈ 93.3dp，这里按同样的尺寸输出，启动图与启动动画首帧完全重合。
三根均衡条镂空（透明），露出品牌红背景。

用法：python3 tool/gen_splash.py
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
DP_PER_UNIT = 1.6667  # 与 splash_icon.xml 的 scale 相同
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
SS = 4  # 超采样倍数，抗锯齿


def render(density):
    unit = DP_PER_UNIT * density * SS
    w, h = round(72 * unit), round(62 * unit)
    img = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(img)

    def box(x, y, bw, bh):
        return [(x - 14) * unit, (y - 18) * unit, (x - 14 + bw) * unit, (y - 18 + bh) * unit]

    d.rounded_rectangle(box(22, 50, 56, 22), radius=11 * unit, fill=255)
    d.ellipse(box(42 - 13, 48 - 13, 26, 26), fill=255)
    d.ellipse(box(60 - 16, 42 - 16, 32, 32), fill=255)
    for x, y, bh in ((38, 49, 14), (47, 44, 24), (56, 47, 18)):
        d.rounded_rectangle(box(x, y, 6, bh), radius=3 * unit, fill=0)
    alpha = img.resize((w // SS, h // SS), Image.LANCZOS)
    out = Image.new('RGBA', alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def main():
    for name, density in DENSITIES.items():
        folder = os.path.join(RES, f'drawable-{name}')
        os.makedirs(folder, exist_ok=True)
        im = render(density)
        im.save(os.path.join(folder, 'splash_cloud.png'), optimize=True)
        print(name, im.size)


if __name__ == '__main__':
    main()
