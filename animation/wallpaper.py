#!/usr/bin/env python3
"""LV-426: a photographic 30 fps cinemagraph, enabled only on external power."""
import fcntl
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import threading
import time
from ctypes import CDLL
import cairo
from power import external_power

ROOT=Path(__file__).resolve().parent.parent
CURRENT=Path.home()/'.local/state/omarchy/current/theme.name'
PHOTO=cairo.ImageSurface.create_from_png(str(ROOT/'animation/photo.png'))
VIDEO=ROOT/'animation/creatures.mp4'
WIDTH,HEIGHT,FPS=1920,1294,30
STATUS=Path(os.environ.get('XDG_RUNTIME_DIR','/tmp'))/'lv-426-playback.json'

class Frames:
    """Decodes the loop at 30 fps. Pausing simply stops reading: FFmpeg then
    blocks on the full pipe and uses no CPU, and playback resumes in place."""
    def __init__(self):
        self.latest=None
        self.serial=0
        self.stopping=threading.Event()
        self.playing=threading.Event()
        self.playing.set()
        self.process=subprocess.Popen([
            'ffmpeg','-nostdin','-v','error','-threads','2','-stream_loop','-1',
            '-i',str(VIDEO),'-an','-sn','-dn','-filter_threads','1','-threads','1','-pix_fmt','bgr0','-f','rawvideo','pipe:1'
        ],stdout=subprocess.PIPE,bufsize=WIDTH*HEIGHT*4)
        self.worker=threading.Thread(target=self.read,name='lv426-video',daemon=True)
        self.worker.start()

    def read(self):
        size=WIDTH*HEIGHT*4
        deadline=time.monotonic()
        try:
            while not self.stopping.is_set():
                if not self.playing.is_set():
                    self.playing.wait(1)
                    deadline=time.monotonic()
                    continue
                # Only raw bytes cross threads; Cairo is used on the GTK thread only.
                pixels=bytearray(size)
                view=memoryview(pixels)
                filled=0
                while filled<size:
                    count=self.process.stdout.readinto(view[filled:])
                    if not count:
                        return
                    filled+=count
                self.latest=pixels
                self.serial+=1
                # Pace playback here rather than with -re, so a pause never
                # makes FFmpeg race to catch up afterwards.
                deadline=max(deadline+1/FPS,time.monotonic()-1/FPS)
                delay=deadline-time.monotonic()
                if delay>0:
                    time.sleep(delay)
        except (OSError,ValueError):
            pass

    def set_playing(self,playing):
        if playing:
            self.playing.set()
        else:
            self.playing.clear()

    def stop(self):
        self.stopping.set()
        self.playing.set()
        if self.process.poll() is None:
            self.process.terminate()
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.process.kill();self.process.wait()
        self.worker.join(timeout=2)
        self.process.stdout.close()


def hyprland(query):
    path=Path(os.environ.get('XDG_RUNTIME_DIR','/tmp'))/'hypr'/os.environ.get('HYPRLAND_INSTANCE_SIGNATURE','')/'.socket.sock'
    try:
        with socket.socket(socket.AF_UNIX) as sock:
            sock.settimeout(.5)
            sock.connect(str(path))
            sock.sendall(('j/'+query).encode())
            data=b''
            while chunk:=sock.recv(65536):
                data+=chunk
        return json.loads(data)
    except (OSError,ValueError):
        return None


def should_play():
    """Additional AC-only savings while the animation cannot be seen."""
    workspace=hyprland('activeworkspace')
    if isinstance(workspace,dict) and workspace.get('hasfullscreen'):
        return False
    monitors=hyprland('monitors')
    if isinstance(monitors,list) and monitors and not any(m.get('dpmsStatus',True) for m in monitors):
        return False
    return True


def to_surface(pixels):
    # GTK can retain a Cairo snapshot after the draw callback, so each frame is
    # copied into a surface that owns its memory rather than borrowing a buffer.
    surface=cairo.ImageSurface(cairo.FORMAT_RGB24,WIDTH,HEIGHT)
    surface.get_data()[:]=pixels
    surface.mark_dirty()
    return surface


def paint(cr,w,h,frame):
    photo=frame or PHOTO
    scale=max(w/photo.get_width(),h/photo.get_height())
    cr.save()
    cr.translate((w-photo.get_width()*scale)/2,(h-photo.get_height()*scale)/2)
    cr.scale(scale,scale)
    cr.set_source_surface(photo,0,0)
    cr.get_source().set_filter(cairo.FILTER_BILINEAR)
    cr.paint()
    cr.restore()

CDLL('libgtk4-layer-shell.so')
import gi
gi.require_version('Gtk','4.0')
gi.require_version('Gtk4LayerShell','1.0')
from gi.repository import Gtk,Gdk,GLib,Gtk4LayerShell as Layer

