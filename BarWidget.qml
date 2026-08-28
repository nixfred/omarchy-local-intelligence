import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.nixfred.local-intelligence"

  property bool online: false
  property bool active: false
  property real load: 0
  property int modelCount: 0
  property string model: ""
  property string backend: "none"
  property string errorText: ""
  property bool pendingPanelOpen: false
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property int refreshMs: Math.max(500, Number(root.setting("refreshIntervalMs", 1500)))
  readonly property real threshold: Math.max(1, Number(root.setting("activeThreshold", 8)))
  readonly property color ringColor: !online ? "#ff4664" : active ? "#00aaff" : "#35f28b"

  implicitWidth: vertical ? barSize : Style.bar.iconSlot
  implicitHeight: vertical ? Style.bar.iconSlot : barSize

  function plainText(value, limit) {
    return String(value || "").slice(0, limit).replace(/[<>&]/g, function(character) {
      return character === "<" ? "‹" : character === ">" ? "›" : "＆"
    }).replace(/[\u0000-\u001f\u007f]/g, " ")
  }

  function refresh() {
    if (!probe.running) probe.running = true
  }

  function applyStatus(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      online = data.online === true
      load = Math.max(0, Math.min(100, Number(data.load || 0)))
      active = online && (data.active === true || load >= threshold)
      modelCount = Number(data.modelCount || 0)
      model = plainText(data.model, 256)
      backend = plainText(data.backend || "none", 32)
      errorText = plainText(data.error, 384)
    } catch (e) {
      online = false
      active = false
      load = 0
      modelCount = 0
      model = ""
      backend = "none"
      errorText = "Invalid monitor response"
    }
    if (panelLoader.item) panelLoader.item.applyStatus({
      online: online, active: active, load: load, modelCount: modelCount,
      model: model, backend: backend, error: errorText
    })
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.settings = root.settings
  }

  function openPanel() {
    if (panelLoader.item) {
      pendingPanelOpen = false
      panelLoader.item.open()
    } else {
      pendingPanelOpen = true
      panelLoader.active = true
    }
  }
  function toggle() {
    if (!panelLoader.item) { openPanel(); return }
    if (panelLoader.item.opened) panelLoader.item.close()
    else openPanel()
  }
  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
      if (root.pendingPanelOpen) Qt.callLater(root.openPanel)
    }
  }

  Process {
    id: probe
    command: [root.pluginDir + "/scripts/llm-status", "--threshold", String(root.threshold)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.applyStatus("")
    }
  }

  Timer {
    interval: root.refreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.moduleName
    function refresh(): void { root.refresh() }
    function open(): void { root.openPanel() }
    function close(): void { if (panelLoader.item) panelLoader.item.close() }
    function toggle(): void { root.toggle() }
    function status(): string {
      return JSON.stringify({online: root.online, active: root.active, load: root.load,
        model: root.model, modelCount: root.modelCount, backend: root.backend})
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: !root.online
      ? "Ollama offline" + (root.errorText !== "" ? " · " + root.errorText : "")
      : root.active
        ? "Deep inference · " + Math.round(root.load) + "% · " + (root.model || "local model")
        : "Local AI idle" + (root.modelCount > 0 ? " · " + root.modelCount + " model(s) loaded" : "")
    onPressed: function(code) {
      if (code === Qt.RightButton) root.refresh()
      else if (code === Qt.LeftButton) root.toggle()
    }

    iconComponent: Component {
      Item {
        id: icon
        anchors.fill: parent

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height) * 0.82
          height: width
          radius: width / 2
          color: root.ringColor
          opacity: root.active ? 0.80 : 0.28
          scale: root.active ? 1 : 0.88
          Behavior on color { ColorAnimation { duration: 180 } }
          Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height) * 0.64
          height: width
          radius: width / 2
          color: root.ringColor
          Behavior on color { ColorAnimation { duration: 180 } }

          SequentialAnimation on scale {
            running: root.active
            loops: Animation.Infinite
            NumberAnimation { to: 1.13; duration: 520; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.96; duration: 520; easing.type: Easing.InOutSine }
          }
        }

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height) * 0.36
          height: width
          radius: width / 2
          color: root.bar ? root.bar.background : Color.background
          border.width: 1
          border.color: Qt.rgba(root.ringColor.r, root.ringColor.g, root.ringColor.b, 0.35)
          Behavior on border.color { ColorAnimation { duration: 180 } }
        }
      }
    }
  }
}
