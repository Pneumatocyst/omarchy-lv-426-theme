#!/usr/bin/env python3
"""An animated, theme-aware terminal welcome. Python standard library only."""
import argparse
import curses
import json
import math
import os
from pathlib import Path
import platform
import random
import shutil
import subprocess
import sys
import time

THEME = Path.home() / '.local/state/omarchy/current/theme.name'
WIDTH, HEIGHT = 64, 24


def active():
    try:
        return THEME.read_text().strip() == 'lv-426'
    except OSError:
        return False


def machine_info():
    data = {}
    try:
        result = subprocess.run(
            ['fastfetch', '--format', 'json', '--structure', 'OS:Host:CPU:GPU'],
            capture_output=True, text=True, timeout=2, check=True)
        data = {item['type']: item.get('result') for item in json.loads(result.stdout)}
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    system, host, cpu = (data.get(k) or {} for k in ('OS', 'Host', 'CPU'))
    return [
        ('OS', ' '.join(filter(None, [system.get('name', platform.system()), system.get('versionID')]))),
        ('COMPUTER', host.get('name', platform.machine())),
        ('KERNEL', platform.release()),
        ('CPU', cpu.get('cpu', platform.machine()).replace('(R)', '').replace('(TM)', '')),
        ('CORES', f"{cpu.get('cores', {}).get('physical', '?')} physical / {cpu.get('cores', {}).get('logical', '?')} threads"),
        ('GPU', ' / '.join(g.get('name', '?') for g in data.get('GPU') or []) or 'Unavailable'),
        ('MEMORY', 'Unavailable'), ('UPTIME', 'Unavailable'),
        ('DESKTOP', os.environ.get('XDG_CURRENT_DESKTOP', 'Hyprland')),
        ('SHELL', Path(os.environ.get('SHELL', '/bin/bash')).name),
    ]


def refresh(info):
    info = list(info)
    try:
        mem = {k: int(v.split()[0]) for k, v in
               (line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())}
        used = (mem['MemTotal'] - mem['MemAvailable']) / 1048576
        info[6] = ('MEMORY', f"{used:.1f} / {mem['MemTotal']/1048576:.1f} GiB")
        minutes = int(float(Path('/proc/uptime').read_text().split()[0]) / 60)
        info[7] = ('UPTIME', f'{minutes//60}h {minutes%60:02d}m')
    except (OSError, ValueError, KeyError):
        pass
    return info


class Activity:
    """CPU deltas, smoothed to avoid sudden changes in the creature's gait."""
    def __init__(self):
        self.previous = self.read()
        self.load = 0.0
        self.ready = False

    @staticmethod
    def read():
        try:
            fields = [int(v) for v in Path('/proc/stat').read_text().splitlines()[0].split()[1:9]]
            return sum(fields), fields[3] + fields[4]
        except (OSError, ValueError, IndexError):
            return None

    def sample(self):
        current = self.read()
        if current and self.previous:
            total = current[0] - self.previous[0]
            idle = current[1] - self.previous[1]
            if total > 0 and 0 <= idle <= total:
                raw = max(0.0, min(1.0, 1 - idle / total))
                self.load = self.load * .65 + raw * .35 if self.ready else raw
                self.ready = True
        self.previous = current
        return self.load

    @property
    def speed(self):
        return .20 + 1.6 * math.sqrt(self.load)

    @property
    def state(self):
        if not self.ready:
            return 'SENSING'
        return 'PROWL' if self.load < .15 else 'ALERT' if self.load < .55 else 'PURSUIT'


