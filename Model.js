function emptySummary() {
  return {
    total: 0,
    active: 0,
    paused: 0,
    failed: 0,
    attention: 0,
    waiting: 0,
    running: 0,
    nextJob: "",
    nextRunAt: null
  }
}

function asInt(value, fallback) {
  var n = parseInt(String(value), 10)
  return isFinite(n) ? n : fallback
}

function asString(value) {
  return value === undefined || value === null ? "" : String(value)
}

function parseJob(raw) {
  if (!raw || typeof raw !== "object") return null

  var history = []
  var histIn = Array.isArray(raw.history) ? raw.history : []
  for (var i = 0; i < histIn.length && history.length < 7; i++) {
    var entry = histIn[i] || {}
    history.push({
      startedAt: asString(entry.startedAt),
      status: asString(entry.status) || "never"
    })
  }

  var lastRun = null
  if (raw.lastRun && typeof raw.lastRun === "object") {
    lastRun = {
      startedAt: asString(raw.lastRun.startedAt),
      endedAt: asString(raw.lastRun.endedAt),
      status: asString(raw.lastRun.status),
      exitCode: asInt(raw.lastRun.exitCode, 0),
      durationSec: asInt(raw.lastRun.durationSec, 0),
      logPath: asString(raw.lastRun.logPath),
      summary: asString(raw.lastRun.summary),
      hint: asString(raw.lastRun.hint)
    }
  }

  var pending = null
  if (raw.pending && typeof raw.pending === "object") {
    pending = { requestedAt: asString(raw.pending.requestedAt) }
  }

  return {
    name: asString(raw.name),
    description: asString(raw.description),
    schedule: asString(raw.schedule),
    mode: asString(raw.mode),
    paused: raw.paused === true,
    running: raw.running === true,
    nextRunAt: raw.nextRunAt ? String(raw.nextRunAt) : null,
    state: asString(raw.state) || "never",
    pending: pending,
    lastRun: lastRun,
    history: history
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "Empty status" }

  var data
  try {
    data = JSON.parse(text)
  } catch (e) {
    return { ok: false, error: "Malformed status JSON" }
  }
  if (!data || typeof data !== "object" || Array.isArray(data))
    return { ok: false, error: "Malformed status JSON" }

  var summaryIn = data.summary && typeof data.summary === "object" ? data.summary : {}
  var summary = emptySummary()
  summary.total = Math.max(0, asInt(summaryIn.total, 0))
  summary.active = Math.max(0, asInt(summaryIn.active, 0))
  summary.paused = Math.max(0, asInt(summaryIn.paused, 0))
  summary.failed = Math.max(0, asInt(summaryIn.failed, 0))
  summary.attention = Math.max(0, asInt(summaryIn.attention, 0))
  summary.waiting = Math.max(0, asInt(summaryIn.waiting, 0))
  summary.running = Math.max(0, asInt(summaryIn.running, 0))
  summary.nextJob = asString(summaryIn.nextJob)
  summary.nextRunAt = summaryIn.nextRunAt ? String(summaryIn.nextRunAt) : null

  var jobsIn = Array.isArray(data.jobs) ? data.jobs : []
  var jobs = []
  for (var i = 0; i < jobsIn.length; i++) {
    var job = parseJob(jobsIn[i])
    if (job) jobs.push(job)
  }

  return {
    ok: true,
    error: "",
    revision: asInt(data.revision, 0),
    generatedAt: asString(data.generatedAt),
    summary: summary,
    jobs: jobs
  }
}

function parseIsoMs(iso) {
  if (!iso) return NaN
  var ms = Date.parse(String(iso))
  return isFinite(ms) ? ms : NaN
}

function relativeTime(iso, nowMs) {
  var ms = parseIsoMs(iso)
  if (!isFinite(ms)) return ""
  var now = isFinite(nowMs) ? Number(nowMs) : Date.now()
  var delta = ms - now
  var future = delta > 0
  var abs = Math.abs(delta)
  var minutes = Math.round(abs / 60000)
  var hours = Math.round(abs / 3600000)
  var days = Math.round(abs / 86400000)
  var label
  if (abs < 45000) label = "now"
  else if (minutes < 60) label = minutes + "m"
  else if (hours < 48) label = hours + "h"
  else label = days + "d"
  if (label === "now") return "now"
  return future ? "in " + label : label + " ago"
}

