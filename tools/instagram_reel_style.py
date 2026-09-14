"""User-approved defaults for every newly produced Instagram Reel."""
from pathlib import Path
from functools import lru_cache
import json
from PIL import ImageFont, Image, ImageChops
ROOT=Path(__file__).resolve().parents[1]
STYLE=json.loads((ROOT/'functions/instagram_reel_style.json').read_text())
W,H=STYLE['width'],STYLE['height']
PAPER,INK,LIME,GREY=[STYLE['colors'][k] for k in ('paper','ink','lime','muted')]
@lru_cache(maxsize=128)
def font(size,weight='medium'):
    name={'regular':'Regular','medium':'Medium','semi':'SemiBold','bold':'ExtraBold','black':'Black'}[weight]
    return ImageFont.truetype(str(ROOT/'functions/instagram_assets'/f'WantedSans-{name}.ttf'),size)
def assert_safe_bottom(frame):
    assert frame.size==(W,H), 'Render natively at 1080 x 1920'
    zone=frame.convert('RGB').crop((0,STYLE['contentBottomExclusive'],W,H))
    assert ImageChops.difference(zone,Image.new('RGB',zone.size,zone.getpixel((0,0)))).getbbox() is None, 'Keep the bottom 370px clear'