def creature(t):
    """Articulate a dome, rib cage, limbs and tail in a character raster."""
    grid = {}
    rng = random.Random(int(t * 10))
    def dot(x, y, char=None):
        x, y = round(x), round(y)
        if 0 <= x < WIDTH and 0 <= y < HEIGHT:
            grid[x, y] = char or rng.choice('01:/|+=x#%')
    def line(a, b, thick=0, char=None):
        count = max(2, int(math.dist(a, b)*3))
        for i in range(count+1):
            x, y = (a[j]+(b[j]-a[j])*i/count for j in (0, 1))
            dot(x, y, char)
            if thick:
                dot(x-thick, y, char)
                dot(x+thick, y, char)
    def ellipse(cx, cy, rx, ry):
        for y in range(max(0, int(cy-ry)), min(HEIGHT, int(cy+ry)+2)):
            for x in range(max(0, int(cx-rx)), min(WIDTH, int(cx+rx)+2)):
                q = ((x-cx)/rx)**2 + ((y-cy)/ry)**2
                if q <= 1:
                    dot(x, y, rng.choice('.:+') if q < .35 else None)
    phase = t * math.tau * 1.15
    bob = .4*math.cos(phase*2)
    previous = (29, 15+bob)
    for i in range(1, 46):
        u = i/45
        point = (29-26*u, 15+bob-9*u+3*math.sin(u*math.pi+phase*.6)*u)
        line(previous, point, .7*(1-u), '/')
        previous = point
    for side in (1, -1):
        swing = math.sin(phase+(0 if side == 1 else math.pi))
        hip = (30, 15+bob)
        knee = (30+9*swing, 18-1.8*max(0, -swing))
        ankle = (29-10*swing, 21.5-3*max(0, swing))
        line(hip, knee, 1, ':' if side == 1 else None)
        line(knee, ankle, .7, ':' if side == 1 else None)
        line(ankle, (ankle[0]+5, ankle[1]+.5), .5, '_')
        elbow = (39-8*swing, 13+bob)
        hand = (46-7*swing, 11+2*swing+bob)
        line((36, 10+bob), elbow, .7)
        line(elbow, hand, .4)
        for claw in range(3):
            line(hand, (hand[0]+3, hand[1]+claw*.7), 0, '/')
    for i in range(4):
        line((31+i, 13-i+bob), (25+i, 9-i+bob), .5, '|')
    ellipse(32, 12+bob, 4.5, 4.2)
    line((34, 11+bob), (39, 7+bob), 1.3)
    for j in range(5):
        line((29, 10+j+bob), (34, 10.5+j+bob), 0, ')')
    ellipse(43, 5+bob, 12, 2.7)
    for x in range(34, 53):
        dot(x, 3+bob, '_')
    line((43, 7+bob), (53, 7+bob), .5, 'V')
    line((48, 8+bob), (55, 8+bob), 0, '=')
    dot(56, 8+bob, '>')
    for x in range(WIDTH):
        if (x+int(t*18))%9 < 3:
            dot(x, 23, '.')
    return [''.join(grid.get((x,y), ' ') for x in range(WIDTH)) for y in range(HEIGHT)]


# Tones are terminal palette roles, so the display follows the theme's ANSI
# colors: green is MU-TH-UR phosphor, yellow is Weyland-Yutani amber.
DIM, BODY, NEAR, TEETH, TITLE, KEY, VALUE, ALARM = range(8)
TONE_OF = {'/': DIM, '_': DIM, '.': DIM, ':': NEAR, 'V': TEETH, '=': TEETH, '>': TEETH}
ANSI = {DIM: '2;32', BODY: '32', NEAR: '1;32', TEETH: '1;97', TITLE: '33',
        KEY: '2;32', VALUE: '37', ALARM: '1;31'}
STATE_TONE = {'SENSING': KEY, 'PROWL': BODY, 'ALERT': TITLE, 'PURSUIT': ALARM}


def art_runs(text):
    """Split a raster row into (text, tone) runs."""
    runs = []
    for char in text:
        tone = TONE_OF.get(char, BODY)
        if runs and runs[-1][1] == tone:
            runs[-1][0] += char
        else:
            runs.append([char, tone])
    return [tuple(run) for run in runs]


def detail_runs(text, iw):
    if text.startswith('\0'):
        return [(text[1:], TITLE)]
    if text.startswith('\1'):
        return [(text[1:], STATE_TONE.get(text.split()[-1], BODY))]
    return [(text[:9], KEY), (text[9:iw], VALUE)]


