"""把 GitHub 上的 LPC 开源素材整理进 Godot 项目。
- 角色：按图层上色后输出 assets/chars/<图层名>_<动作>.png（walk 9x4 / slash 6x4 / hurt 6x1，每帧 64x64）
- 地图：复制需要的图块图集
- 字体：从系统的 Noto Sans CJK（OFL 协议）里裁出游戏用到的字
运行：python3 tools/build_assets.py
"""
import os, re, shutil, glob, colorsys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LPC = '/home/claude/assets-src/lpcgen/spritesheets'
TILES = '/home/claude/assets-src/lpctiles'
OUT_C = os.path.join(ROOT, 'assets/chars')
OUT_T = os.path.join(ROOT, 'assets/tiles')
os.makedirs(OUT_C, exist_ok=True); os.makedirs(OUT_T, exist_ok=True)
ANIMS = ['walk', 'slash', 'hurt']

def hex2rgb(h):
    h = h.lstrip('#'); return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))

def colorize(im, color, strength=1.0):
    """按亮度把灰白模板重新上色：最亮处 = 目标色略提亮，暗部压暗，保留明暗层次。"""
    tr, tg, tb = hex2rgb(color)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0: continue
            l = (r * .299 + g * .587 + b * .114) / 255
            k = 0.28 + 0.95 * l
            hi = max(0.0, l - 0.85) * 1.2
            nr, ng, nb = (min(1, c * k + hi) for c in (tr, tg, tb))
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return im

def pale(im):
    """吸血鬼的苍白皮肤：降饱和、提亮、略偏冷。"""
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0: continue
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            nr, ng, nb = colorsys.hls_to_rgb(.75, min(1, l * 1.12 + .06), s * .18)
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return im

def ghost(im):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0: continue
            l = (r + g + b) / 765
            px[x, y] = (int(120 + 80 * l), int(160 + 70 * l), int(200 + 55 * l), int(a * .78))
    return im

# 名字: (LPC 路径, 处理方式)
LAYERS = {
    'body': ('body/bodies/male', None),
    'body_pale': ('body/bodies/male', 'pale'),
    'skeleton': ('body/bodies/skeleton', None),
    'skeleton_head': ('head/heads/skeleton/adult', None),
    'ghost_body': ('body/bodies/skeleton', 'ghost'),
    'ghost_head': ('head/heads/skeleton/adult', 'ghost'),
    'head': ('head/heads/human/male', None),
    'head_old': ('head/heads/human/male_elderly', None),
    'head_vamp': ('head/heads/vampire/adult', 'pale'),
    'head_boar': ('head/heads/boarman/adult', None),
    'eyes': ('eyes/human/adult/default', None),
    'eyes_red': ('eyes/human/adult/default', 'red'),
    'pants_brown': ('legs/pants/male', '#5a4632'),
    'pants_dark': ('legs/pants/male', '#2a2630'),
    'pants_gray': ('legs/pants/male', '#5a5a64'),
    'shoes': ('feet/shoes/basic/male', '#3e2c20'),
    'boots': ('feet/boots/basic/male', '#4a3020'),
    'boots_black': ('feet/boots/basic/male', '#1e1a20'),
    'shirt_tan': ('torso/clothes/longsleeve/longsleeve/male', '#8a7a5a'),
    'shirt_green': ('torso/clothes/longsleeve/longsleeve/male', '#3e5a3a'),
    'shirt_purple': ('torso/clothes/longsleeve/longsleeve/male', '#4a3a66'),
    'shirt_red': ('torso/clothes/longsleeve/longsleeve/male', '#6a2a2a'),
    'shirt_gold': ('torso/clothes/longsleeve/longsleeve/male', '#8a6a2a'),
    'shirt_white': ('torso/clothes/longsleeve/longsleeve/male', '#cfc6dc'),
    'shirt_gray': ('torso/clothes/longsleeve/longsleeve/male', '#5a6a74'),
    'shirt_black': ('torso/clothes/longsleeve/longsleeve/male', '#24202a'),
    'shirt_cult': ('torso/clothes/longsleeve/longsleeve/male', '#3a2248'),
    'shirt_crimson': ('torso/clothes/longsleeve/longsleeve/male', '#6a1424'),
    'leather': ('torso/armour/leather/male', None),
    'plate': ('torso/armour/plate/male', None),
    'hair_brown': ('hair/messy1/adult', '#5a3a22'),
    'hair_black': ('hair/plain/adult', '#1e1a1e'),
    'hair_blond': ('hair/messy1/adult', '#c8a050'),
    'hair_red': ('hair/messy1/adult', '#a83a2a'),
    'hair_white': ('hair/balding/adult', '#d8d4cc'),
    'hair_long_white': ('hair/long/adult', '#d8d4cc'),
    'hair_long_silver': ('hair/long/adult', '#cfc6dc'),
    'hair_dark': ('hair/bangsshort/adult', '#2a2020'),
    'hood_cult': ('hat/cloth/hood/adult', '#3a2248'),
    'hood_lead': ('hat/cloth/hood/adult', '#7a1c2a'),
    'hood_gray': ('hat/cloth/hood/adult', '#5a5662'),
    'cap': ('hat/cloth/leather_cap/adult', '#6b4a2e'),
    'bandana': ('hat/cloth/leather_cap/adult', '#7a2020'),
    'helm': ('hat/helmet/kettle/adult', None),
    'cape_bg_black': ('cape/solid/bg', '#1e1a24'),
    'cape_fg_black': ('cape/solid/fg', '#1e1a24'),
    'cape_bg_red': ('cape/solid/bg', '#6a1224'),
    'cape_fg_red': ('cape/solid/fg', '#6a1224'),
}

