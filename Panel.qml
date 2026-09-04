import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.nixfred.local-intelligence"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property color stateColor: !online ? "#ff4664" : active ? "#00aaff" : "#35f28b"

  property bool online: false
  property bool active: false
  property real load: 0
  property int modelCount: 0
  property string loadedModel: ""
  property string backend: "none"
  property var modelOptions: []
  property string selectedModel: ""
  property bool busy: false
  property string actionNote: ""
  property string errorText: ""
  readonly property int refreshMs: Math.max(500, Number(root.setting("refreshIntervalMs", 1500)))
  readonly property real threshold: Math.max(1, Number(root.setting("activeThreshold", 8)))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function plainText(value, limit) {
    return String(value || "").slice(0, limit).replace(/[<>&]/g, function(character) {
      return character === "<" ? "‹" : character === ">" ? "›" : "＆"
    }).replace(/[\u0000-\u001f\u007f]/g, " ")
  }

  function applyStatus(value) {
    var data = value
    if (typeof value === "string") {
      try { data = JSON.parse(value) }
      catch (e) { data = {online: false, error: "Invalid monitor response"} }
    }
    online = data.online === true
    load = Number(data.load || 0)
    active = online && (data.active === true || load >= threshold)
    modelCount = Number(data.modelCount || 0)
    loadedModel = plainText(data.model, 256)
    backend = plainText(data.backend || "none", 32)
    errorText = plainText(data.error, 384)
  }

  function open() {
    controller.show()
    refreshModels()
    refresh()
  }
  function toggle() { opened ? close() : open() }
  function refresh() {
    if (root.hostWidget) { root.hostWidget.refresh(); return }
    if (!statusProc.running) statusProc.running = true
  }
  function refreshModels() {
    if (!listProc.running) listProc.running = true
  }
  function runAction(action) {
    if (busy || selectedModel === "") return
    busy = true
    actionNote = (action === "load" ? "Warming " : "Unloading ") + selectedModel + "…"
    actionProc.command = [pluginDir + "/scripts/ollama-control", action, selectedModel]
    actionProc.running = true
  }
  function parseModels(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      var options = []
      if (!Array.isArray(data.models)) throw new Error("Invalid model list")
      for (var i = 0; i < Math.min(data.models.length, 128); i++) {
        var m = data.models[i]
        var rawName = String(m.name || "").slice(0, 256)
        if (rawName === "") continue
        options.push({value: rawName,
          label: plainText(rawName, 256) + (m.loaded ? "  • loaded" : ""),
          description: [plainText(m.parameters, 64), plainText(m.quantization, 64)]
            .filter(Boolean).join(" · ")})
      }
      modelOptions = options
      if (selectedModel === "" && options.length > 0) selectedModel = options[0].value
    } catch (e) { actionNote = "Could not read installed models" }
  }

  Process {
    id: listProc
    command: [root.pluginDir + "/scripts/ollama-control", "list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseModels(text) }
  }
  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result = JSON.parse(String(text || ""))
          root.actionNote = root.plainText(result.ok ? result.message : result.error, 384)
        } catch (e) { root.actionNote = "Ollama action failed" }
      }
    }
    onExited: {
      root.busy = false
      refreshDelay.restart()
    }
  }
  Timer {
    id: refreshDelay
    interval: 500
    repeat: false
    onTriggered: {
      root.refreshModels()
      root.refresh()
    }
  }

  Process {
    id: statusProc
    command: [root.pluginDir + "/scripts/llm-status", "--threshold", String(root.threshold)]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
  }
  Timer {
    interval: root.refreshMs
    running: !root.hostWidget
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: !root.online
      ? "Ollama offline" + (root.errorText !== "" ? " · " + root.errorText : "")
      : root.active ? "Deep inference · " + Math.round(root.load) + "% · " + (root.loadedModel || "local model")
      : "Local AI idle — click for model control"
    onPressed: function(code) {
      if (code === Qt.RightButton) root.refresh()
      else if (code === Qt.LeftButton) root.toggle()
    }
    iconComponent: Component {
      Item {
        anchors.fill: parent
        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height) * 0.72
          height: width
          radius: width / 2
          color: root.stateColor
          opacity: root.active ? 0.30 : 0.16
        }
        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height) * 0.56
          height: width
          radius: width / 2
          color: root.stateColor
          SequentialAnimation on scale {
            running: root.active
            loops: Animation.Infinite
            NumberAnimation { to: 1.10; duration: 520; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.96; duration: 520; easing.type: Easing.InOutSine }
          }
        }
        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height) * 0.30
          height: width
          radius: width / 2
          color: root.bar ? root.bar.background : Color.background
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: modelPicker.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true

        ColumnLayout {
          id: content
          width: parent.width
          spacing: Style.space(14)

          PanelHero {
            Layout.fillWidth: true
            title: "Local Intelligence"
            meta: !root.online ? "Ollama offline" : root.active ? "Deep inference" : "Ready & idle"
            detail: root.loadedModel !== "" ? root.loadedModel : "No model resident in memory"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Item {
                implicitWidth: Style.space(46)
                implicitHeight: Style.space(46)
                Rectangle {
                  anchors.centerIn: parent
                  width: Style.space(34)
                  height: width
                  radius: width / 2
                  color: root.stateColor
                  opacity: root.active ? 0.22 : 0.12
                }
                Rectangle {
                  anchors.centerIn: parent
                  width: Style.space(28)
                  height: width
                  radius: width / 2
                  color: root.stateColor
                }
                Rectangle {
                  anchors.centerIn: parent
                  width: Style.space(16)
                  height: width
                  radius: width / 2
                  color: root.bar ? root.bar.background : Color.background
                }
              }
            }
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

          RowLayout {
            Layout.fillWidth: true
            Text { text: "RESOURCE LOAD"; textFormat: Text.PlainText; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
            Item { Layout.fillWidth: true }
            Text { text: Math.round(root.load) + "%  " + root.backend.toUpperCase(); textFormat: Text.PlainText; color: root.stateColor; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
          }
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(12)
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
            Rectangle {
              width: parent.width * Math.max(0.025, Math.min(1, root.load / 100))
              height: parent.height
              radius: height / 2
              color: root.stateColor
              Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.active ? "Tokens are flowing. The ring pulses while the local runner is working."
              : "Standing by. Pick a model below to keep it warm in memory."
            textFormat: Text.PlainText
            color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }
          PanelSectionHeader { Layout.fillWidth: true; text: "MODEL CONTROL"; foreground: root.foreground; fontFamily: root.fontFamily }

          SearchableDropdown {
            id: modelPicker
            Layout.fillWidth: true
            label: "Installed Ollama model"
            placeholderText: "Choose a model…"
            fontFamily: root.fontFamily
            options: root.modelOptions
            value: root.selectedModel
            onChanged: function(value) { root.selectedModel = value }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Button {
              text: root.busy ? "Working…" : "Load & keep warm"
              enabled: !root.busy && root.online && root.selectedModel !== ""
              onClicked: root.runAction("load")
            }
            Button {
              text: "Unload"
              enabled: !root.busy && root.online && root.selectedModel !== ""
              onClicked: root.runAction("unload")
            }
            Item { Layout.fillWidth: true }
            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: { root.refreshModels(); root.refresh() }
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.actionNote !== ""
            text: root.actionNote
            textFormat: Text.PlainText
            color: root.stateColor; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