function nextRunLabel(summary, nowMs) {
  var name = asString(summary && summary.nextJob)
  var when = summary ? summary.nextRunAt : null
  if (!name && !when) return "no jobs"
  var rel = relativeTime(when, nowMs)
  if (!name) return rel || "no upcoming run"
  if (!rel) return name
  if (rel === "now") return name + " now"
  return name + " " + rel
}

function tooltip(summary, nowMs) {
  var parts = [nextRunLabel(summary, nowMs)]
  var failed = summary ? asInt(summary.failed, 0) : 0
  var waiting = summary ? asInt(summary.waiting, 0) : 0
  if (failed > 0) parts.push(failed + " failed")
  if (waiting > 0) parts.push(waiting + " waiting")
  return parts.join(" · ")
}

function formatDuration(sec) {
  var n = asInt(sec, 0)
  if (n < 0) n = 0
  if (n < 60) return n + "s"
  var minutes = Math.floor(n / 60)
  var seconds = n % 60
  var hours = Math.floor(minutes / 60)
  minutes = minutes % 60
  if (hours > 0) return hours + "h " + minutes + "m"
  return seconds > 0 ? minutes + "m " + seconds + "s" : minutes + "m"
}

function lastRunLine(job) {
  if (!job || !job.lastRun) return "never ran"
  var status = asString(job.lastRun.status) || "unknown"
  return status + " · " + formatDuration(job.lastRun.durationSec)
}

// The live state must read as words, not only as a color: several Omarchy
// themes resolve accent and foreground to nearly the same hue, which makes
// waiting/attention indistinguishable from ok on color alone.
function statusLine(job) {
  if (!job) return ""
  var state = asString(job.state)
  if (state === "running") return "running now"
  if (state === "waiting") return "needs approval"
  if (state === "paused") return "paused"
  if (state === "never") return "never ran"
  return lastRunLine(job)
}

// Codepoints verified by rendering JetBrainsMono Nerd Font, not guessed:
// F0026 filled alert triangle, F02FC filled info circle, F0625 question
// circle, F040C filled play circle, F03E4 pause bars, F13AB stopwatch.
function statusGlyph(state) {
  if (state === "failed") return String.fromCodePoint(0xF0026)
  if (state === "attention") return String.fromCodePoint(0xF02FC)
  if (state === "waiting") return String.fromCodePoint(0xF0625)
  if (state === "running") return String.fromCodePoint(0xF040C)
  if (state === "paused") return String.fromCodePoint(0xF03E4)
  return ""
}

function jobNextLabel(job, nowMs) {
  if (!job) return ""
  if (job.paused) return "paused"
  if (!job.nextRunAt) return "—"
  return relativeTime(job.nextRunAt, nowMs) || "—"
}

function worstState(summary) {
  if (!summary) return "ok"
  if (asInt(summary.failed, 0) > 0) return "failed"
  if (asInt(summary.waiting, 0) > 0) return "waiting"
  if (asInt(summary.attention, 0) > 0) return "attention"
  if (asInt(summary.running, 0) > 0) return "running"
  if (asInt(summary.total, 0) === 0) return "never"
  return "ok"
}

function barGlyph(state) {
  if (state === "failed" || state === "waiting" || state === "attention")
    return String.fromCodePoint(0xF0026)
  return String.fromCodePoint(0xF13AB)
}

function formatEndedAt(iso, nowMs) {
  var rel = relativeTime(iso, nowMs)
  if (!rel) return ""
  return rel === "now" ? "ended just now" : "ended " + rel
}

function heroMeta(summary, available, lastError) {
  if (!available && lastError) return lastError
  var total = summary ? asInt(summary.total, 0) : 0
  if (total === 0) return "No scheduled jobs"
  return total + " job" + (total === 1 ? "" : "s")
}
