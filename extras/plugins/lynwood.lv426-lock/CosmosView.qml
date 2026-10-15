import QtQuick
import Quickshell
import Quickshell.Io

// THE COSMOS lock screen: Apollo 17, Tracy's Rock (NASA AS17-140-21497).
// Shown by LockView while the-cosmos is the Omarchy theme. Deliberately quiet:
// the photograph, a slow drift of light, a few faint stars, a thin clock in the
// black sky and a hairline auth prompt over the plain. Auth state and password
// plumbing stay in LockView/Service; this view only renders and forwards input
// through `view`.
Item {
  id: cv

  property var view: null
  property bool running: visible
  property bool inputEnabled: false
  property bool authenticatingPassword: false
  property bool fingerprintConfigured: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property string hostName: "omarchy"
  property alias input: passwordInput

  readonly property bool errorState: failureMessage.length > 0
  readonly property bool typing: passwordInput.text.length > 0

  readonly property color navy: "#050B14"
  readonly property color navyDeep: "#02050A"
  readonly property color hud: "#5CC8E8"
  readonly property color gold: "#E8B04B"
  readonly property color goldBright: "#FFD27A"
  readonly property color ink: "#B9C9DA"
  readonly property color dim: "#6A7F96"
  readonly property color abort: "#FF5A5F"
  readonly property string mono: "JetBrainsMono Nerd Font"
  readonly property string thin: "Adwaita Sans"

  readonly property string themeDir: (Quickshell.env("HOME") || "") + "/.config/omarchy/themes/the-cosmos"
  readonly property var heroSources: [
    "file://" + themeDir + "/lock/tracys-rock.png",
    "file://" + themeDir + "/backgrounds/tracys-rock.jpg",
    "file://" + themeDir + "/lock/helmet.png"
  ]
  property int heroIndex: 0
  // The jpg fallback is the undimmed wallpaper; dim it here instead.
  readonly property real heroWash: heroIndex === 0 ? 0.0 : 0.3

  readonly property color fieldColor: errorState ? abort : (authenticatingPassword ? hud : (typing ? gold : hud))

  // Telemetry: battery as O₂, charger as umbilical, /proc/uptime as MET.
  property int o2: -1
  property bool umbilical: false
  property real uptime: 0

  Process {
    id: suitProc
    command: ["sh", "-c",
      "cap=; for b in /sys/class/power_supply/BAT*; do [ -r \"$b/capacity\" ] && cap=$(cat \"$b/capacity\") && break; done; " +
      "ac=0; for s in /sys/class/power_supply/*; do t=$(cat \"$s/type\" 2>/dev/null); " +
      "case $t in Mains|USB*|Wireless) [ \"$(cat \"$s/online\" 2>/dev/null)\" = 1 ] && ac=1;; esac; done; " +
      "echo \"${cap:--1} $ac $(cut -d' ' -f1 /proc/uptime)\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var f = String(text || "").trim().split(/\s+/)
        if (f.length < 3) return
        cv.o2 = parseInt(f[0])
        cv.umbilical = f[1] === "1"
        cv.uptime = parseFloat(f[2]) || 0
      }
    }
  }

  Timer {
    interval: 15000
    repeat: true
    running: cv.running
    triggeredOnStart: true
    onTriggered: if (!suitProc.running) suitProc.running = true
  }

  property date now: new Date()
  Timer {
    interval: 1000
    repeat: true
    running: cv.running
    triggeredOnStart: true
    onTriggered: { cv.now = new Date(); cv.uptime += cv.uptime > 0 ? 1 : 0 }
  }

  function pad(n, w) { var s = String(Math.floor(n)); while (s.length < w) s = "0" + s; return s }
  function metText() {
    var t = Math.floor(uptime)
    return pad(t / 86400, 2) + ":" + pad((t % 86400) / 3600, 2) + ":" + pad((t % 3600) / 60, 2) + ":" + pad(t % 60, 2)
  }

  // ── Background ───────────────────────────────────────────────────────────
  Rectangle { anchors.fill: parent; color: cv.navyDeep }

  Image {
    id: hero
    anchors.fill: parent
    source: cv.running && cv.heroIndex < cv.heroSources.length ? cv.heroSources[cv.heroIndex] : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    sourceSize.width: width
    sourceSize.height: height
    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 900 } }
    onStatusChanged: if (status === Image.Error) cv.heroIndex += 1
  }

  Rectangle { anchors.fill: parent; color: cv.navy; opacity: cv.heroWash }

  // A slow band of light drifting across the hills and boulder and back,
  // once every 24 s, like the wallpaper.
  Rectangle {
    id: lightBand
    width: cv.width * 0.55
    height: cv.height
    x: -width
    opacity: 0.05
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
      GradientStop { position: 0.5; color: Qt.rgba(0.85, 0.9, 1, 1) }
      GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
    }
    SequentialAnimation on x {
      loops: Animation.Infinite
      running: cv.running
      NumberAnimation { from: -lightBand.width; to: cv.width; duration: 12000; easing.type: Easing.InOutSine }
      NumberAnimation { from: cv.width; to: -lightBand.width; duration: 12000; easing.type: Easing.InOutSine }
    }
  }

  // A few faint stars in the black sky band (upper right).
  Repeater {
    model: [
      { x: 0.70, y: 0.040, s: 1.6, d: 4100 }, { x: 0.74, y: 0.112, s: 1.2, d: 5300 },
      { x: 0.78, y: 0.068, s: 1.4, d: 3700 }, { x: 0.83, y: 0.150, s: 1.1, d: 6100 },
      { x: 0.87, y: 0.030, s: 1.3, d: 4700 }, { x: 0.91, y: 0.095, s: 1.0, d: 5900 },
      { x: 0.95, y: 0.052, s: 1.5, d: 4300 }, { x: 0.66, y: 0.135, s: 1.0, d: 6700 },
      { x: 0.60, y: 0.060, s: 1.1, d: 5100 }, { x: 0.98, y: 0.140, s: 1.2, d: 3900 }
    ]
    delegate: Rectangle {
      required property var modelData
      x: Math.round(cv.width * modelData.x)
      y: Math.round(cv.height * modelData.y)
      width: modelData.s; height: modelData.s; radius: modelData.s / 2
      color: "#E6F0FA"
      opacity: 0.35
      SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: cv.running
        NumberAnimation { to: 0.7; duration: modelData.d; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.25; duration: modelData.d; easing.type: Easing.InOutSine }
      }
    }
  }

  // Soft left-side shade so the auth prompt reads over the regolith.
  Rectangle {
    width: Math.round(cv.width * 0.42)
    height: cv.height
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Qt.rgba(0.008, 0.02, 0.04, 0.42) }
      GradientStop { position: 1.0; color: Qt.rgba(0.008, 0.02, 0.04, 0) }
    }
  }

  // Tiny corner brackets at the screen corners.
  Repeater {
    model: 4
    delegate: Item {
      required property int index
      readonly property bool isRight: index % 2 === 1
      readonly property bool isBottom: index > 1
      x: isRight ? cv.width - 24 - 18 : 24
      y: isBottom ? cv.height - 24 - 18 : 24
      width: 18; height: 18
      opacity: 0.35
      Rectangle { x: 0; y: parent.isBottom ? 17 : 0; width: 18; height: 1; color: cv.ink }
      Rectangle { x: parent.isRight ? 17 : 0; y: 0; width: 1; height: 18; color: cv.ink }
    }
  }

  // ── Clock, date and telemetry in the black sky (upper right) ─────────────
  Column {
    anchors.right: parent.right
    anchors.rightMargin: Math.round(cv.width * 0.042)
    y: Math.round(cv.height * 0.03)
    spacing: 4

    Text {
      anchors.right: parent.right
      text: Qt.formatDateTime(cv.now, "HH:mm")
      color: cv.ink
      opacity: 0.88
      font.family: cv.thin
      font.weight: Font.Thin
      font.pixelSize: Math.round(cv.height * 0.088)
      font.letterSpacing: 3
    }
    Text {
      anchors.right: parent.right
      text: Qt.formatDateTime(cv.now, "dddd  ·  d MMMM").toUpperCase()
      color: cv.ink
      opacity: 0.55
      font.family: cv.mono
      font.pixelSize: 12
      font.letterSpacing: 5
    }
    Item { width: 1; height: 6 }
    Text {
      anchors.right: parent.right
      text: "EVA-01  ·  TAURUS-LITTROW"
      color: cv.gold
      opacity: 0.7
      font.family: cv.mono
      font.pixelSize: 11
      font.letterSpacing: 4
    }
    Text {
      anchors.right: parent.right
      text: "MET " + cv.metText() + "   ·   O₂ " + (cv.o2 < 0 ? "--" : cv.o2 + "%") + "  ·  " + (cv.umbilical ? "UMBILICAL" : "SUIT RESERVES")
      color: (!cv.umbilical && cv.o2 >= 0 && cv.o2 < 15) ? cv.abort : ((!cv.umbilical && cv.o2 >= 0 && cv.o2 < 30) ? cv.gold : cv.ink)
      opacity: 0.62
      font.family: cv.mono
      font.pixelSize: 10
      font.letterSpacing: 3
    }
  }

  // ── Auth prompt, over the open plain (left) ──────────────────────────────
  Item {
    id: auth
    width: Math.min(cv.width * 0.8, 360)
    height: authColumn.implicitHeight
    x: Math.round(cv.width * 0.045) + shakeX
    y: Math.round(cv.height * 0.50)
    property real shakeX: 0

    SequentialAnimation {
      id: shake
      NumberAnimation { target: auth; property: "shakeX"; to: -12; duration: 50 }
      NumberAnimation { target: auth; property: "shakeX"; to: 10; duration: 70 }
      NumberAnimation { target: auth; property: "shakeX"; to: -6; duration: 70 }
      NumberAnimation { target: auth; property: "shakeX"; to: 4; duration: 70 }
      NumberAnimation { target: auth; property: "shakeX"; to: 0; duration: 60 }
    }

    Column {
      id: authColumn
      width: parent.width
      spacing: 9

      Text {
        text: cv.errorState ? "ACCESS DENIED" : (cv.authenticatingPassword ? "VERIFYING..." : "AUTH // EVA-01")
        color: cv.errorState ? cv.abort : (cv.typing ? cv.gold : cv.hud)
        opacity: 0.85
        font.family: cv.mono
        font.pixelSize: 11
        font.letterSpacing: 5
        Behavior on color { ColorAnimation { duration: 250 } }
      }

      Item {
        id: field
        width: parent.width
        height: 40

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(0.02, 0.043, 0.078, 0.55)
          border.width: 1
          border.color: Qt.rgba(cv.fieldColor.r, cv.fieldColor.g, cv.fieldColor.b, cv.typing || cv.errorState ? 0.6 : 0.3)
          Behavior on border.color { ColorAnimation { duration: 250 } }
        }

        // Small corner brackets.
        Repeater {
          model: 4
          delegate: Item {
            required property int index
            readonly property bool isRight: index % 2 === 1
            readonly property bool isBottom: index > 1
            x: isRight ? field.width - 9 : 0
            y: isBottom ? field.height - 9 : 0
            width: 9; height: 9
            Rectangle { x: 0; y: parent.isBottom ? 8 : 0; width: 9; height: 1; color: cv.fieldColor; Behavior on color { ColorAnimation { duration: 250 } } }
            Rectangle { x: parent.isRight ? 8 : 0; y: 0; width: 1; height: 9; color: cv.fieldColor; Behavior on color { ColorAnimation { duration: 250 } } }
          }
        }

        // Verification scan.
        Rectangle {
          visible: cv.authenticatingPassword
          y: 1; height: parent.height - 2; width: 60
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0.36, 0.78, 0.91, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(0.36, 0.78, 0.91, 0.25) }
            GradientStop { position: 1.0; color: Qt.rgba(0.36, 0.78, 0.91, 0) }
          }
          NumberAnimation on x {
            loops: Animation.Infinite
            running: cv.authenticatingPassword
            from: -60; to: field.width; duration: 900
          }
        }

        TextInput {
          id: passwordInput
          anchors.fill: parent
          anchors.leftMargin: 16
          anchors.rightMargin: cv.fingerprintConfigured ? 40 : 16
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignLeft
          activeFocusOnPress: true
          clip: true
          maximumLength: cv.view ? cv.view.maxPasswordLength : 256
          enabled: cv.inputEnabled && !cv.authenticatingPassword
          readOnly: cv.authenticatingPassword
          echoMode: TextInput.Password
          passwordCharacter: "◆"
          passwordMaskDelay: 0
          color: cv.goldBright
          selectionColor: Qt.rgba(0.91, 0.69, 0.29, 0.35)
          selectedTextColor: cv.navy
          font.family: cv.mono
          font.pixelSize: 13
          font.letterSpacing: 5
          cursorVisible: activeFocus && cv.inputEnabled && !cv.authenticatingPassword && !cv.errorState
          cursorDelegate: Rectangle {
            width: 1; height: 16
            color: cv.gold
            visible: passwordInput.cursorVisible
            SequentialAnimation on opacity {
              loops: Animation.Infinite
              running: passwordInput.cursorVisible
              NumberAnimation { to: 0; duration: 500 }
              NumberAnimation { to: 1; duration: 500 }
            }
          }

          onTextChanged: {
            if (!cv.view) return
            if (!cv.view.syncingPasswordText) cv.view.passwordTextEdited(cv.view.boundPassword(text))
            if (text.length > 0) cv.view.requestWake(false)
            if (text.length > 0 && cv.failureMessage.length > 0) cv.view.clearFailureRequested()
          }

          onAccepted: {
            if (!cv.view) return
            var submitted = cv.view.boundPassword(cv.view.passwordText)
            cv.view.passwordTextEdited("")
            if (submitted.length > 0) cv.view.submitPassword(submitted)
          }

          Keys.onPressed: function(event) {
            if (cv.view) cv.view.requestWake(false)
            if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
              if (cv.view) cv.view.passwordTextEdited("")
              event.accepted = true
            }
          }
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          visible: passwordInput.text.length === 0
          text: cv.authenticatingPassword ? "CROSS-CHECKING"
              : (cv.errorState ? "ATTEMPT " + cv.failedAttempts + " // RE-ENTER"
                               : "PASSPHRASE")
          color: cv.errorState ? cv.abort : (cv.authenticatingPassword ? cv.hud : cv.dim)
          font.family: cv.mono
          font.pixelSize: 11
          font.letterSpacing: 4
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          visible: cv.fingerprintConfigured
          text: "󰈷"
          color: cv.hud
          font.family: cv.mono
          font.pixelSize: 15
        }
      }

      Text {
        text: cv.errorState ? "IDENTITY NOT CONFIRMED" : "ENTER TO TRANSMIT  ·  ESC CLEARS"
        color: cv.errorState ? cv.abort : cv.dim
        opacity: 0.6
        font.family: cv.mono
        font.pixelSize: 9
        font.letterSpacing: 3
      }
    }
  }

  onFailureMessageChanged: if (failureMessage.length > 0) shake.restart()
}