def load(path, anim, mode):
    p = os.path.join(LPC, path, anim + '.png')
    if mode == 'red':
        p = os.path.join(LPC, path, anim, 'red.png')
    if not os.path.exists(p):
        return None
    im = Image.open(p).convert('RGBA')
    if mode == 'pale': im = pale(im)
    elif mode == 'ghost': im = ghost(im)
    elif mode and mode.startswith('#'): im = colorize(im, mode)
    return im

for name, (path, mode) in LAYERS.items():
    for a in ANIMS:
        im = load(path, a, mode)
        if im is None:
            print('缺少', name, a); continue
        # 统一尺寸：walk 576x256, slash 384x256, hurt 384x64
        want = {'walk': (576, 256), 'slash': (384, 256), 'hurt': (384, 64)}[a]
        if im.size != want:
            c = Image.new('RGBA', want, (0, 0, 0, 0)); c.alpha_composite(im.crop((0, 0, min(im.width, want[0]), min(im.height, want[1])))); im = c
        im.save(os.path.join(OUT_C, f'{name}_{a}.png'))

# 地图图集
for src, dst in [('terrain-v7.png', 'terrain.png'), ('Outside Objects.png', 'objects.png'), ('conifers.png', 'conifers.png'),
                 ('Exterior Tiles.png', 'exterior.png'), ('stone-bridge.png', 'bridge.png'), ('decorations-medieval.png', 'deco.png'), ('Interior.png', 'interior.png')]:
    shutil.copy(os.path.join(TILES, src), os.path.join(OUT_T, dst))

# 署名文件
os.makedirs(os.path.join(ROOT, 'assets/credits'), exist_ok=True)
for f in glob.glob(os.path.join(TILES, 'CREDITS-*.txt')) + glob.glob(os.path.join(TILES, 'Attributions/*.txt')):
    shutil.copy(f, os.path.join(ROOT, 'assets/credits', 'tiles_' + os.path.basename(f).replace(' ', '_')))
shutil.copy('/home/claude/assets-src/lpcgen/CREDITS.csv', os.path.join(ROOT, 'assets/credits/characters_CREDITS.csv'))
print('done')

# 预制房屋：3 格宽 x 5 格高（屋顶 3 行 + 墙 2 行，中间是门）
E = Image.open(os.path.join(TILES, 'Exterior Tiles.png')).convert('RGBA')
def tile(c, r, w=1, h=1): return E.crop((c * 32, r * 32, (c + w) * 32, (r + h) * 32))
for name, roof in [('house', (0, 12)), ('hall', (0, 12))]:
    im = Image.new('RGBA', (96, 160), (0, 0, 0, 0))
    im.alpha_composite(tile(roof[0], roof[1], 3, 3), (0, 0))
    im.alpha_composite(tile(0, 9, 3, 2), (0, 96))
    im.alpha_composite(tile(4, 9, 1, 2), (32, 96))
    if name == 'hall':
        im.alpha_composite(tile(17, 1, 1, 1), (64, 100))  # 门边挂牌
    im.save(os.path.join(OUT_T, name + '.png'))
print('houses done')
