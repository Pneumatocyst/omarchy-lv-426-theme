#!/usr/bin/env python3
"""Render animation/creatures.mp4: the LV-426 cinemagraph loop.

Every motion is a smooth, masked local warp of photo.png (no overlays or
particles), driven by periodic functions with whole-number cycles per loop,
so the 24 s loop is seamless. Tune AMOUNT to scale all motion at once.

Needs NumPy and OpenCV only while rendering, e.g.:
  uv run --no-project --with numpy --with opencv-python-headless \
      python render.py [--preview=<dir>]
"""
import math
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

cv2.setNumThreads(2)

HERE = Path(__file__).resolve().parent
W, H, FPS, SECONDS = 1920, 1294, 30, 24
FRAMES = FPS * SECONDS
AMOUNT = 1.0          # global motion multiplier
S = W / 1024          # region coordinates below are given on a 1024-wide photo

TAU = 2 * math.pi


def wave(t, cycles, phase=0.0):
    return math.sin(TAU * (cycles * t / SECONDS + phase))


def burst(t, cycles, phase, sharp=10):
    """0 most of the time, rising to 1 in short periodic bursts."""
    return max(0.0, wave(t, cycles, phase)) ** sharp


def ease_wave(t, cycles, phase=0.0):
    """Like wave, but lingers at the extremes: reads as deliberate movement."""
    s = wave(t, cycles, phase)
    return math.sin(math.pi * 0.5 * s)


class Region:
    """Elliptical soft mask in 1024-space, evaluated once on its bounding box."""

    def __init__(self, cx, cy, rx, ry, core=0.45, angle=0.0):
        self.cx, self.cy, self.rx, self.ry = cx * S, cy * S, rx * S, ry * S
        reach = max(self.rx, self.ry)
        x0, x1 = int(max(0, self.cx - reach)), int(min(W, self.cx + reach + 1))
        y0, y1 = int(max(0, self.cy - reach)), int(min(H, self.cy + reach + 1))
        self.box = (slice(y0, y1), slice(x0, x1))
        ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        self.xs, self.ys = xs, ys
        a = math.radians(angle)       # tilt of the ellipse's long axis
        u = (xs - self.cx) * math.cos(a) + (ys - self.cy) * math.sin(a)
        v = -(xs - self.cx) * math.sin(a) + (ys - self.cy) * math.cos(a)
        r = np.sqrt((u / self.rx) ** 2 + (v / self.ry) ** 2)
        e = np.clip((r - core) / (1 - core), 0, 1)
        self.mask = (1 - e * e * (3 - 2 * e)).astype(np.float32)  # smoothstep falloff

    def rotate(self, dx, dy, px, py, degrees):
        """Add a rotation about (px, py) in 1024-space to the displacement maps."""
        a = math.radians(degrees * AMOUNT)
        px, py = px * S, py * S
        ox, oy = self.xs - px, self.ys - py
        # Backward map: where does this output pixel come from?
        sx = px + ox * math.cos(-a) - oy * math.sin(-a)
        sy = py + ox * math.sin(-a) + oy * math.cos(-a)
        dx[self.box] += (sx - self.xs) * self.mask
        dy[self.box] += (sy - self.ys) * self.mask

    def shift(self, dx, dy, mx, my):
        dx[self.box] -= mx * S * AMOUNT * self.mask
        dy[self.box] -= my * S * AMOUNT * self.mask

    def scale(self, dx, dy, k):
        """Radial swell about the region centre (k = 0.03 is 3 %)."""
        f = 1 / (1 + k * AMOUNT)
        dx[self.box] += (self.cx + (self.xs - self.cx) * f - self.xs) * self.mask
        dy[self.box] += (self.cy + (self.ys - self.cy) * f - self.ys) * self.mask

    def undulate(self, dx, dy, t, amp, wavelength, cycles, angle_deg=0.0):
        """Travelling wave across the region, perpendicular to angle_deg."""
        a = math.radians(angle_deg)
        along = (self.xs * math.cos(a) + self.ys * math.sin(a)) / (wavelength * S)
        offset = amp * S * AMOUNT * np.sin(TAU * (along - cycles * t / SECONDS))
        dx[self.box] += -math.sin(a) * offset * self.mask
        dy[self.box] += math.cos(a) * offset * self.mask


