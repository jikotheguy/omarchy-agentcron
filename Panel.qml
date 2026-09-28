import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "jikotheguy.agentcron"
  ipcTarget: "jikotheguy.agentcron"
  manageIpc: false

  property int selectedIndex: 0
  property bool cursorActive: false
  property double nowMs: Date.now()
  // "active" or "expired": expired jobs have a schedule that never elapses again.
  property string jobTab: "active"
  // Name of the job whose Remove is armed; a second press removes it.
  property string confirmRemove: ""
  readonly property var visibleJobs: jobsForTab(jobTab)
  readonly property int activeCount: jobsForTab("active").length
  readonly property int expiredCount: jobsForTab("expired").length

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showWhenEmpty: setting("showWhenEmpty", true) === true
  readonly property string worstState: cron.worstState
  readonly property int badgeCount: cron.badgeCount
  readonly property string barGlyph: Model.barGlyph(worstState)
  readonly property string barTooltip: Model.tooltip(cron.summary, nowMs)
  readonly property color barIconColor: {
    if (worstState === "failed") return urgent
    if (worstState === "waiting" || worstState === "running" || worstState === "attention") return accent
    if (worstState === "never" || worstState === "paused" || cron.total === 0) return Qt.darker(barForeground, 1.55)
    return barForeground
  }

  property real iconPulse: 1.0

  visible: cron.total > 0 || showWhenEmpty
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function stateColor(state) {
    if (state === "failed") return urgent
    if (state === "waiting" || state === "running" || state === "attention") return accent
    if (state === "never" || state === "paused") return dim
    return foreground
  }

  function jobsForTab(tab) {
    var wantExpired = tab === "expired"
    return cron.jobs.filter(function(job) { return job.expired === wantExpired })
  }

  function selectedJob() {
    var jobs = jobsForTab(jobTab)
    if (jobs.length === 0) return null
    return jobs[Math.max(0, Math.min(selectedIndex, jobs.length - 1))]
  }

  function ensureCursor() {
    var count = jobsForTab(jobTab).length
    if (count === 0) {
      selectedIndex = 0
      return
    }
    if (selectedIndex >= count) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    var count = jobsForTab(jobTab).length
    if (dy === 0 || count === 0) return
    selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + dy))
    scrollCursorIntoView()
  }

  function setJobTab(tab) {
    if (tab === jobTab) return
    jobTab = tab
    confirmRemove = ""
    selectedIndex = 0
    if (panelFlick) panelFlick.contentY = 0
  }

  function setJobCursor(index) {
    cursorActive = true
    selectedIndex = index
    scrollCursorIntoView()
  }

  function activateCursor() {
    if (confirmRemove !== "") {
      removeConfirmed()
      return
    }
    ensureCursor()
    cursorActive = true
  }

  function runSelected() {
    var job = selectedJob()
    if (job) cron.runNow(job.name)
  }

  function copySelectedHint() {
    var job = selectedJob()
    if (job && job.lastRun && job.lastRun.hint) cron.copyToClipboard(job.lastRun.hint)
  }

  function togglePauseSelected() {
    var job = selectedJob()
    if (!job || job.expired) return
    if (job.paused) cron.resume(job.name)
    else cron.pause(job.name)
  }

  function requestRemove(job) {
    if (!job || job.running) return
    if (confirmRemove === job.name) removeConfirmed()
    else confirmRemove = job.name
  }

  function requestRemoveSelected() {
    if (cursorActive) requestRemove(selectedJob())
  }

  function removeConfirmed() {
    var name = confirmRemove
    confirmRemove = ""
    if (name !== "") cron.remove(name)
  }

  function cancelRemove() {
    confirmRemove = ""
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (jobColumn && selectedIndex >= 0 && selectedIndex < jobColumn.children.length)
      scrollItemIntoView(jobColumn.children[selectedIndex])
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    confirmRemove = ""
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    cron.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onSelectedIndexChanged: {
    confirmRemove = ""
    scrollCursorIntoView()
  }
  onWorstStateChanged: if (worstState !== "running") iconPulse = 1.0

  Service {
    id: cron
    settings: root.settings
  }

  Connections {
    target: cron
    function onJobsChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { cron.refresh(); return "ok" }
  }

  SequentialAnimation {
    running: root.worstState === "running" && root.visible
    loops: Animation.Infinite
    NumberAnimation { target: root; property: "iconPulse"; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "iconPulse"; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
  }

  Timer {
    interval: root.opened ? 1000 : 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.barTooltip
    dimmed: cron.total === 0
    iconComponent: Component {
      Item {
        OpticalGlyph {
          anchors.fill: parent
          text: root.barGlyph
          fontFamily: root.fontFamily
          fontSize: Style.bar.iconFont
          color: root.barIconColor
          opacity: root.iconPulse
        }

        Rectangle {
          visible: root.badgeCount > 0
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          width: Math.max(Style.space(8), badgeText.implicitWidth + Style.space(4))
          height: Style.space(8)
          radius: height / 2
          color: cron.failed > 0 ? root.urgent : root.accent

          Text {
            id: badgeText
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.badgeCount > 9 ? "9+" : String(root.badgeCount)
            color: Color.background
            font.family: root.fontFamily
            font.pixelSize: Math.max(7, Style.font.caption - 2)
            font.bold: true
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) cron.refresh()
      else if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) { root.setJobTab(dx > 0 ? "expired" : "active"); return }
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: {
        if (root.confirmRemove !== "") root.cancelRemove()
        else root.close()
      }
      onDeleteRequested: root.requestRemoveSelected()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.runSelected()
        else if (t === "p" || t === "P") root.togglePauseSelected()
        else if (t === "c" || t === "C") root.copySelectedHint()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "AgentCron"
            meta: Model.heroMeta(cron.summary, cron.available, cron.lastError)
            detail: root.badgeCount > 0 ? String(root.badgeCount) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: cron.total > 0 ? 1.0 : 0.5
            iconComponent: Component {
              OpticalGlyph {
                width: Style.font.display
                height: Style.font.display
                text: root.barGlyph
                fontFamily: root.fontFamily
                fontSize: Style.font.display
                color: root.stateColor(root.worstState)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: cron.lastError !== "" && !cron.available
            width: parent.width
            text: cron.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: cron.jobs.length === 0
            width: parent.width
            topPadding: Style.space(8)
            text: "No jobs yet. Create one with agentcron add."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Column {
            visible: cron.jobs.length > 0
            width: parent.width
            spacing: Style.space(10)

            ButtonGroup {
              options: [
                { value: "active", label: "Active " + root.activeCount },
                { value: "expired", label: "Expired " + root.expiredCount, tooltip: "Schedules that never run again (h / l to switch)" }
              ]
              value: root.jobTab
              focusable: false
              spacing: Style.space(6)
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onChanged: function(value) { root.setJobTab(value) }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.visibleJobs.length === 0
              width: parent.width
              text: root.jobTab === "expired"
                ? "No expired jobs. One-shot jobs move here after their date passes."
                : "No active jobs."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              id: jobColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.visibleJobs
                JobRow {
                  required property var modelData
                  required property int index
                  width: jobColumn.width
                  job: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  component JobRow: CursorSurface {
    id: jobRow
    property var job: null
    property int rowIndex: 0
    readonly property bool selected: root.cursorActive && root.selectedIndex === rowIndex
    readonly property bool expanded: selected
    readonly property bool hasPending: !!(job && job.pending)
    readonly property bool confirming: !!(job && root.confirmRemove === job.name)

    hasCursor: selected
    foreground: root.foreground

    implicitHeight: jobContent.implicitHeight + Style.space(10)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setJobCursor(jobRow.rowIndex)
      onClicked: root.setJobCursor(jobRow.rowIndex)
    }

    Column {
      id: jobContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(4)

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            readonly property string stateGlyph: Model.statusGlyph(jobRow.job ? jobRow.job.state : "")
            text: (stateGlyph === "" ? "" : stateGlyph + " ") + (jobRow.job ? String(jobRow.job.name || "") : "")
            color: root.stateColor(jobRow.job ? jobRow.job.state : "ok")
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: jobRow.job ? String(jobRow.job.schedule || "") : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        ColumnLayout {
          spacing: Style.space(2)
          Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

          Text {
            textFormat: Text.PlainText
            text: Model.jobNextLabel(jobRow.job, root.nowMs)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
            Layout.alignment: Qt.AlignRight
          }

          Text {
            textFormat: Text.PlainText
            text: Model.statusLine(jobRow.job)
            color: root.stateColor(jobRow.job ? jobRow.job.state : "never")
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
            Layout.alignment: Qt.AlignRight
          }
        }
      }

      Row {
        spacing: Style.space(3)
        Repeater {
          model: jobRow.job && jobRow.job.history ? jobRow.job.history : []
          Rectangle {
            required property var modelData
            width: Style.space(7)
            height: Style.space(7)
            radius: 1
            color: root.stateColor(modelData.status)
          }
        }
      }

      Column {
        visible: jobRow.expanded
        width: parent.width
        spacing: Style.space(6)
        topPadding: Style.space(4)

        Text {
          textFormat: Text.PlainText
          visible: !!(jobRow.job && jobRow.job.lastRun && jobRow.job.lastRun.summary)
          width: parent.width
          text: jobRow.job && jobRow.job.lastRun ? String(jobRow.job.lastRun.summary || "") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          visible: !!(jobRow.job && jobRow.job.lastRun && jobRow.job.lastRun.endedAt)
          width: parent.width
          text: jobRow.job && jobRow.job.lastRun ? Model.formatEndedAt(jobRow.job.lastRun.endedAt, root.nowMs) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          readonly property string hint: jobRow.job && jobRow.job.lastRun ? String(jobRow.job.lastRun.hint || "") : ""
          visible: hint !== ""
          width: parent.width
          spacing: Style.space(6)

          Text {
            id: hintText
            textFormat: Text.PlainText
            width: parent.width - copyButton.width - Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: parent.hint
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }

          Button {
            id: copyButton
            text: "Copy"
            foreground: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: cron.copyToClipboard(hintText.text)
          }
        }

        Flow {
          visible: !jobRow.confirming
          width: parent.width
          spacing: Style.space(6)

          Button {
            text: "Run now"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            bordered: true
            enabled: !!(jobRow.job && !jobRow.job.running)
            onClicked: if (jobRow.job) cron.runNow(jobRow.job.name)
          }

          Button {
            visible: !!(jobRow.job && !jobRow.job.expired)
            text: jobRow.job && jobRow.job.paused ? "Resume" : "Pause"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: {
              if (!jobRow.job) return
              if (jobRow.job.paused) cron.resume(jobRow.job.name)
              else cron.pause(jobRow.job.name)
            }
          }

          Button {
            visible: jobRow.hasPending
            text: "Approve"
            foreground: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: if (jobRow.job) cron.approve(jobRow.job.name)
          }

          Button {
            visible: jobRow.hasPending
            text: "Skip"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: if (jobRow.job) cron.skip(jobRow.job.name)
          }

          Button {
            text: "Remove"
            tooltipText: "Delete this job and its timer; logs are kept (x)"
            foreground: root.urgent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            bordered: true
            enabled: !!(jobRow.job && !jobRow.job.running)
            onClicked: root.requestRemove(jobRow.job)
          }
        }

        RowLayout {
          visible: jobRow.confirming
          width: parent.width
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: "Remove this job? Logs are kept."
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Button {
            text: "Cancel"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: root.cancelRemove()
          }

          Button {
            text: "Remove"
            foreground: root.urgent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            bordered: true
            onClicked: root.removeConfirmed()
          }
        }
      }
    }
  }
}
