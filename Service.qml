import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool available: false
  property bool refreshing: false
  property string lastError: ""
  property int revision: 0
  property string generatedAt: ""
  property var summary: Model.emptySummary()
  property var jobs: []

  readonly property int total: Number(summary.total || 0)
  readonly property int failed: Number(summary.failed || 0)
  readonly property int waiting: Number(summary.waiting || 0)
  readonly property int attention: Number(summary.attention || 0)
  readonly property int runningCount: Number(summary.running || 0)
  readonly property int badgeCount: failed + waiting
  readonly property string worstState: Model.worstState(summary)
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 3600)
  readonly property bool busy: statusProcess.running || actionProcess.running

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string stateDir: stateHome + "/agentcron"
  readonly property string revisionPath: stateDir + "/revision"
  readonly property string cliPath: {
    var url = String(Qt.resolvedUrl("bin/agentcron") || "")
    if (url.indexOf("file://") === 0) return url.replace(/^file:\/\//, "")
    if (url.charAt(0) === "/") return url
    return home + "/.config/omarchy/plugins/jikotheguy.agentcron/bin/agentcron"
  }

  property string _statusOutput: ""
  property string _statusError: ""
  property string _actionError: ""
  property bool _pendingRefresh: false
  property var _pendingAction: null

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function setError(message) {
    var text = elideStatus(message)
    if (text === lastError) return
    lastError = text
    if (text !== "") console.warn("agentcron", text)
  }

  function refresh() {
    if (cliPath === "") {
      available = false
      setError("agentcron CLI path is empty")
      return
    }
    if (statusProcess.running) {
      _pendingRefresh = true
      return
    }
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = [cliPath, "status", "--json"]
    statusProcess.running = true
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      available = false
      setError(parsed.error || "Failed to parse agentcron status")
      return
    }
    revision = parsed.revision
    generatedAt = parsed.generatedAt
    summary = parsed.summary
    jobs = parsed.jobs
    available = true
    setError("")
  }

  function runNow(name) { runAction("run", name) }
  function pause(name) { runAction("pause", name) }
  function resume(name) { runAction("resume", name) }
  function approve(name) { runAction("approve", name) }
  function skip(name) { runAction("skip", name) }

  function runAction(verb, name) {
    var job = String(name || "")
    if (job === "" || cliPath === "") return
    if (actionProcess.running) {
      _pendingAction = [verb, job]
      return
    }
    _actionError = ""
    actionProcess.command = [cliPath, verb, job]
    actionProcess.running = true
  }

  // The panel never writes the clipboard on its own; only an explicit Copy.
  function copyToClipboard(text) {
    var value = String(text || "")
    if (value === "") return
    copyProcess.running = false
    copyProcess.command = ["wl-copy", value]
    copyProcess.running = true
  }

  onRefreshIntervalSecChanged: refreshTimer.restart()

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: delayedRefresh
    interval: 400
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
    }
  }

  FileView {
    id: revisionFile
    path: root.revisionPath
    watchChanges: true
    printErrors: false
    onFileChanged: {
      reload()
      root.refresh()
    }
  }

  FileView {
    id: stateDirWatcher
    path: root.stateDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      pollWatchdog.stop()
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.applyStatus(stdout)
      else {
        root.available = false
        root.setError(stderr || stdout || (exitCode === 127 ? "agentcron not found" : "Could not read agentcron status"))
      }
      if (root._pendingRefresh) {
        root._pendingRefresh = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) root.setError(stderr || "agentcron action failed")
      else if (root.lastError !== "") root.setError("")
      delayedRefresh.restart()
      if (root._pendingAction) {
        var next = root._pendingAction
        root._pendingAction = null
        Qt.callLater(function() { root.runAction(next[0], next[1]) })
      }
    }
  }

  Process {
    id: copyProcess
    running: false
    command: []
    onExited: function(exitCode) {
      if (exitCode !== 0) root.setError("wl-copy failed (exit " + exitCode + ")")
    }
  }
}
