import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.seyhunakyurek.omteleprompt"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string moduleId: moduleName
  property bool isPlaying: false
  property bool voiceEnabled: setting("voiceEnabled", false) === true
  property bool voiceDetected: false
  property int currentWordIndex: 0
  readonly property real scrollSpeed: Number(setting("scrollSpeed", 1))
  readonly property int fontSize: Math.max(12, Math.min(120, Number(setting("fontSize", 36))))
  readonly property int vadThreshold: Math.max(100, Math.min(3000, Number(setting("vadThreshold", 500))))
  property var words: []
  property int totalWords: 0
  property bool editMode: false
  // OMTELEPROMPT-UNBOUNDED-VAD-RESTART fix: bounded retry with backoff
  property int vadFailureCount: 0
  property int vadMaxRetries: 5
  property int vadBaseRetryDelayMs: 1000
  property bool vadPermanentFailure: false
  property bool vadManualStop: false

  property var settingsWriteQueue: []
  property bool settingsWriteRunning: false

  Process {
    id: settingsWriteProcess
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0)
        console.warn("omteleprompt/settings", "omarchy bar set failed:", settingsWriteProcess.command.join(" "))
      root.settingsWriteRunning = false
      root.pumpSettingsWriteQueue()
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  function writeSetting(key, jsonValue) {
    if (root.moduleId === "") return
    root.settingsWriteQueue.push({ key: key, jsonValue: jsonValue })
    root.pumpSettingsWriteQueue()
  }

  function pumpSettingsWriteQueue() {
    if (root.settingsWriteRunning) return
    if (root.settingsWriteQueue.length === 0) return
    var next = root.settingsWriteQueue.shift()
    root.settingsWriteRunning = true
    settingsWriteProcess.command = ["omarchy", "bar", "set", root.moduleId, next.key, next.jsonValue, "--json"]
    settingsWriteProcess.running = true
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide(); root.stopPlayback() }
  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function startPlayback() {
    if (root.words.length === 0) return
    if (root.currentWordIndex >= root.words.length) root.currentWordIndex = 0
    root.isPlaying = true
    playTimer.start()
  }

  function stopPlayback() {
    root.isPlaying = false
    playTimer.stop()
  }

  function togglePlayback() {
    if (root.isPlaying) root.stopPlayback()
    else root.startPlayback()
  }

  function resetPlayback() {
    root.stopPlayback()
    root.currentWordIndex = 0
    teleprompterView.contentY = 0
    updateWordHighlight()
  }

  function updateWordHighlight() {
    for (let i = 0; i < wordRepeater.count; i++) {
      if (wordRepeater.itemAt(i)) wordRepeater.itemAt(i).active = (i === root.currentWordIndex)
    }
    if (root.currentWordIndex >= 0 && root.currentWordIndex < wordRepeater.count && wordRepeater.itemAt(root.currentWordIndex)) {
      ensureWordVisible(wordRepeater.itemAt(root.currentWordIndex))
    }
    wordCounter.text = (root.currentWordIndex + 1) + " / " + root.totalWords
  }

  function ensureWordVisible(item) {
    const itemTop = wordColumn.y + item.y
    const itemBottom = itemTop + item.height
    const viewTop = teleprompterView.contentY + Style.space(10)
    const viewBottom = viewTop + teleprompterView.height - Style.space(20)
    if (itemTop < viewTop) {
      teleprompterView.contentY = Math.max(0, itemTop - Style.space(10))
    } else if (itemBottom > viewBottom) {
      const maxY = Math.max(0, teleprompterView.contentHeight - teleprompterView.height)
      teleprompterView.contentY = Math.min(maxY, itemBottom - teleprompterView.height + Style.space(20))
    }
  }

  function splitIntoWords(text) {
    const raw = String(text).replace(/\s+/g, " ").trim()
    if (raw.length === 0) return []
    return raw.split(" ")
  }

  function rebuildWords() {
    root.stopPlayback()
    root.words = splitIntoWords(scriptEditor.text)
    root.totalWords = root.words.length
    root.currentWordIndex = 0
    wordRepeater.model = root.words
    wordCounter.text = "0 / " + root.totalWords
    Qt.callLater(function() {
      teleprompterView.contentY = 0
    })
  }

  Timer {
    id: playTimer
    interval: 200
    repeat: true
    running: root.isPlaying
    onTriggered: {
      if (!root.isPlaying) return
      if (root.voiceEnabled && root.voiceDetected) return
      if (root.currentWordIndex < root.totalWords - 1) {
        root.currentWordIndex++
        root.updateWordHighlight()
      } else {
        root.stopPlayback()
      }
    }
  }

  Timer {
    id: vadTimer
    interval: 1000
    running: root.voiceEnabled && !root.vadPermanentFailure && !vadRetryTimer.running
    repeat: true
    onTriggered: {
      if (!root.voiceEnabled || root.vadPermanentFailure || vadRetryTimer.running || vadProcess.running)
        return
      if (root.vadFailureCount >= root.vadMaxRetries) {
        root.vadPermanentFailure = true
        console.warn("omteleprompt/vad", "max retries reached, not restarting VAD")
        voiceIndicator.color = "#ff8800"
        voiceStatus.text = "Voice Error"
        return
      }
      if (!vadProcess.running && root.vadFailureCount === 0) {
        vadProcess.command = ["python3", Qt.resolvedUrl("bin/vad.py").toString(), "--threshold", String(root.vadThreshold)]
        vadProcess.running = true
        vadStableTimer.restart()
      }
    }
  }

  Timer {
    id: vadRetryTimer
    interval: 1000
    repeat: false
    onTriggered: {
      if (!root.voiceEnabled || root.vadPermanentFailure || root.vadManualStop) return
      if (root.vadFailureCount >= root.vadMaxRetries) {
        root.vadPermanentFailure = true
        console.warn("omteleprompt/vad", "max retries reached, disabling voice auto-restart. Check audio backend (python-pyaudio / sounddevice / alsa-utils).")
        voiceIndicator.color = "#ff8800"
        voiceStatus.text = "Voice Error"
        root.voiceDetected = false
        return
      }
      vadProcess.command = ["python3", Qt.resolvedUrl("bin/vad.py").toString(), "--threshold", String(root.vadThreshold)]
      vadProcess.running = true
      vadStableTimer.restart()
    }
  }

  Timer {
    id: vadStableTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (vadProcess.running) {
        root.vadFailureCount = 0
        root.vadPermanentFailure = false
      }
    }
  }

  Process {
    id: vadProcess
    command: []
    running: false
    stdout: StdioCollector {
      waitForEnd: false
      onStreamFinished: {
        const trimmed = String(text || "").trim()
        if (trimmed === "VOICE_START") {
          root.voiceDetected = true
          voiceIndicator.color = "#ff4444"
          voiceStatus.text = "Speaking..."
        } else if (trimmed === "VOICE_END") {
          root.voiceDetected = false
          voiceIndicator.color = "#44ff44"
          voiceStatus.text = "Listening"
        } else if (trimmed.startsWith("LEVEL:")) {
          const parts = trimmed.split(":")
          if (parts.length > 1 && typeof voiceLevel !== "undefined" && voiceLevel) voiceLevel.value = parseFloat(parts[1])
        }
      }
    }
    stderr: StdioCollector { waitForEnd: false }
    onExited: function(code) {
      vadStableTimer.stop()
      if (root.vadManualStop) {
        root.vadManualStop = false
        return
      }
      if (!root.voiceEnabled) return
      if (root.vadPermanentFailure) return
      if (vadProcess.command.length === 0) return
      root.vadFailureCount++
      if (root.vadFailureCount >= root.vadMaxRetries) {
        root.vadPermanentFailure = true
        console.warn("omteleprompt/vad", "VAD failed", root.vadFailureCount, "times (code", code, "), giving up until voice toggled. Install python-pyaudio or sounddevice.")
        voiceIndicator.color = "#ff8800"
        voiceStatus.text = "Voice Error"
        root.voiceDetected = false
        return
      }
      const backoff = Math.min(30000, root.vadBaseRetryDelayMs * Math.pow(2, root.vadFailureCount - 1))
      console.warn("omteleprompt/vad", "VAD exited code", code, "retry", root.vadFailureCount + "/" + root.vadMaxRetries, "in", backoff, "ms")
      vadRetryTimer.interval = backoff
      vadRetryTimer.start()
    }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Seconds
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ColumnLayout {
        id: content
        width: parent.width
        spacing: Style.space(8)
        // padding removed: ColumnLayout does not have padding

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          height: Style.space(36)

          Text {
            text: "OmTeleprompt"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            verticalAlignment: Text.AlignVCenter
          }

          Item { width: Style.space(8); height: 1 }

          Rectangle {
            id: voiceIndicator
            width: Style.space(12)
            height: Style.space(12)
            radius: width / 2
            color: root.voiceEnabled ? (root.voiceDetected ? "#ff4444" : "#44ff44") : "#666666"
            Layout.alignment: Qt.AlignVCenter
          }

          Text {
            id: voiceStatus
            text: root.voiceEnabled ? (root.voiceDetected ? "Speaking..." : "Listening") : "Voice Off"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            verticalAlignment: Text.AlignVCenter
          }

          Item { width: Style.space(4); height: 1 }

          Text {
            id: wordCounter
            text: "0 / 0"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            verticalAlignment: Text.AlignVCenter
          }

          Item { width: 1; height: 1; Layout.fillWidth: true }

          Text {
            text: Qt.formatTime(clock.date, "HH:mm:ss")
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            verticalAlignment: Text.AlignVCenter
          }
        }

        PanelSeparator { Layout.fillWidth: true }

        // Controls
        GridLayout {
          Layout.fillWidth: true
          columns: 2
          rowSpacing: Style.space(4)
          columnSpacing: Style.space(6)

          Button {
            text: root.isPlaying ? "⏸ Pause" : "▶ Play"
            onClicked: root.togglePlayback()
            enabled: root.totalWords > 0
            Layout.fillWidth: true
          }

          Button {
            text: "⏹ Stop"
            onClicked: root.resetPlayback()
            enabled: root.totalWords > 0
            Layout.fillWidth: true
          }

          Button {
            text: root.editMode ? "📖 Read" : "✏️ Edit"
            onClicked: {
              root.editMode = !root.editMode
              scriptEditor.visible = root.editMode
              teleprompterView.visible = !root.editMode
              notesSection.visible = !root.editMode
              if (!root.editMode) root.rebuildWords()
            }
            Layout.fillWidth: true
          }

          Button {
            text: root.voiceEnabled ? "🎤 Voice On" : "🎤 Voice Off"
            onClicked: {
              const newValue = !root.voiceEnabled
              root.voiceEnabled = newValue
              if (!newValue) {
                root.voiceDetected = false
                root.vadManualStop = true
                root.vadFailureCount = 0
                root.vadPermanentFailure = false
                vadRetryTimer.stop()
                vadStableTimer.stop()
                vadProcess.running = false
                voiceIndicator.color = "#666666"
                voiceStatus.text = "Voice Off"
              } else {
                root.vadManualStop = false
                root.vadFailureCount = 0
                root.vadPermanentFailure = false
                voiceIndicator.color = "#44ff44"
                voiceStatus.text = "Listening"
                vadProcess.command = ["python3", Qt.resolvedUrl("bin/vad.py").toString(), "--threshold", String(root.vadThreshold)]
                vadProcess.running = true
                vadStableTimer.restart()
              }
              root.writeSetting("voiceEnabled", String(newValue))
            }
            Layout.fillWidth: true
          }

          Item { width: 1; height: Style.space(24); Layout.columnSpan: 2 }

          Text {
            text: "Speed:"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            verticalAlignment: Text.AlignVCenter
          }

          Slider {
            id: speedSlider
            from: 0.5
            to: 5.0
            stepSize: 0.1
            value: root.scrollSpeed
            onValueChanged: {
              playTimer.interval = Math.max(50, 200 / value)
              root.writeSetting("scrollSpeed", String(value))
            }
            Layout.fillWidth: true
          }

          Text {
            text: root.scrollSpeed.toFixed(1) + "x"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            verticalAlignment: Text.AlignVCenter
          }
        }

        PanelSeparator { Layout.fillWidth: true }

        // Script Editor
        TextEdit {
          id: scriptEditor
          Layout.fillWidth: true
          height: Style.space(140)
          visible: root.editMode
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: TextEdit.WordWrap
          text: "Welcome to OmTeleprompt!\n\nThis is a teleprompter designed for interviewers and streamers.\n\nFeatures:\n- Word tracking with auto-scroll\n- Voice activation that pauses when you speak\n- Notes panel to write during speaking\n- Adjustable scroll speed\n\nClick Edit to paste your script, then switch to Read Mode."
          onTextChanged: root.rebuildWords()
        }

        // Teleprompter View
        Flickable {
          id: teleprompterView
          Layout.fillWidth: true
          height: Style.space(380)
          visible: !root.editMode
          clip: true
          contentWidth: width
          contentHeight: wordColumn.height
          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
          }

          Column {
            id: wordColumn
            width: parent.width
            spacing: Style.space(6)
            padding: Style.space(10)
            topPadding: Math.max(Style.space(10), teleprompterView.height / 2 - Style.space(20))

            Repeater {
              id: wordRepeater
              model: root.words

              Text {
                width: parent.width
                text: modelData
                color: active ? Color.accent : root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: active ? root.fontSize + 4 : root.fontSize
                font.bold: active
                wrapMode: Text.WordWrap
                property bool active: false
              }
            }
          }
        }

        // Notes Section
        ColumnLayout {
          id: notesSection
          Layout.fillWidth: true
          spacing: Style.space(6)
          visible: !root.editMode

          Text {
            text: "Notes (write during speaking):"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          TextEdit {
            id: notesArea
            Layout.fillWidth: true
            height: Style.space(80)
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: TextEdit.WordWrap
          }

          Button {
            text: "🗑 Clear Notes"
            onClicked: notesArea.text = ""
          }
        }
      }
    }
  }
}