class Wallpaper(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='local.codex.LV426')
        self.views=[]
        self.frames=None
        self.drawn=-1
        self.surface=None
        self.initialized=False
        self.tick_id=0
        self.mode=None
        self.connect('activate',self.activate_scene)
        self.connect('shutdown',self.shutdown_scene)

    def activate_scene(self,app):
        if self.initialized:
            return
        if not Layer.is_supported():
            print('LV-426 requires Wayland layer-shell.',file=sys.stderr)
            self.quit();return
        self.initialized=True
        self.monitors=Gdk.Display.get_default().get_monitors()
        self.monitors.connect('items-changed',self.rebuild)
        # Keep the application alive during monitor changes.
        self.hold()
        self.rebuild()
        self.check_power()
        GLib.timeout_add(500,self.check_theme)
        GLib.timeout_add(1000,self.check_power)

    def rebuild(self,*args):
        for window,area in self.views:
            window.close()
        self.views=[]
        for i in range(self.monitors.get_n_items()):
            window=Gtk.ApplicationWindow(application=self)
            Layer.init_for_window(window)
            Layer.set_namespace(window,'lv-426-atmosphere')
            Layer.set_layer(window,Layer.Layer.BACKGROUND)
            Layer.set_monitor(window,self.monitors.get_item(i))
            Layer.set_keyboard_mode(window,Layer.KeyboardMode.NONE)
            Layer.set_exclusive_zone(window,-1)
            for edge in (Layer.Edge.TOP,Layer.Edge.BOTTOM,Layer.Edge.LEFT,Layer.Edge.RIGHT):
                Layer.set_anchor(window,edge,True)
            area=Gtk.DrawingArea()
            area.set_draw_func(lambda widget,cr,w,h:paint(cr,w,h,self.surface if self.frames else None))
            window.set_child(area)
            window.present()
            self.drawn=-1
            window.get_surface().set_input_region(cairo.Region())
            self.views.append((window,area))

    def redraw(self):
        for window,area in self.views:
            area.queue_draw()

    def tick(self):
        if not self.frames:
            self.tick_id=0
            return False
        if self.frames.serial!=self.drawn:
            self.drawn=self.frames.serial
            pixels=self.frames.latest
            if pixels is not None:
                self.surface=to_surface(pixels)
            self.redraw()
        return True

    def record_state(self,mode):
        pid=self.frames.process.pid if self.frames else None
        if (mode,pid)==self.mode:
            return
        self.mode=(mode,pid)
        state={'mode':mode,'decoder_pid':pid,
               'fps':FPS,'policy':'charger-only'}
        try:
            STATUS.write_text(json.dumps(state)+'\n')
        except OSError:
            pass
        print('LV-426: '+mode,flush=True)

    def check_power(self):
        # Check power before ever launching a decoder, including at login.
        # Unplugging destroys the decoder and frame buffers instead of pausing it.
        if not external_power():
            if self.tick_id:
                GLib.source_remove(self.tick_id)
                self.tick_id=0
            if self.frames:
                self.frames.stop()
                self.frames=None
                self.surface=None
                self.drawn=-1
                self.redraw()
            self.record_state('static-battery')
            return True
        visible=should_play()
        if self.frames and self.frames.process.poll() is not None:
            self.frames.stop()
            self.frames=None
        if visible and not self.frames and VIDEO.exists():
            try:
                self.frames=Frames()
            except OSError as error:
                print('LV-426 decoder unavailable: '+str(error),file=sys.stderr,flush=True)
                self.record_state('static-decoder-unavailable')
                return True
            self.drawn=-1
        if self.frames:
            self.frames.set_playing(visible)
        if visible and not self.tick_id:
            self.tick_id=GLib.timeout_add(33,self.tick)
        elif not visible and self.tick_id:
            GLib.source_remove(self.tick_id)
            self.tick_id=0
        self.record_state('animated-ac' if visible else 'paused-ac')
        return True

    def check_theme(self):
        if not theme_active():
            self.quit();return False
        return True

    def shutdown_scene(self,*args):
        if self.frames:
            self.frames.stop()
            self.frames=None
        self.record_state('stopped')

def theme_active():
    try:
        return CURRENT.read_text().strip()=='lv-426'
    except OSError:
        return False


def main():
    if not theme_active():
        return
    lock_path=Path(os.environ.get('XDG_RUNTIME_DIR','/tmp'))/('lv-426-'+str(os.getuid())+'.lock')
    with lock_path.open('w') as lock:
        try:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            return
        Wallpaper().run([sys.argv[0]])


if __name__=='__main__':
    main()
