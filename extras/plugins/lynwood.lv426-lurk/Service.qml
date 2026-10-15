import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// LV-426 lurker. Something closes in while you are away: the M314 tracker
// starts pinging far off, then nearer and faster, until the screensaver comes
// up. If you are still gone when the screen locks, the klaxon sounds. Come
// back first and contact is lost. Silent under every other theme, and while
// stay-awake is on.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string themeDir: home + "/.config/omarchy/themes/lv-426"
  readonly property string stayAwakePath: home + "/.local/state/omarchy/indicators/stay-awake"
  readonly property string screensaverClass: "org.omarchy.screensaver"

  // Follow the same idle settings as Omarchy's idle service.
  readonly property var idleConfig: shell && shell.shellConfig && shell.shellConfig.idle ? shell.shellConfig.idle : ({})
  readonly property int screensaverSeconds: seconds(idleConfig.screensaver, 150)
  readonly property int lockSeconds: seconds(idleConfig.lock, 300)

  // The approach: far pings 90 s before the screensaver, then mid, then near.
  readonly property int farAt: Math.max(15, screensaverSeconds - 90)
  readonly property int midAt: Math.max(farAt + 5, screensaverSeconds - 45)
  readonly property int nearAt: Math.max(midAt + 5, screensaverSeconds - 20)

  property bool themeActive: false
  property bool stayAwake: false
  property int stage: 0              // 0 none, 1 far, 2 mid, 3 near
  property bool pinged: false        // anything played this idle stretch
  property var screensavers: ({})
  readonly property bool screensaverUp: Object.keys(screensavers).length > 0
  readonly property bool armed: themeActive && !stayAwake

  function seconds(value, fallback) {
    var n = Number(value)
    return isFinite(n) && n > 0 ? Math.round(n) : fallback
  }

  function play(file, volume) {
    var p = soundComponent.createObject(root, { command: ["pw-play", "--volume", String(volume), root.themeDir + "/sounds/" + file] })
    p.exited.connect(function() { p.destroy() })
    p.running = true
  }

  function setStage(n) {
    if (!root.armed || root.screensaverUp) return
    root.stage = n
    root.ping()
    pingTimer.restart()
  }

  function ping() {
    if (!root.armed || root.screensaverUp || root.stage === 0) return
    root.pinged = true
    play(["", "ping-far.wav", "ping-mid.wav", "ping-near.wav"][root.stage], [0, 0.18, 0.26, 0.34][root.stage])
  }

  function userBack() {
    var wasHunted = root.pinged
    root.stage = 0
    root.pinged = false
    pingTimer.stop()
    klaxonTimer.stop()
    if (wasHunted && root.armed) {
      play("notify.wav", 0.3)
      notifyProc.running = true
    }
  }

  IdleMonitor {
    id: farMonitor
    enabled: root.armed
    timeout: root.farAt
    respectInhibitors: true
    onIsIdleChanged: isIdle ? root.setStage(1) : (root.screensaverUp ? null : root.userBack())
  }
  IdleMonitor {
    enabled: root.armed
    timeout: root.midAt
    respectInhibitors: true
    onIsIdleChanged: if (isIdle) root.setStage(2)
  }
  IdleMonitor {
    enabled: root.armed
    timeout: root.nearAt
    respectInhibitors: true
    onIsIdleChanged: if (isIdle) root.setStage(3)
  }

  Timer {
    id: pingTimer
    repeat: true
    interval: [4500, 4500, 2600, 1150][root.stage]
    onTriggered: root.ping()
  }

  // The screensaver is the tracker going quiet. If it is still up when the
  // lock comes, it is already in the room.
  Timer {
    id: klaxonTimer
    interval: Math.max(1000, (root.lockSeconds - root.screensaverSeconds) * 1000 - 600)
    onTriggered: if (root.armed && root.screensaverUp) root.play("klaxon.wav", 0.3)
  }

  onScreensaverUpChanged: {
    if (screensaverUp) {
      pingTimer.stop()
      if (root.pinged && root.lockSeconds > root.screensaverSeconds) klaxonTimer.restart()
    } else {
      klaxonTimer.stop()
      if (!farMonitor.isIdle) root.userBack()
    }
  }

  onArmedChanged: if (!armed) { stage = 0; pinged = false; pingTimer.stop(); klaxonTimer.stop() }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event && event.name ? event.name : "")
      var data = String(event && event.data ? event.data : "")
      var next
      if (name === "openwindow") {
        var parts = data.split(",")
        if (parts[2] === root.screensaverClass) {
          next = Object.assign({}, root.screensavers); next[parts[0]] = true; root.screensavers = next
        }
      } else if (name === "closewindow" && root.screensavers[data]) {
        next = Object.assign({}, root.screensavers); delete next[data]; root.screensavers = next
      }
    }
  }

  FileView {
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeActive = String(text() || "").trim() === "lv-426"
  }

  // Stay-awake is a flag file; poll it cheaply rather than watch a directory.
  Timer {
    interval: 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!stayAwakeProbe.running) stayAwakeProbe.running = true
  }
  Process {
    id: stayAwakeProbe
    command: ["test", "-e", root.stayAwakePath]
    onExited: function(code) { root.stayAwake = code === 0 }
  }

  Process {
    id: notifyProc
    command: ["omarchy-notification-send", "-g", "󰍹", "M314 MOTION TRACKER", "CONTACT LOST"]
  }

  Component { id: soundComponent; Process {} }

  Component.onCompleted: console.log("lv426-lurk ready: far=" + farAt + "s mid=" + midAt + "s near=" + nearAt + "s screensaver=" + screensaverSeconds + "s lock=" + lockSeconds + "s")
}
