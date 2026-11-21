import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.mahmudurah.sigenergy"
  ipcTarget: "io.github.mahmudurah.sigenergy"

  readonly property string host: String(setting("host", "") || "").trim()
  readonly property bool needsSetup: host.length === 0
  readonly property int port: {
    var p = parseInt(setting("port", 502), 10)
    return (isFinite(p) && p > 0 && p <= 65535) ? p : 502
  }
  readonly property int refreshSeconds: Math.max(5, parseInt(setting("refreshSeconds", 15), 10) || 15)
  readonly property string barMode: String(setting("barMode", "full") || "full")
  readonly property real openPanelIndicatorWidth: !button.vertical ? button.labelWidth : 0

  readonly property string scriptPath: {
    var url = String(Qt.resolvedUrl("scripts/poll.py"))
    return url.indexOf("file://") === 0 ? url.slice(7) : url
  }

  property var telemetry: null
  property bool offline: false
  property string lastError: ""
  property int consecutiveFailures: 0
  property string lastUpdatedText: ""
  property bool refreshing: false

  readonly property bool hasData: !needsSetup && telemetry !== null && telemetry.ok === true
  readonly property real socPct: hasData ? Math.max(0, Math.min(100, Number(telemetry.socPct) || 0)) : 0
  readonly property real socFraction: socPct / 100.0
  readonly property int pvPowerW: hasData ? (Number(telemetry.pvPowerW) || 0) : 0
  readonly property int homeLoadW: hasData ? (Number(telemetry.homeLoadW) || 0) : 0
  readonly property int gridPowerW: hasData ? (Number(telemetry.gridPowerW) || 0) : 0
  readonly property int essPowerW: hasData ? (Number(telemetry.essPowerW) || 0) : 0
  readonly property bool batteryCharging: hasData && essPowerW > 30
  readonly property bool batteryDischarging: hasData && essPowerW < -30
  readonly property bool solarGenerating: hasData && pvPowerW >= 30
  readonly property bool lowBattery: hasData && socPct <= 15

  readonly property color fgColor: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color accentColor: Commons.Color.accent
  readonly property color urgentColor: Commons.Color.urgent
  readonly property color mutedColor: Qt.darker(fgColor, 1.4)

  readonly property color batteryBarColor: {
    if (needsSetup || (offline && !hasData)) return mutedColor
    if (lowBattery) return urgentColor
    if (batteryCharging) return accentColor
    return fgColor
  }

  function formatPower(watts, signed) {
    var w = Number(watts)
    if (!isFinite(w)) return "—"
    var absW = Math.abs(w)
    var prefix = ""
    if (signed) {
      if (w > 20) prefix = "+"
      else if (w < -20) prefix = "-"
    }
    if (absW >= 1000) {
      return prefix + Commons.I18n.formatNumber(absW / 1000.0, 2) + " kW"
    }
    return prefix + Commons.I18n.formatNumber(Math.round(absW), 0) + " W"
  }

  function formatPowerCompact(watts) {
    var w = Math.abs(Number(watts) || 0)
    if (w >= 1000) return Commons.I18n.formatNumber(w / 1000.0, 1) + "kW"
    return Commons.I18n.formatNumber(Math.round(w), 0) + "W"
  }

  function formatKwh(val) {
    if (val === undefined || val === null || !isFinite(Number(val))) return "—"
    return Commons.I18n.formatNumber(Number(val), 2) + " kWh"
  }

  function homeBatteryGlyph() {
    if (needsSetup || (offline && !hasData)) return "󱤂"
    if (batteryCharging) return "󱤃"
    return "󱤁"
  }

  function barText() {
    var battIcon = homeBatteryGlyph()
    if (button.vertical || barMode === "icon") return battIcon
    if (needsSetup) return battIcon + " Setup"
    if (!hasData) return battIcon + (offline ? " off" : " …")
    var socStr = Commons.I18n.formatNumber(Math.round(socPct), 0) + "%"
    if (barMode === "soc") return battIcon + " " + socStr
    var parts = []
    if (pvPowerW > 0) parts.push("󰖙 " + formatPowerCompact(pvPowerW))
    parts.push("󰋜 " + formatPowerCompact(homeLoadW))
    parts.push(battIcon + " " + socStr)
    return parts.join("  ")
  }

  function heroStatusLine() {
    if (needsSetup) return "CONFIGURE HOST IP"
    if (offline && !hasData) return "OFFLINE · " + host
    if (!hasData) return "CONNECTING…"
    var stateStr = "IDLE"
    if (batteryCharging) stateStr = "CHARGING · " + formatPower(essPowerW, false)
    else if (batteryDischarging) stateStr = "DISCHARGING · " + formatPower(essPowerW, false)
    var ems = telemetry.emsMode ? String(telemetry.emsMode) : ""
    var suffix = ems ? (" · " + ems.toUpperCase()) : ""
    if (offline) suffix += " · STALE"
    return stateStr + suffix
  }

  function gridSubLabel() {
    if (!hasData) return "—"
    if (gridPowerW > 20) return "Importing"
    if (gridPowerW < -20) return "Exporting"
    return "Balanced"
  }

  function cycleBarMode() {
    var next = barMode === "full" ? "soc" : (barMode === "soc" ? "icon" : "full")
    root.settings = Object.assign({}, root.settings, { barMode: next })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function refresh() {
    if (needsSetup || pollProc.running) return
    if (!/^[A-Za-z0-9._:-]+$/.test(host)) {
      offline = true
      lastError = "Invalid host"
      return
    }
    refreshing = true
    pollProc.command = ["python3", scriptPath, host, String(port)]
    pollProc.running = true
  }

  function handlePollOutput(raw) {
    refreshing = false
    var text = String(raw || "").trim()
    if (!text) {
      consecutiveFailures++
      if (consecutiveFailures >= 2) offline = true
      lastError = "Empty response"
      return
    }
    try {
      var parsed = JSON.parse(text)
      if (parsed && parsed.ok === true) {
        telemetry = parsed
        offline = false
        lastError = ""
        consecutiveFailures = 0
        var now = new Date()
        var hh = String(now.getHours()).padStart(2, "0")
        var mm = String(now.getMinutes()).padStart(2, "0")
        var ss = String(now.getSeconds()).padStart(2, "0")
        lastUpdatedText = hh + ":" + mm + ":" + ss
      } else {
        consecutiveFailures++
        if (consecutiveFailures >= 2 || !hasData) offline = true
        lastError = parsed && parsed.error ? String(parsed.error).slice(0, 64) : "Read failed"
      }
    } catch (e) {
      consecutiveFailures++
      if (consecutiveFailures >= 2 || !hasData) offline = true
      lastError = "Parse error"
    }
  }

  onOpenedChanged: {
    if (opened) refresh()
  }

  onHostChanged: {
    telemetry = null
    offline = false
    lastError = ""
    consecutiveFailures = 0
    if (!needsSetup) refresh()
  }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: pollProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handlePollOutput(text)
    }
    onExited: function(code) {
      if (root.refreshing) {
        root.refreshing = false
        root.consecutiveFailures++
        if (root.consecutiveFailures >= 2 || !root.hasData) root.offline = true
      }
    }
  }

  Timer {
    id: pollTimer
    interval: (root.opened ? 5 : root.refreshSeconds) * 1000
    running: !root.needsSetup
    repeat: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText()
    fontSize: Style.bar.iconFont
    horizontalMargin: 7
    tooltipText: ""

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleBarMode()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(396))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_R) {
          root.refresh()
          event.accepted = true
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: Home Battery icon · SigenStor / Status · SoC % ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.homeBatteryGlyph()
            color: root.batteryBarColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "SigenStor"
              color: root.fgColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.heroStatusLine()
              color: root.offline ? root.urgentColor : root.mutedColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.8
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.hasData ? (Commons.I18n.formatNumber(root.socPct, 1) + "%") : "—"
            color: root.lowBattery ? root.urgentColor : root.fgColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
          }
        }

        // ---------- Setup notice when host is not configured ----------
        Rectangle {
          visible: root.needsSetup
          width: parent.width
          implicitHeight: setupCol.implicitHeight + Style.space(20)
          radius: Math.min(Style.cornerRadius, 8)
          color: Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.05)
          border.width: 1
          border.color: Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.12)

          Column {
            id: setupCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(12)
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              text: "Set your Sigenergy IP address in ~/.config/omarchy/shell.json:"
              color: root.fgColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: "{ \"id\": \"io.github.mahmudurah.sigenergy\", \"host\": \"192.168.1.50\" }"
              color: root.accentColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WrapAnywhere
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: "Ensure Modbus TCP (port 502) is enabled in the mySigen app."
              color: root.mutedColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              width: parent.width
            }
          }
        }

        // ---------- Battery Progress Bar ----------
        Item {
          visible: !root.needsSetup
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryBarColor
            width: root.hasData ? Math.max(barTrack.height, barTrack.width * root.socFraction) : 0

            Behavior on width { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Style.duration(200) } }

            SequentialAnimation on opacity {
              running: root.batteryCharging && root.opened && !Style.reduceMotion
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: Style.duration(950); easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: Style.duration(950); easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Live Power Flow: Solar · Home Load · Grid ----------
        Row {
          visible: !root.needsSetup
          id: liveRow
          width: parent.width
          spacing: Style.space(8)

          MetricTile {
            width: (parent.width - parent.spacing * 2) / 3
            glyph: "󰖙"
            title: "SOLAR"
            value: root.hasData ? root.formatPower(root.pvPowerW, false) : "—"
            subtitle: root.solarGenerating ? "Generating" : "Idle"
            highlight: root.solarGenerating
          }

          MetricTile {
            width: (parent.width - parent.spacing * 2) / 3
            glyph: "󰋜"
            title: "HOME"
            value: root.hasData ? root.formatPower(root.homeLoadW, false) : "—"
            subtitle: "Load"
            highlight: false
          }

          MetricTile {
            width: (parent.width - parent.spacing * 2) / 3
            glyph: "󰠠"
            title: "GRID"
            value: root.hasData ? root.formatPower(Math.abs(root.gridPowerW), false) : "—"
            subtitle: root.gridSubLabel()
            highlight: root.hasData && root.gridPowerW < -20
            warn: root.hasData && root.gridPowerW > 200
          }
        }

        PanelSeparator {
          visible: !root.needsSetup
          foreground: root.fgColor
        }

        // ---------- Today's Energy Breakdown ----------
        Column {
          visible: !root.needsSetup
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "TODAY"
            foreground: root.fgColor
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Row {
            width: parent.width
            spacing: Style.space(18)

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(8)

              StatPair {
                label: "Solar Generated"
                value: root.hasData ? root.formatKwh(root.telemetry.dailyPvKwh) : "—"
              }
              StatPair {
                label: "Battery Charged"
                value: root.hasData ? root.formatKwh(root.telemetry.dailyChargeKwh) : "—"
              }
              StatPair {
                label: "Net Grid"
                value: {
                  if (!root.hasData || root.telemetry.netExportKwh === null || root.telemetry.netExportKwh === undefined) return "—"
                  var v = Number(root.telemetry.netExportKwh)
                  var absStr = Commons.I18n.formatNumber(Math.abs(v), 2) + " kWh"
                  if (v > 0.05) return absStr + " exp"
                  if (v < -0.05) return absStr + " imp"
                  return "0.00 kWh"
                }
              }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(8)

              StatPair {
                label: "Home Load"
                value: root.hasData ? root.formatKwh(root.telemetry.dailyLoadKwh) : "—"
              }
              StatPair {
                label: "Battery Discharged"
                value: root.hasData ? root.formatKwh(root.telemetry.dailyDischargeKwh) : "—"
              }
              StatPair {
                label: "Battery Health"
                value: {
                  if (!root.hasData) return "—"
                  var soh = root.telemetry.sohPct !== null && root.telemetry.sohPct !== undefined
                    ? (Commons.I18n.formatNumber(Number(root.telemetry.sohPct), 0) + "%")
                    : "—"
                  var temp = root.telemetry.cellTempC !== null && root.telemetry.cellTempC !== undefined
                    ? (" · " + Commons.I18n.formatNumber(Number(root.telemetry.cellTempC), 1) + "°C")
                    : ""
                  return soh + temp
                }
              }
            }
          }
        }

        PanelSeparator {
          visible: !root.needsSetup
          foreground: root.fgColor
        }

        // ---------- Footer: Status + Refresh ----------
        Item {
          visible: !root.needsSetup
          width: parent.width
          implicitHeight: Math.max(footerLeft.implicitHeight, refreshBtn.implicitHeight)

          Text {
            id: footerLeft
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: refreshBtn.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            color: root.hasData && root.telemetry.hasAlarms ? root.urgentColor : root.mutedColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            text: {
              if (root.offline && !root.hasData) return root.lastError ? ("Error: " + root.lastError) : "Unreachable"
              var grid = root.hasData && root.telemetry.gridState ? root.telemetry.gridState : ""
              var alarm = root.hasData && root.telemetry.hasAlarms ? " · Alarm active" : ""
              var upd = root.lastUpdatedText ? (" · " + root.lastUpdatedText) : ""
              return grid + alarm + upd
            }
          }

          Rectangle {
            id: refreshBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: refreshRow.implicitWidth + Style.space(14)
            implicitHeight: refreshRow.implicitHeight + Style.space(6)
            radius: Math.min(Style.cornerRadius, 6)
            color: refreshArea.containsMouse
              ? Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.14)
              : Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.06)

            Behavior on color { ColorAnimation { duration: Style.duration(140) } }

            Row {
              id: refreshRow
              anchors.centerIn: parent
              spacing: Style.space(5)

              Text {
                textFormat: Text.PlainText
                text: root.refreshing ? "󰔟" : "󰑓"
                color: root.fgColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                textFormat: Text.PlainText
                text: root.refreshing ? "Updating" : "Refresh"
                color: root.fgColor
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: refreshArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.refresh()
            }
          }
        }
      }
    }
  }

  component MetricTile: Rectangle {
    property string glyph: ""
    property string title: ""
    property string value: "—"
    property string subtitle: ""
    property bool highlight: false
    property bool warn: false

    implicitHeight: tileCol.implicitHeight + Style.space(16)
    radius: Math.min(Style.cornerRadius, 8)
    color: highlight
      ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
      : Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.05)
    border.width: 1
    border.color: highlight
      ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.32)
      : Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.10)

    Column {
      id: tileCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(10)
      spacing: Style.space(3)

      Row {
        spacing: Style.space(5)

        Text {
          textFormat: Text.PlainText
          text: glyph
          color: highlight ? root.accentColor : (warn ? root.urgentColor : root.mutedColor)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          text: title
          color: root.mutedColor
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.8
        }
      }

      Text {
        textFormat: Text.PlainText
        text: value
        color: highlight ? root.accentColor : (warn ? root.urgentColor : root.fgColor)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        text: subtitle
        color: root.mutedColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }
  }

  component StatPair: Column {
    property string label: ""
    property string value: "—"

    width: parent.width
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      text: label
      color: root.mutedColor
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      width: parent.width
    }

    Text {
      textFormat: Text.PlainText
      text: value
      color: root.fgColor
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
      width: parent.width
    }
  }
}
