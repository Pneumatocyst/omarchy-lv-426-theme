import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property int maxPasswordLength: 256
  readonly property int maxIdentityLength: 64
  readonly property int maxRainColumns: 24
  readonly property int maxRainRows: 28
  readonly property int maxScanlines: 96
  readonly property int wakeCooldownMs: 400

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  property double lastWakeEmitAt: 0

  readonly property string rawUserName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || "operator"
  readonly property string userName: boundIdentity(rawUserName, "operator")
  readonly property string hostName: boundIdentity(resolvedHost, "omarchy")
  readonly property string placeholderText: lv426
    ? "ENTER CREW ACCESS CODE // " + userName.toUpperCase()
    : "sudo password for " + userName + ":"
  readonly property int fieldWidth: Math.min(parent.width * 0.72, 760)
  readonly property int fieldHeight: 54
  readonly property int outlineThickness: 2
  readonly property int fieldFontSize: Style.font.body
  readonly property int passwordDotFontSize: Math.round(Style.font.subtitle * 1.05)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.body * 0.12)
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  readonly property int passwordDisplayLength: Math.min(passwordInput.text.length, root.maxPasswordLength)
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0

  readonly property color hackGreen: lv426 ? "#4FB87A" : "#87aa78"
  readonly property color hackGreenDim: lv426 ? "#2E6B47" : "#35514d"
  readonly property color hackGreenBright: lv426 ? "#6FE39A" : "#a3c391"
  readonly property color hackCyan: lv426 ? "#5FC9B8" : "#72aca6"
  readonly property color hackGold: lv426 ? "#E8A33D" : "#cbb77a"
  readonly property color hackRed: lv426 ? "#D9534A" : "#e18a85"
  readonly property color hackBg: lv426 ? "#030504" : "#050a09"
  readonly property color hackPanel: lv426 ? "#0A120E" : "#0a1513"

  readonly property var inputBorderSpec: errorState
    ? Border.surfaceSpec("lock", "border-error", hackRed, root.outlineThickness, "border-alpha")
    : Border.surfaceSpec("lock", "border-active", hackGreenBright, root.outlineThickness, "border-alpha")

  readonly property int rainColumns: Math.max(8, Math.min(root.maxRainColumns, Math.floor(width / 48)))
  readonly property int rainRows: Math.max(8, Math.min(root.maxRainRows, Math.ceil(height / 36)))
  readonly property int scanlineCount: Math.max(1, Math.min(root.maxScanlines, Math.ceil(height / 8)))

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function boundIdentity(value, fallback) {
    var text = String(value || "").replace(/[\r\n\t]/g, " ").trim()
    if (!text.length) return fallback
    if (text.length > root.maxIdentityLength) return text.slice(0, root.maxIdentityLength)
    return text
  }

  function boundPassword(value) {
    return String(value || "").slice(0, root.maxPasswordLength)
  }

  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    if (root.cosmos) cosmosView.input.forceActiveFocus()
    else passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    var next = root.boundPassword(passwordText)
    if (passwordInput.text === next && cosmosView.input.text === next) return
    syncingPasswordText = true
    if (passwordInput.text !== next) passwordInput.text = next
    if (cosmosView.input.text !== next) cosmosView.input.text = next
    syncingPasswordText = false
  }

  function randomHexChar() {
    return "0123456789abcdef"[Math.floor(Math.random() * 16)]
  }

  function requestWake(force) {
    var now = Date.now()
    if (!force && now - root.lastWakeEmitAt < root.wakeCooldownMs) return
    root.lastWakeEmitAt = now
    root.wakeRequested()
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
    bootLogTimer.start()
  }
  Component.onDestruction: {
    if (hostProc.running) hostProc.running = false
    if (themeProc.running) themeProc.running = false
    hostWatchdog.stop()
  }

  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(root.passwordDisplayLength)
  }

  Process {
    id: hostProc
    running: true
    command: ["/usr/bin/hostname", "-s"]
    stdout: StdioCollector {
      id: hostStdout
      waitForEnd: true
    }
    onRunningChanged: {
      if (running) hostWatchdog.restart()
      else hostWatchdog.stop()
    }
  }

  Timer {
    id: hostWatchdog
    interval: 3000
    repeat: false
    onTriggered: if (hostProc.running) hostProc.running = false
  }

  // LV-426 / MU-TH-UR 6000 look while that Omarchy theme is active.
  Process {
    id: themeProc
    running: true
    command: ["/usr/bin/cat", (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme.name"]
    stdout: StdioCollector {
      id: themeStdout
      waitForEnd: true
    }
  }

  // Watched, not read once: this view outlives theme switches.
  FileView {
    id: themeFile
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  readonly property string themeName: {
    var watched = String(themeFile.text() || "").trim()
    return watched.length > 0 ? watched : String(themeStdout.text || "").trim()
  }
  readonly property bool lv426: themeName === "lv-426"
  // THE COSMOS: helmet boot sequence (CosmosView.qml) replaces the whole stage.
  readonly property bool cosmos: themeName === "the-cosmos"

  readonly property string resolvedHost: {
    var text = String(hostStdout.text || "").trim()
    return text.length > 0 ? text : "omarchy"
  }

  Rectangle {
    id: stage
    anchors.fill: parent
    color: hackBg
    visible: !root.cosmos

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground && !root.cosmos ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      opacity: root.lv426 ? 0.2 : 0.12
      sourceSize.width: width
      sourceSize.height: height
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 1.0
      blurMax: 96
      blurMultiplier: 1.5
    }

    // Matrix rain columns — hard-capped per surface.
    Repeater {
      model: root.rainColumns
      delegate: Item {
        id: rainCol
        required property int index
        width: 22
        height: stage.height
        x: Math.floor((index + 0.5) * stage.width / Math.max(1, root.rainColumns)) - 11
        opacity: 0.08 + (index % 5) * 0.025

        property real rainOffset: -(index * 37) % 420

        Column {
          y: rainCol.rainOffset
          spacing: 2

          Repeater {
            model: root.rainRows
            delegate: Text {
              textFormat: Text.PlainText
              text: root.randomHexChar()
              color: index % 7 === 0 ? hackCyan : hackGreen
              font.family: Style.font.family
              font.pixelSize: 11
              opacity: 0.35 + (index % 4) * 0.12
            }
          }
        }

        SequentialAnimation on rainOffset {
          loops: Animation.Infinite
          running: (root.loadBackground || root.inputEnabled) && rainCol.height > 0 && !root.cosmos
          NumberAnimation {
            from: -520
            to: rainCol.height + 140
            duration: 9000 + (rainCol.index * 173) % 5000
            easing.type: Easing.Linear
          }
        }
      }
    }

    // Boot log panel
    Rectangle {
      id: bootPanel
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.min(340, parent.width * 0.28)
      color: Qt.rgba(0, 0, 0, 0.55)
      border.color: Qt.rgba(0.53, 0.67, 0.47, 0.25)
      border.width: 1
      visible: parent.width > 720

      Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 4

        Text {
          textFormat: Text.PlainText
          text: root.lv426 ? "MU-TH-UR.LOG" : "KERNEL.LOG"
          color: hackGold
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.2
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(0.53, 0.67, 0.47, 0.35)
        }

        ListView {
          id: bootLogView
          width: parent.width
          height: parent.height - 36
          clip: true
          model: ListModel { id: bootLogModel }
          spacing: 3

          delegate: Text {
            required property string line
            required property int index
            width: bootLogView.width
            textFormat: Text.PlainText
            text: line
            wrapMode: Text.Wrap
            color: line.indexOf("[ERR") >= 0 ? hackRed
                 : line.indexOf("[warn") >= 0 ? hackGold
                 : line.indexOf("[ok") >= 0 ? hackGreenBright
                 : hackCyan
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            opacity: 0.55 + Math.min(index, 8) * 0.05
          }

          onCountChanged: if (count > 0) positionViewAtEnd()
        }
      }
    }

    // LV-426: M314 motion tracker. While the screen stays locked, contacts
    // drift slowly closer; any wake knocks them back out to the edge of range.
    Item {
      id: lockTracker
      visible: root.lv426 && parent.width > 720
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 36
      width: Math.min(380, parent.width * 0.26)
      height: width * 0.78

      property real t: 0
      property real closing: 0          // 0 = edge of range, 1 = on top of you
      readonly property real meters: 2 + 28 * (1 - closing)
      readonly property real period: 1800 - 900 * closing
      property real pulseStart: 0
      property var blips: [
        { a: -0.55, d: 0.0, s: 1.0 }, { a: 0.35, d: 0.09, s: 0.8 },
        { a: -0.1, d: 0.16, s: 1.2 }, { a: 0.7, d: 0.05, s: 0.9 }
      ]

      Timer {
        interval: 40
        repeat: true
        running: lockTracker.visible && (root.loadBackground || root.inputEnabled)
        onTriggered: {
          lockTracker.t = Date.now()
          if (lockTracker.pulseStart === 0) lockTracker.pulseStart = lockTracker.t
          lockTracker.closing = Math.min(0.94, lockTracker.closing + 0.00012)
          if (lockTracker.t - lockTracker.pulseStart >= lockTracker.period) lockTracker.pulseStart = lockTracker.t
          trackerCanvas.requestPaint()
        }
      }

      Connections {
        target: root
        function onInputEnabledChanged() { lockTracker.closing = Math.max(0, lockTracker.closing - 0.25) }
      }

      Canvas {
        id: trackerCanvas
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height - 34

        onPaint: {
          const ctx = getContext("2d")
          const w = width, h = height
          const ox = w / 2, oy = h - 2, r = Math.min(h - 6, w / 2 / Math.sin(1.0))
          const a0 = -Math.PI / 2 - 1.0, a1 = -Math.PI / 2 + 1.0
          const phase = Math.min(1, (lockTracker.t - lockTracker.pulseStart) / lockTracker.period)
          ctx.reset()

          ctx.beginPath(); ctx.moveTo(ox, oy); ctx.arc(ox, oy, r, a0, a1); ctx.closePath()
          ctx.fillStyle = Qt.rgba(0.02, 0.07, 0.04, 0.75); ctx.fill()
          ctx.strokeStyle = Qt.rgba(0.43, 0.89, 0.6, 0.6); ctx.lineWidth = 1.5; ctx.stroke()

          ctx.strokeStyle = Qt.rgba(0.43, 0.89, 0.6, 0.18); ctx.lineWidth = 1
          for (let k = 1; k < 5; k++) { ctx.beginPath(); ctx.arc(ox, oy, r * k / 5, a0, a1); ctx.stroke() }
          for (let k = -2; k <= 2; k++) {
            const a = -Math.PI / 2 + k * 0.5
            ctx.beginPath(); ctx.moveTo(ox, oy); ctx.lineTo(ox + Math.cos(a) * r, oy + Math.sin(a) * r); ctx.stroke()
          }

          // Pulse wave with a soft trailing band.
          for (let j = 0; j < 6; j++) {
            const pr = r * phase - j * 3
            if (pr <= 0) continue
            ctx.beginPath(); ctx.arc(ox, oy, pr, a0, a1)
            ctx.strokeStyle = Qt.rgba(0.65, 1, 0.77, (j === 0 ? 0.9 : 0.25 / j) * (1 - phase))
            ctx.lineWidth = j === 0 ? 2 : 3; ctx.stroke()
          }

          const base = 1 - lockTracker.closing
          for (let i = 0; i < lockTracker.blips.length; i++) {
            const b = lockTracker.blips[i]
            const wobble = Math.sin(lockTracker.t / 1300 * b.s + i) * 0.03
            const d = Math.max(0.06, Math.min(0.97, base * 0.9 + b.d + wobble))
            const since = phase - d
            const glow = since < 0 ? 0.12 : Math.max(0.12, 1 - since * 1.6)
            const ang = -Math.PI / 2 + (b.a + wobble) * 1.0
            const bx = ox + Math.cos(ang) * r * d, by = oy + Math.sin(ang) * r * d
            ctx.beginPath(); ctx.arc(bx, by, 9, 0, Math.PI * 2)
            ctx.fillStyle = Qt.rgba(0.43, 0.89, 0.6, 0.22 * glow); ctx.fill()
            ctx.beginPath(); ctx.arc(bx, by, 4, 0, Math.PI * 2)
            ctx.fillStyle = Qt.rgba(0.75, 1, 0.85, glow); ctx.fill()
          }

          ctx.fillStyle = Qt.rgba(0.43, 0.89, 0.6, 1)
          ctx.beginPath(); ctx.moveTo(ox, oy - 8); ctx.lineTo(ox - 5, oy); ctx.lineTo(ox + 5, oy); ctx.closePath(); ctx.fill()
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        textFormat: Text.PlainText
        text: "MOTION DETECTED  ::  " + lockTracker.meters.toFixed(1) + " M"
        color: lockTracker.meters < 6 ? hackRed : lockTracker.meters < 14 ? hackGold : hackGreenBright
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.letterSpacing: 2
      }
    }

    // Scanlines — capped count, spacing derived from height.
    Repeater {
      model: root.scanlineCount
      delegate: Rectangle {
        required property int index
        width: stage.width
        height: 1
        y: Math.floor(index * stage.height / Math.max(1, root.scanlineCount))
        color: Qt.rgba(0, 0, 0, index % 2 === 0 ? 0.08 : 0.03)
      }
    }

    // Vignette
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.45) }
        GradientStop { position: 0.18; color: Qt.rgba(0, 0, 0, 0.0) }
        GradientStop { position: 0.82; color: Qt.rgba(0, 0, 0, 0.0) }
        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.requestWake(true); root.forcePasswordFocus() }
      onPositionChanged: root.requestWake(false)
    }

    Column {
      anchors.centerIn: parent
      spacing: 18
      width: root.fieldWidth

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.lv426 ? [
          "╔════════════════════════════════════════════╗",
          "║   MU-TH-UR 6000  //  SPECIAL ORDER 937     ║",
          "║   SCIENCE OFFICER EYES ONLY                ║",
          "╚════════════════════════════════════════════╝"
        ].join("\n") : [
          "╔══════════════════════════════════════════╗",
          "║  SESSION LOCKED // AUTHENTICATION REQUIRED ║",
          "╚══════════════════════════════════════════╝"
        ].join("\n")
        color: hackGreenBright
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        lineHeight: 1.15
        lineHeightMode: Text.ProportionalHeight
        opacity: 0.92
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 18

        Text {
          textFormat: Text.PlainText
          text: (root.lv426 ? "VESSEL :: " : "HOST :: ") + root.hostName
          color: hackCyan
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          id: clockText
          textFormat: Text.PlainText
          color: hackGold
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          Timer {
            interval: 1000
            repeat: true
            running: true
            triggeredOnStart: true
            onTriggered: {
              clockText.text = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm:ss")
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: fingerprintConfigured ? "BIO :: armed" : "BIO :: offline"
          color: fingerprintConfigured ? hackGreenBright : hackGreenDim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignLeft
        textFormat: Text.PlainText
        text: root.lv426
          ? "INTERFACE 2037 READY FOR INQUIRY"
          : root.userName + "@" + root.hostName + ":~$ omarchy-system-unlock"
        color: hackGreen
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        opacity: 0.85
      }

      BorderSurface {
        id: inputField
        width: root.fieldWidth
        height: root.fieldHeight
        color: Qt.rgba(0.04, 0.08, 0.07, 0.88)
        borderSpec: root.inputBorderSpec
        radius: 0
        clip: true

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 4
          color: errorState ? hackRed : hackGreenBright
        }

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: inputField.borderLeft + 14
          anchors.verticalCenter: parent.verticalCenter
          text: ">"
          color: hackGold
          font.family: Style.font.family
          font.pixelSize: root.fieldFontSize
        }

        TextInput {
          id: passwordInput
          anchors.fill: parent
          anchors.topMargin: inputField.borderTop
          anchors.rightMargin: inputField.borderRight + 14 + root.fingerprintReserve
          anchors.bottomMargin: inputField.borderBottom
          anchors.leftMargin: inputField.borderLeft + 34 + root.fingerprintReserve
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignLeft
          activeFocusOnPress: true
          clip: true
          maximumLength: root.maxPasswordLength
          enabled: root.inputEnabled && !root.authenticatingPassword
          readOnly: root.authenticatingPassword
          echoMode: TextInput.Password
          passwordCharacter: "\u25CF"
          passwordMaskDelay: 0
          color: hackGreenBright
          selectionColor: Qt.rgba(0.53, 0.67, 0.47, 0.45)
          selectedTextColor: hackBg
          font.family: Style.font.family
          font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
          font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
          cursorVisible: activeFocus && root.showPasswordCursor
          cursorDelegate: Rectangle {
            width: 8
            height: 14
            color: hackGreenBright
            visible: passwordInput.cursorVisible
            Timer {
              interval: 530
              repeat: true
              running: passwordInput.cursorVisible
              onTriggered: parent.visible = !parent.visible
            }
          }

          onTextChanged: {
            if (!root.syncingPasswordText) root.passwordTextEdited(root.boundPassword(text))
            if (text.length > 0) root.requestWake(false)
            if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
          }

          onAccepted: {
            var submitted = root.boundPassword(root.passwordText)
            root.passwordTextEdited("")
            if (submitted.length > 0) root.submitPassword(submitted)
          }

          Keys.onPressed: function(event) {
            root.requestWake(false)
            if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
              root.passwordTextEdited("")
              event.accepted = true
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.fill: passwordInput
          text: root.authenticatingPassword
            ? (root.lv426 ? "CROSS-REFERENCING CREW MANIFEST…" : "verifying credentials…")
            : (root.failureMessage.length > 0
              ? root.failureMessage
              : root.placeholderText)
          visible: passwordInput.text.length === 0
          color: root.authenticatingPassword ? hackCyan
               : (root.failureMessage.length > 0 ? hackRed : Qt.rgba(0.53, 0.67, 0.47, 0.75))
          font.family: Style.font.family
          font.pixelSize: root.fieldFontSize
          font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
          horizontalAlignment: Text.AlignLeft
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }

        Text {
          id: fingerprintIcon
          objectName: "fingerprintIndicator"
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: inputField.borderRight + 14
          anchors.verticalCenter: parent.verticalCenter
          visible: root.fingerprintConfigured
          text: "󰈷"
          color: hackCyan
          font.family: Style.font.family
          font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.lv426
          ? (errorState
            ? "ACCESS DENIED // ATTEMPT " + failedAttempts + " // CREW EXPENDABLE"
            : "WEYLAND-YUTANI CORP // BUILDING BETTER WORLDS // ESC CLEARS")
          : (errorState
            ? "intrusion countermeasure active // attempt " + failedAttempts
            : "enter passphrase // touch sensor // ESC clears")
        color: errorState ? hackRed : hackGreenDim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        opacity: 0.8
      }
    }

    Rectangle {
      id: crtFlicker
      anchors.fill: parent
      color: hackGreen
      opacity: 0
      SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: !root.cosmos
        NumberAnimation { from: 0; to: 0.012; duration: 90 }
        NumberAnimation { from: 0.012; to: 0; duration: 140 }
        PauseAnimation { duration: 2600 }
      }
    }
  }

  CosmosView {
    id: cosmosView
    anchors.fill: parent
    visible: root.cosmos
    running: root.cosmos && (root.loadBackground || root.inputEnabled)
    view: root
    inputEnabled: root.inputEnabled
    authenticatingPassword: root.authenticatingPassword
    fingerprintConfigured: root.fingerprintConfigured
    failureMessage: root.failureMessage
    failedAttempts: root.failedAttempts
    hostName: root.hostName

    MouseArea {
      anchors.fill: parent
      z: -1
      hoverEnabled: true
      onClicked: { root.requestWake(true); root.forcePasswordFocus() }
      onPositionChanged: root.requestWake(false)
    }
  }

  onCosmosChanged: if (inputEnabled) Qt.callLater(forcePasswordFocus)

  Timer {
    id: bootLogTimer
    interval: 850
    repeat: true
    property int lineIndex: 0
    onTriggered: {
      var lines = root.lv426 ? [
        "[init] MU-TH-UR 6000 interface online",
        "[ok]   USCSS Nostromo :: reg 180924609",
        "[ok]   crew manifest loaded: 7",
        "[warn] unidentified signal :: LV-426",
        "[----] signal analysis :: in progress",
        "[ok]   vessel resolved: " + root.hostName,
        "[ok]   crew member mapped: " + root.userName,
        "[warn] hypersleep cycle interrupted",
        "[----] awaiting crew access code",
        "[scan] bio-sensor " + (fingerprintConfigured ? "ready" : "absent"),
        "[ping] motion tracker 0x" + Math.floor(Math.random() * 65535).toString(16),
        "[----] special order 937 in effect"
      ] : [
        "[init] ext-session-lock client online",
        "[ok]   pam: omarchy-lock-password",
        "[ok]   secure surface acquired",
        "[warn] idle threshold exceeded",
        "[----] scrubbing framebuffer cache",
        "[ok]   hostname resolved: " + root.hostName,
        "[ok]   operator uid mapped: " + root.userName,
        "[warn] unauthorized access attempt blocked",
        "[----] awaiting credentials on tty-lock",
        "[scan] fingerprint daemon " + (fingerprintConfigured ? "ready" : "absent"),
        "[ping] watchdog heartbeat 0x" + Math.floor(Math.random() * 65535).toString(16),
        "[----] press enter to submit passphrase"
      ]
      bootLogModel.append({ line: lines[lineIndex % lines.length] })
      lineIndex += 1
      if (bootLogModel.count > 18) bootLogModel.remove(0)
    }
  }

  onFailureMessageChanged: {
    if (failureMessage.length > 0) {
      var hex = failedAttempts.toString(16)
      if (hex.length < 2) hex = "0" + hex
      bootLogModel.append({ line: "[ERR ] auth failure :: code 0x" + hex })
    }
  }
}