# ---- the scene ---------------------------------------------------------------
# Big xenomorph head: cut out along this outline (1024-space) and moved as a
# rigid layer over a background rebuilt by inpainting, so nothing smears
# where it moves away from. Only the neck (NECK) stretches to follow it.
HEAD_OUTLINE = [(378, 92), (390, 62), (410, 51), (440, 46), (470, 48), (500, 54),
                (530, 66), (555, 81), (575, 99), (592, 118), (600, 135), (585, 150),
                (555, 155), (520, 150), (490, 142), (460, 140), (430, 143),
                (405, 141), (388, 133), (378, 115)]
HEAD_PIVOT = (600, 150)
NECK = Region(572, 178, 58, 62, core=0.25)
CHEST = Region(548, 263, 85, 78, core=0.3)         # its rib cage
ARM = Region(430, 250, 70, 60, core=0.35)          # its forearm, reaching left
LEFT_HEAD = Region(262, 335, 68, 66, core=0.4)     # elongated head on the left
TAIL = Region(250, 225, 105, 50, core=0.35)        # ribbed tail curling top-left
HUGGER = Region(682, 335, 58, 44, core=0.3)        # facehugger
RIGHT_HEAD = Region(806, 405, 58, 58, core=0.4)    # screaming head, right
HAND = Region(680, 590, 48, 34, core=0.3)          # hand reaching, bottom
RIGHT_HAND = Region(922, 392, 40, 34, core=0.3)    # raised hand, far right
LIGHT = Region(360, 120, 260, 230, core=0.0)       # light shaft (brightness only)


def displacement(t):
    dx = np.zeros((H, W), np.float32)
    dy = np.zeros((H, W), np.float32)
    # Shallow breathing every six seconds; staggered phases keep the tableau alive.
    CHEST.scale(dx, dy, 0.005 * (0.5 + 0.5 * wave(t, 4)))
    ARM.rotate(dx, dy, 470, 230, 0.20 * wave(t, 2, 0.3))
    LEFT_HEAD.rotate(dx, dy, 300, 300, 0.34 * wave(t, 1, 0.6) + 0.07 * wave(t, 3))
    TAIL.undulate(dx, dy, t, 0.42, 100, 2, angle_deg=-20)
    HUGGER.undulate(dx, dy, t, 0.14, 40, 4, angle_deg=70)
    HUGGER.shift(dx, dy, 0.12 * wave(t, 3, 0.4), 0.08 * wave(t, 2, 0.15))
    RIGHT_HEAD.rotate(dx, dy, 830, 440, 0.25 * wave(t, 1, 0.7) + 0.06 * wave(t, 3, 0.2))
    HAND.rotate(dx, dy, 650, 590, 0.22 * wave(t, 2, 0.15))
    RIGHT_HAND.rotate(dx, dy, 905, 410, -0.24 * wave(t, 1, 0.45))
    return dx, dy


def head_pose(t):
    """Restrained rigid head tilt; no abrupt strikes or rubbery skull deformation."""
    return (0.38 * wave(t, 1, 0.1) + 0.07 * wave(t, 2, 0.3),
            0.20 * wave(t, 1, 0.2), 0.30 * wave(t, 4, 0.05))