def panel(t, info, cols, height=26):
    """Rows of (text, tone) runs: the creature, then or beside the dossier."""
    import textwrap
    art = creature(t)
    if cols >= 76:
        aw = min(64, (cols-5)//2)
        iw = cols-aw-5
        detail = ['\0SPECIAL ORDER 937', '\0SCIENCE OFFICER EYES ONLY', '']
        for key, value in info:
            detail += textwrap.wrap(f'{key:<8} {value}', width=iw, subsequent_indent=' '*9)
        detail += ['', '\1BIO-SIGNAL  ' + ('ACTIVE' if info else 'NONE')]
        rows = min(24, max(8, height))
        scaled = [''.join(art[min(23, int(y*24/rows))][int(x*64/aw)] for x in range(aw)) for y in range(rows)]
        lines = []
        for i in range(max(rows, len(detail))):
            row = [(' ', BODY)] + art_runs(scaled[i] if i < rows else ' '*aw) + [('  ', BODY)]
            if i < len(detail) and detail[i]:
                row += detail_runs(detail[i], iw)
            lines.append(row)
        return lines
    # Narrow panes keep the full silhouette with a compact system readout below.
    aw = max(8, cols-2)
    rows = min(12, max(4, height-9))
    result = [art_runs(''.join(art[int(y*24/rows)][min(63,int(x*64/aw))] for x in range(aw))) for y in range(rows)]
    return result + [[(f'{k}: '[:cols-1], KEY), (str(v)[:max(0, cols-3-len(k))], VALUE)] for k,v in info]


def tracker(motion, load, width=18):
    """Motion-tracker strip: a sweep pulses outward, a blip closes with load."""
    sweep = int(motion*9) % width
    blip = int((width-2)*(1-min(1, load*1.4)))
    cells = [')' if (i-sweep) % width < 3 else ' ' for i in range(width)]
    cells[max(0, min(width-1, blip))] = '*'
    return '[' + ''.join(cells) + ']', f'{2+28*(1-load):4.1f}m'


def animate(screen, info, duration, preview):
    try:
        curses.curs_set(0)
    except curses.error:
        pass
    screen.timeout(83)
    attr = {tone: 0 for tone in ANSI}
    if curses.has_colors():
        curses.start_color()
        curses.use_default_colors()
        for pair, color in enumerate((curses.COLOR_GREEN, curses.COLOR_YELLOW, curses.COLOR_RED, curses.COLOR_WHITE), 1):
            curses.init_pair(pair, color, -1)
        green, amber, red, white = (curses.color_pair(i) for i in range(1, 5))
        attr = {DIM: green | curses.A_DIM, BODY: green, NEAR: green | curses.A_BOLD,
                TEETH: white | curses.A_BOLD, TITLE: amber, KEY: green | curses.A_DIM,
                VALUE: white, ALARM: red | curses.A_BOLD}
    started = time.monotonic()
    previous_second = -1
    activity = Activity()
    motion = 0.0
    previous_frame = started
    frame = 0
    while True:
        now = time.monotonic()
        elapsed = now-started
        motion += min(now-previous_frame, .25) * activity.speed
        previous_frame = now
        frame += 1
        if duration and elapsed >= duration:
            break
        if int(elapsed) != previous_second:
            previous_second = int(elapsed)
            if not preview and not active():
                break
            info = refresh(info)
            activity.sample()
        h, w = screen.getmaxyx()
        screen.erase()
        state = activity.state
        display_info = [('ACTIVITY', f'{state} / CPU {activity.load:.0%}' if activity.ready else 'SENSING CPU...')] + info
        lines = panel(motion, display_info, w, h-4)
        # A bright phosphor band rolls down the screen like a CRT refresh.
        band = frame % (len(lines)+12)
        strip, distance = tracker(motion, activity.load)
        try:
            screen.addnstr(0, 0, ' MU-TH-UR 6000 // LV-426 UPLINK', max(0, w-1), attr[NEAR])
            right = f'{strip} {distance}  {state:<7} '
            if w > len(right)+34:
                screen.addnstr(0, w-len(right)-1, right, len(right), attr[STATE_TONE[state]])
            for y, row in enumerate(lines[:max(0, h-3)], 1):
                x = 0
                for text, tone in row:
                    if x >= w-1:
                        break
                    style = attr[tone]
                    if tone in (BODY, DIM) and abs(y-band) <= 1:
                        style = attr[NEAR]
                    screen.addnstr(y, x, text, w-1-x, style)
                    x += len(text)
            screen.addnstr(h-1, 0, ' INTERFACE 2037 READY FOR INQUIRY  //  any key: shell  //  xeno: replay',
                           max(0, w-1), attr[TITLE])
        except curses.error:
            pass
        screen.refresh()
        key = screen.getch()
        if key not in (-1, curses.KEY_RESIZE):
            break
    return motion, refresh(info)


def print_panel(lines, color):
    for row in lines:
        text = ''.join(f'\033[{ANSI[tone]}m{run}\033[0m' if color and run.strip() else run
                       for run, tone in row)
        print(text.rstrip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--intro', action='store_true', help='Six-second welcome, then the shell')
    parser.add_argument('--preview', action='store_true', help='Preview even with another theme selected')
    parser.add_argument('--snapshot', action='store_true', help='Print a still frame')
    args = parser.parse_args()
    if not args.preview and not active():
        return
    if not args.snapshot and (not sys.stdin.isatty() or not sys.stdout.isatty() or os.environ.get('TERM') in (None,'dumb')):
        return
    info, elapsed = refresh(machine_info()), 0
    if not args.snapshot:
        try:
            elapsed, info = curses.wrapper(animate, info, 6 if args.intro else 0, args.preview)
        except (KeyboardInterrupt, curses.error):
            return
    if args.preview or active():
        cols = shutil.get_terminal_size((110,32)).columns
        color = sys.stdout.isatty() and os.environ.get('TERM') not in (None, 'dumb') and 'NO_COLOR' not in os.environ
        print_panel(panel(elapsed, info, cols), color)
        print(f"\n  {chr(27)+'[33m' if color else ''}Uplink ready.{chr(27)+'[0m' if color else ''} "
              'Type xeno to run the specimen display.\n')


if __name__ == '__main__':
    main()
