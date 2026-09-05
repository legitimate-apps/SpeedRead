#!/usr/bin/env python3
"""Render SpeedRead's gallery at native output resolution using headless Chrome."""
from __future__ import annotations

import argparse
import base64
import hashlib
import html
import json
import os
from pathlib import Path
import select
import time
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parent
DEVICES = {
    'iphone': {'output': (1290, 2796), 'raw': (1320, 2868)},
    'ipad': {'output': (2048, 2732), 'raw': (2048, 2732)},
}
# Explicit line breaks preserve the approved wording and editorial rhythm.
FRAMES = [
    ('01', '01-library.png', ('Your shelf,', 'always cozy'), 'cozy',
     'Classics already loaded — tap any spine to begin'),
    ('02', '04-rsvp-paused.png', ('One word', 'at a time'), 'One',
     'The red letter sits where your eye already lands'),
    ('03', '05-rsvp-playing.png', ('500 words', 'a minute'), '500',
     'Books in a day, at a pace you set'),
    ('04', '02-reader-parchment.png', ('Read it', 'like a book'), 'book',
     'Tap any word to launch into it at speed'),
    ('05', '03-reader-night.png', ('Night reading,', 'done right'), 'Night',
     'Parchment, sepia or true night — your type, your size'),
    ('06', '06-browse.png', ('Bring your', 'own library'), 'own',
     'Connect Calibre, Project Gutenberg, or any OPDS catalogue'),
]


def source_for(device, frame):
    path = ROOT / 'raw' / device / frame[1]
    with Image.open(path) as image:
        image.load()
        if image.format != 'PNG' or image.size != DEVICES[device]['raw']:
            raise ValueError(f'{device}/{path.name}: expected PNG {DEVICES[device]["raw"]}, '
                             f'got {image.format} {image.size}; wrong device or capture')
    return path


def build_html(device, frame):
    w, h = DEVICES[device]['output']
    ipad = device == 'ipad'
    unit = w / 1290
    # The iPad uses more of the width to retain legible native tablet UI.
    device_w = w * (0.85 if ipad else 0.84)
    bezel = device_w * (0.022 if ipad else 0.025)
    radius = device_w * (0.052 if ipad else 0.115)
    device_top = h * (0.238 if ipad else 0.245)
    head_size = (108 if ipad else 112) * unit
    band_h = h * (0.137 if ipad else 0.128)
    raw = source_for(device, frame)
    uri = 'data:image/png;base64,' + base64.b64encode(raw.read_bytes()).decode()
    accent = frame[3]
    if ' '.join(frame[2]).split().count(accent) != 1:
        raise ValueError('Accent must appear verbatim exactly once in headline')
    mark = ('<svg class="mark" viewBox="0 0 200 24" preserveAspectRatio="none">'
            '<path d="M4 13 C48 5 107 7 195 10"/>'
            '<path class="echo" d="M12 20 C69 13 133 15 186 17"/></svg>')
    headline = ''.join('<span class="line">' + html.escape(line).replace(
        accent, '<span class="accent">' + accent + mark + '</span>') + '</span>'
        for line in frame[2])
    buttons = '' if ipad else '<i class="button power"></i><i class="button volume"></i><i class="button action"></i>'
    font_root = Path('/') / 'System' / 'Library' / 'Fonts'
    fonts = []
    for filename, style in [('NewYork.ttf', 'normal'), ('NewYorkItalic.ttf', 'italic')]:
        font_path = font_root / filename
        if not font_path.is_file():
            raise RuntimeError(f'Missing macOS system font {filename}; render on a Mac with New York installed')
        data = base64.b64encode(font_path.read_bytes()).decode()
        fonts.append('@font-face{font-family:"SpeedRead Serif";font-style:' + style +
                     ';font-weight:100 900;src:url(data:font/ttf;base64,' + data + ') format("truetype")}')
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>
{''.join(fonts)}
* {{box-sizing:border-box;margin:0;padding:0}}
html,body {{width:{w}px;height:{h}px;overflow:hidden}}
body {{position:relative;background:#FFF8E7;color:#C62828;font-synthesis:none;
 font-family:"SpeedRead Serif",serif;-webkit-font-smoothing:antialiased}}