class HeadLayer:
    def __init__(self, photo):
        pts = np.array([(x * S, y * S) for x, y in HEAD_OUTLINE], np.float32)
        hard = np.zeros((H, W), np.uint8)
        cv2.fillPoly(hard, [pts.astype(np.int32)], 255)
        # Background plate: the photo with the head painted out.
        hole = cv2.dilate(hard, np.ones((15, 15), np.uint8))
        plate = cv2.inpaint(np.clip(photo, 0, 255).astype(np.uint8), hole, 12,
                            cv2.INPAINT_TELEA).astype(np.float32)
        # Inpainting comes out smooth; give the filled area the photo's grain.
        grain = photo - cv2.GaussianBlur(photo, (0, 0), 1.5)
        sigma = float(grain[hole == 0].std())
        noise = np.random.default_rng(426).normal(0, sigma, photo.shape[:2]).astype(np.float32)
        noise = cv2.GaussianBlur(noise, (0, 0), 0.6)[..., None] * (sigma / max(1e-3, float(cv2.GaussianBlur(noise, (0, 0), 0.6).std())))
        fill = cv2.GaussianBlur(hole.astype(np.float32) / 255, (0, 0), 4)[..., None]
        self.plate = plate + noise * fill
        self.matte = cv2.GaussianBlur(hard.astype(np.float32) / 255, (0, 0), 0.8)
        self.neck = np.zeros((H, W), np.float32)
        self.neck[NECK.box] = NECK.mask
        self.photo = photo
        self.px, self.py = HEAD_PIVOT[0] * S, HEAD_PIVOT[1] * S

    def render(self, t, base_x, base_y):
        angle, mx, my = head_pose(t)
        a = math.radians(-angle)
        ox, oy = base_x - self.px - mx * S, base_y - self.py - my * S
        # Backward map of the rigid motion (rotate about the pivot, then shift).
        sx = self.px + ox * math.cos(a) - oy * math.sin(a)
        sy = self.py + ox * math.sin(a) + oy * math.cos(a)
        rdx, rdy = sx - base_x, sy - base_y
        head = cv2.remap(self.photo, sx, sy, cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT)
        alpha = cv2.remap(self.matte, sx, sy, cv2.INTER_LINEAR)[..., None]
        back = cv2.remap(self.plate, base_x + rdx * self.neck, base_y + rdy * self.neck,
                         cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT)
        return head * alpha + back * (1 - alpha)


def light_gain(t):
    """Barely perceptible changes in the shaft of light; stable exposure and grain."""
    return 1.0 + 0.012 * wave(t, 1, 0.25) + 0.004 * wave(t, 3)


def main():
    preview = next((a.split('=', 1)[1] for a in sys.argv if a.startswith('--preview=')), None)
    photo = cv2.imread(str(HERE / 'photo.png'), cv2.IMREAD_COLOR)
    photo = cv2.resize(photo, (W, H), interpolation=cv2.INTER_AREA).astype(np.float32)
    base_x, base_y = np.meshgrid(np.arange(W, dtype=np.float32), np.arange(H, dtype=np.float32))
    light_mask = np.zeros((H, W), np.float32)
    light_mask[LIGHT.box] = LIGHT.mask
    light_mask = cv2.GaussianBlur(light_mask, (0, 0), 40)[..., None]
    head_layer = HeadLayer(photo)

    if preview:
        out = Path(preview)
        out.mkdir(parents=True, exist_ok=True)
        frames = range(0, FRAMES, FRAMES // 8)
        encoder = None
    else:
        frames = range(FRAMES)
        encoder = subprocess.Popen([
            'ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'bgr24',
            '-s', f'{W}x{H}', '-r', str(FPS), '-i', 'pipe:0',
            '-c:v', 'libx264', '-threads', '2', '-preset', 'slow', '-crf', '16', '-tune', 'grain', '-pix_fmt', 'yuv420p',
            '-movflags', '+faststart', str(HERE / 'creatures.new.mp4')], stdin=subprocess.PIPE)

    for n in frames:
        t = n / FPS
        dx, dy = displacement(t)
        scene = head_layer.render(t, base_x, base_y)
        frame = cv2.remap(scene, base_x + dx, base_y + dy, cv2.INTER_CUBIC,
                          borderMode=cv2.BORDER_REFLECT)
        frame *= 1 + (light_gain(t) - 1) * light_mask
        frame = np.clip(frame, 0, 255).astype(np.uint8)
        if encoder:
            encoder.stdin.write(frame.tobytes())
            if n % 48 == 0:
                print(f'frame {n}/{FRAMES}', flush=True)
        else:
            cv2.imwrite(str(out / f'frame{n:03}.png'), frame)

    if encoder:
        encoder.stdin.close()
        if encoder.wait() != 0:
            sys.exit('ffmpeg failed')
        (HERE / 'creatures.new.mp4').replace(HERE / 'creatures.mp4')
        print('wrote', HERE / 'creatures.mp4')


if __name__ == '__main__':
    main()
