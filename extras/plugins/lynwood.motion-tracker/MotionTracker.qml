import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// M314 motion tracker for the LV-426 theme. CPU load is the contact: the
// busier the machine, the closer it gets, the faster the tracker pulses and
// the higher the ping. Hidden (and idle) under every other theme.
BarWidget {
  id: root
  moduleName: "lynwood.motion-tracker"

  readonly property string themeDir: Quickshell.env("HOME") + "/.config/omarchy/themes/lv-426"
  readonly property string soundFlag: Quickshell.env("HOME") + "/.local/state/lv-426/tracker-sound"

  readonly property color phosphor: "#6FE39A"
  readonly property color phosphorBright: "#A6FFC4"
  readonly property color phosphorDim: "#1E4A30"
  readonly property color amber: "#E8A33D"
  readonly property color alarm: "#D9534A"

  property bool themeActive: false
  property bool soundOn: false

  property real load: 0          // smoothed 0..1
  property real rawLoad: 0
  property real lastTotal: -1
  property real lastIdle: -1

  // 30 m when idle, 1 m when pinned.
  readonly property real meters: 1 + 29 * Math.pow(1 - load, 1.6)
  readonly property real pulsePeriod: 1700 - 1000 * load   // ms
  readonly property int contacts: 1 + Math.min(3, Math.floor(load * 4))
  readonly property color rangeColor: meters < 5 ? alarm : (meters < 12 ? amber : phosphor)

  property real pulseStart: 0
  property real now: 0
  property var blipJitter: [0, 0.07, -0.05, 0.11]
  property var blipAngle: [0, -0.45, 0.4, -0.2]

  visible: themeActive && !vertical
  implicitWidth: visible ? row.implicitWidth + Style.spacing.controlPaddingX * 2 : 0
  implicitHeight: barSize

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeActive = String(text() || "").trim() === "lv-426"
  }

  FileView {
    id: soundFile
    path: root.soundFlag
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.soundOn = String(text() || "").trim() === "on"
    onLoadFailed: root.soundOn = false
  }

  function toggleSound() {
    soundOn = !soundOn
    flagProc.command = ["sh", "-c", "mkdir -p \"${1%/*}\" && printf '%s\\n' \"$2\" > \"$1\"", "sh", soundFlag, soundOn ? "on" : "off"]
    flagProc.running = true
  }

  Process { id: flagProc }

  Process {
    id: pingProc
    command: ["pw-play", "--volume", "0.35", root.themeDir + "/sounds/" +
      (root.meters < 5 ? "ping-near.wav" : root.meters < 12 ? "ping-mid.wav" : "ping-far.wav")]
  }

  Process {
    id: statProc
    command: ["head", "-n1", "/proc/stat"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const f = text.trim().split(/\s+/).slice(1).map(Number)
        if (f.length < 5) return
        const idle = f[3] + f[4]
        const total = f.reduce((a, b) => a + b, 0)
        if (root.lastTotal >= 0 && total > root.lastTotal)
          root.rawLoad = 1 - (idle - root.lastIdle) / (total - root.lastTotal)
        root.lastTotal = total
        root.lastIdle = idle
      }
    }
  }

  Timer {
    interval: 1000
    running: root.themeActive
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!statProc.running) statProc.running = true
  }

  // Animation clock: ~30 fps, only while the theme is on.
  Timer {
    interval: 33
    running: root.themeActive && root.visible
    repeat: true
    onTriggered: {
      root.now = Date.now()
      root.load += (root.rawLoad - root.load) * 0.04
      if (root.now - root.pulseStart >= root.pulsePeriod) {
        root.pulseStart = root.now
        if (root.soundOn && !pingProc.running) pingProc.running = true
      }
      tracker.requestPaint()
    }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.spacing.sm

    Canvas {
      id: tracker
      width: Math.round(height * 1.6)
      height: Math.max(16, root.barSize - 6)
      anchors.verticalCenter: parent.verticalCenter

      onPaint: {
        const ctx = getContext("2d")
        const w = width, h = height
        const ox = w / 2, oy = h - 1
        const r = h - 2
        const spread = 1.0                       // half-angle, radians
        const a0 = -Math.PI / 2 - spread, a1 = -Math.PI / 2 + spread
        const phase = Math.min(1, (root.now - root.pulseStart) / root.pulsePeriod)

        ctx.reset()

        // Fan body and range rings.
        ctx.beginPath(); ctx.moveTo(ox, oy); ctx.arc(ox, oy, r, a0, a1); ctx.closePath()
        ctx.fillStyle = Qt.rgba(0.43, 0.89, 0.6, 0.10); ctx.fill()
        ctx.strokeStyle = Qt.rgba(0.43, 0.89, 0.6, 0.55); ctx.lineWidth = 1; ctx.stroke()
        ctx.strokeStyle = Qt.rgba(0.43, 0.89, 0.6, 0.3)
        for (let k = 1; k <= 2; k++) {
          ctx.beginPath(); ctx.arc(ox, oy, r * k / 3, a0, a1); ctx.stroke()
        }

        // Outgoing pulse wave.
        const pr = r * phase
        ctx.beginPath(); ctx.arc(ox, oy, Math.max(0.5, pr), a0, a1)
        ctx.strokeStyle = Qt.rgba(0.65, 1, 0.77, 0.9 * (1 - phase))
        ctx.lineWidth = 2; ctx.stroke()

        // Contacts: lit as the wave passes, then fade like phosphor.
        const base = (root.meters - 1) / 29
        for (let i = 0; i < root.contacts; i++) {
          const d = Math.max(0.08, Math.min(0.97, base + root.blipJitter[i]))
          const since = phase - d
          const glow = since < 0 ? 0.15 : Math.max(0.15, 1 - since * 1.8)
          const ang = -Math.PI / 2 + root.blipAngle[i] * spread
          const bx = ox + Math.cos(ang) * r * d
          const by = oy + Math.sin(ang) * r * d
          ctx.beginPath(); ctx.arc(bx, by, 4, 0, Math.PI * 2)
          ctx.fillStyle = Qt.rgba(0.43, 0.89, 0.6, 0.35 * glow); ctx.fill()
          ctx.beginPath(); ctx.arc(bx, by, 2, 0, Math.PI * 2)
          ctx.fillStyle = Qt.rgba(0.65, 1, 0.77, glow); ctx.fill()
        }

        // Operator position.
        ctx.fillStyle = root.phosphor
        ctx.fillRect(ox - 1, oy - 2, 2, 2)
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.meters.toFixed(1).padStart(4, "0") + "m"
      color: root.rangeColor
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
      Behavior on color { ColorAnimation { duration: 400 } }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) { if (root.bar) root.bar.run("omarchy launch tui btop") }
      else root.toggleSound()
    }
    onEntered: if (root.bar) root.bar.showTooltip(root,
      "CONTACT " + root.meters.toFixed(1) + " m · CPU " + Math.round(root.rawLoad * 100) + "%\n" +
      "Click: tracker audio " + (root.soundOn ? "OFF" : "ON") + " · Right-click: btop")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