.paper {{position:absolute;inset:0;background:
 radial-gradient(ellipse at 50% 0%,#fffdf5 0%,transparent 62%),
 radial-gradient(ellipse at 50% 100%,#F0E6D0 0%,transparent 65%)}}
.rule {{position:absolute;top:{h*.038}px;left:46%;width:8%;height:{2*unit}px;background:#C8A951}}
h1 {{position:absolute;top:{h*.068}px;left:5%;width:90%;text-align:center;
 font-size:{head_size}px;font-weight:600;line-height:1.14;letter-spacing:{-1.8*unit}px}}
.line {{display:block;white-space:nowrap}}
.accent {{display:inline-block;position:relative}}
.mark {{position:absolute;bottom:-0.16em;left:-4%;width:108%;height:.18em;overflow:visible}}
.mark path {{fill:none;stroke:#C62828;stroke-width:3;stroke-linecap:round;opacity:.8}}
.mark .echo {{stroke-width:1.5;opacity:.38}}
.device {{position:absolute;top:{device_top}px;left:50%;transform:translateX(-50%);
 width:{device_w}px;padding:{bezel}px;border-radius:{radius}px;
 background:linear-gradient(135deg,#76706a 0%,#292624 17%,#1C1410 51%,#625b53 85%,#272422 100%);
 box-shadow:inset 0 0 0 {2*unit}px #93887a,inset 0 0 0 {5*unit}px #292623,
 0 {12*unit}px {26*unit}px #3e272322,0 {40*unit}px {70*unit}px #3e272334}}
.screen {{overflow:hidden;border-radius:{radius-bezel}px;background:#1C1410}}
.screen img {{display:block;width:100%;height:auto}}
.button {{position:absolute;width:{bezel*.35}px;border-radius:{2*unit}px;background:#514942}}
.power {{right:{-bezel*.28}px;top:27%;height:{device_w*.105}px}}
.volume {{left:{-bezel*.28}px;top:26%;height:{device_w*.15}px}}
.action {{left:{-bezel*.28}px;top:19%;height:{device_w*.032}px}}
.band {{position:absolute;bottom:0;left:0;width:100%;height:{band_h}px;
 display:flex;align-items:center;justify-content:center;gap:{24*unit}px;
 padding:{30*unit}px {w*.075}px {14*unit}px;
 background:linear-gradient(180deg,#F0E6D000,#F0E6D0 18%,#F0E6D0);
 color:#5D4037}}
.band svg {{width:{49*unit}px;height:{49*unit}px;flex:none;fill:none;stroke:#C62828;
 stroke-width:2.5;stroke-linecap:round;stroke-linejoin:round}}
.benefit {{font-size:{(32 if ipad else 39)*unit}px;line-height:1.27;font-style:italic;
 text-wrap:balance;max-width:{w*.76}px}}
</style></head><body>
<div class="paper"></div><div class="rule"></div>
<h1>{headline}</h1>
<div class="device">{buttons}<div class="screen"><img src="{uri}" alt="SpeedRead capture"></div></div>
<div class="band"><svg viewBox="0 0 48 48"><path d="M24 12 C17 7 8 8 4 10 V37 C11 34 18 35 24 39 C30 35 37 34 44 37 V10 C36 8 30 7 24 12 V39"/></svg><p class="benefit">{html.escape(frame[4])}</p></div>
<script>
(async()=>{{
const report={{errors:[]}};
try {{
 await document.fonts.ready;
 const img=document.querySelector('img'); await img.decode();
 await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
 const rect=s=>document.querySelector(s).getBoundingClientRect();
 const inside=(r,b)=>r.left>=b.left&&r.right<=b.right&&r.top>=b.top&&r.bottom<=b.bottom;
 const page={{left:0,top:0,right:{w},bottom:{h}}};
 const canvas=document.createElement('canvas'),ctx=canvas.getContext('2d');
 const widths=[];
 for(const f of ['monospace','"SpeedRead Serif",monospace']){{ctx.font='600 100px '+f;widths.push(ctx.measureText('SpeedRead cozy 500').width)}}
 if(widths[0]===widths[1]) report.errors.push('New York unavailable: Chrome would fall back');
 report.fontWidths=widths;
 for(const el of document.querySelectorAll('.line,.benefit')){{
 const range=document.createRange();range.selectNodeContents(el);
 for(const r of range.getClientRects()){{
 if(!inside(r,page)) report.errors.push('Text outside output');
 if(el.className==='benefit'&&!inside(r,rect('.band'))) report.errors.push('Band text clipped');
 if(el.className==='line'&&r.bottom+{24*unit}>rect('.device').top) report.errors.push('Headline collides with device');
 }} }}
 const screen=rect('img'),dev=rect('.device'),band=rect('.band');
 if(screen.width>=img.naturalWidth||screen.height>=img.naturalHeight)report.errors.push('Capture is not downscaled');
 if(Math.abs(screen.width/screen.height-img.naturalWidth/img.naturalHeight)>.00001) report.errors.push('Capture distorted');
 if(dev.bottom<=band.top)report.errors.push('Device does not bleed behind band');
 if(!inside(rect('h1'),page))report.errors.push('Headline box outside output');
 report.screen={{width:screen.width,height:screen.height,naturalWidth:img.naturalWidth,naturalHeight:img.naturalHeight}};
 report.headlineBottom=rect('h1').bottom;report.deviceTop=dev.top;report.bandTop=band.top;
}}catch(e){{report.errors.push(String(e))}}
const result=document.createElement('pre');result.id='validation';result.hidden=true;
result.textContent=JSON.stringify(report);document.body.append(result);
}})();
</script></body></html>'''


def chrome_path():
    override = os.environ.get('CHROME_BIN')
    candidates = [override] if override else [shutil.which(n) for n in ('google-chrome', 'chromium', 'chrome')]
    if sys.platform == 'darwin' and not override:
        candidates.append(str(Path('/') / 'Applications' / 'Google Chrome.app' / 'Contents' / 'MacOS' / 'Google Chrome'))
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise RuntimeError('Headless Chrome missing. Set CHROME_BIN to its executable.')


class Chrome:
    """Minimal standard-library CDP pipe client; no browser-driver dependency."""
    def __init__(self, executable, profile):
        self.sequence = 0
        self.buffer = b''
        read_in, self.write_in = os.pipe()
        self.read_out, write_out = os.pipe()

        def child_pipes():
            os.dup2(read_in, 3)
            os.dup2(write_out, 4)
            os.set_inheritable(3, True)
            os.set_inheritable(4, True)

        self.process = subprocess.Popen([
            executable, '--headless', '--disable-gpu', '--hide-scrollbars',
            '--no-first-run', '--no-default-browser-check', '--disable-background-networking',
            '--remote-debugging-pipe', f'--user-data-dir={profile}',
        ], preexec_fn=child_pipes, close_fds=False,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.close(read_in)
        os.close(write_out)

    def call(self, method, params=None, session=None):
        self.sequence += 1
        message = dict(id=self.sequence, method=method, params=params or {})
        if session:
            message['sessionId'] = session
        payload = json.dumps(message).encode() + b'\0'
        while payload:
            payload = payload[os.write(self.write_in, payload):]
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            while b'\0' in self.buffer:
                line, self.buffer = self.buffer.split(b'\0', 1)
                response = json.loads(line)
                if response.get('id') == self.sequence:
                    if 'error' in response:
                        raise RuntimeError(f'Chrome {method}: {response["error"]}')
                    return response.get('result', {})
            if select.select([self.read_out], [], [], max(0, deadline-time.monotonic()))[0]:
                chunk = os.read(self.read_out, 1024*1024)
                if not chunk:
                    raise RuntimeError('Chrome closed its protocol pipe')
                self.buffer += chunk
        raise RuntimeError(f'Chrome {method} timed out')

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        os.close(self.write_in)
        os.close(self.read_out)


def render(chrome, device, frame, staging):
    w, h = DEVICES[device]['output']
    name = device + '-' + frame[0]
    page = staging / (name + '.html')
    output = staging / (name + '.png')
    page.write_text(build_html(device, frame))
    target = chrome.call('Target.createTarget', {'url': 'about:blank'})['targetId']
    session = chrome.call('Target.attachToTarget', {'targetId': target, 'flatten': True})['sessionId']
    def call(method, params=None):
        return chrome.call(method, params, session)
    try:
        call('Emulation.setDeviceMetricsOverride', dict(width=w, height=h, deviceScaleFactor=1, mobile=False))
        call('Page.enable')
        call('Page.navigate', {'url': page.as_uri()})
        validation = call('Runtime.evaluate', {
            'expression': """new Promise((resolve,reject)=>{
              const deadline=Date.now()+15000;
              const poll=()=>{const el=document.querySelector('#validation');
                if(el)resolve(JSON.parse(el.textContent));
                else if(Date.now()>deadline)reject(Error('Layout validation missing'));
                else setTimeout(poll,50)};poll();})""",
            'awaitPromise': True, 'returnByValue': True,
        })
        if 'exceptionDetails' in validation:
            raise RuntimeError(f'{name}: Chrome did not complete layout validation')
        report = validation['result']['value']
        if report['errors']:
            raise RuntimeError(f'{name}: ' + '; '.join(report['errors']))
        capture = call('Page.captureScreenshot', {
            'format': 'png', 'captureBeyondViewport': False,
            'clip': dict(x=0, y=0, width=w, height=h, scale=1),
        })
        output.write_bytes(base64.b64decode(capture['data']))
    finally:
        chrome.call('Target.closeTarget', {'targetId': target})
    with Image.open(output) as image:
        image.load()
        if image.size != (w, h) or image.format != 'PNG':
            raise RuntimeError(f'{name}: output is {image.format} {image.size}, expected PNG {(w,h)}')
    raw = source_for(device, frame)
    report.update(output=f'out/{device}/{frame[0]}.png', pixels=[w,h],
                  raw=f'raw/{device}/{frame[1]}', raw_sha256=hashlib.sha256(raw.read_bytes()).hexdigest(),
                  png_sha256=hashlib.sha256(output.read_bytes()).hexdigest())
    return output, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', choices=['all', *DEVICES], default='all')
    parser.add_argument('--only', choices=[f[0] for f in FRAMES])
    args = parser.parse_args()
    chrome = chrome_path()
    devices = DEVICES if args.device == 'all' else [args.device]
    frames = [f for f in FRAMES if not args.only or f[0] == args.only]
    # Preflight every input before rendering. Publish only after the entire selection passes.
    for device in devices:
        for frame in frames:
            source_for(device, frame)
    with tempfile.TemporaryDirectory(prefix='speedread-compose-') as temp:
        staged = []
        browser = Chrome(chrome, Path(temp) / 'profile')
        try:
            for device in devices:
                for frame in frames:
                    output, report = render(browser, device, frame, Path(temp))
                    staged.append((output, report))
                    print(f'PASS {report["output"]} {report["pixels"][0]}x{report["pixels"][1]}', flush=True)
        finally:
            browser.close()
        for output, report in staged:
            dest = ROOT / report['output']
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(output, dest)
        # Per-frame reports remain accurate for partial rerenders too.
        for _, report in staged:
            dest = ROOT / 'checks' / (Path(report['output']).parent.name + '-' + Path(report['output']).stem + '.json')
            dest.parent.mkdir(exist_ok=True)
            dest.write_text(json.dumps(report, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        # Avoid leaking local paths or embedded capture data in Chrome diagnostics.
        print(f'ERROR: {type(error).__name__}: {error}', file=sys.stderr)
        raise SystemExit(1)
