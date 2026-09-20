---
name: agentcron
description: "Create, inspect, edit, and debug scheduled jobs with the AgentCron CLI and its Omarchy bar widget. Use for any request about scheduling something, running a command at a set time, cron, systemd timers, a daily/weekly job, an unattended agent run, or reading the result of a job that already ran."
---

# AgentCron

Scheduled jobs backed by systemd user timers, with their state in the Omarchy
bar. **systemd does the timing.** The CLI defines jobs and records runs; the
bar widget renders and offers buttons. Nothing holds a timer in a process, so
restarting the shell never loses a schedule.

Never build a scheduler inside a long-lived process when a user timer will do:
the schedule then dies with that process.

## Commands

```bash
agentcron add <name> --at '<OnCalendar>' [options] --shell '<line>'
agentcron edit <name> [same options]     # in place; an empty string clears a gate
agentcron list                           # one line per job
agentcron status --json                  # the contract the widget reads
agentcron show <name>                    # definition + current status
agentcron run|pause|resume|approve|skip|rm <name>
agentcron log <name> [-n N] [--path]
agentcron doctor
```

Schedules are systemd `OnCalendar`, validated on write. Five-field cron is
rejected: write `*:0/15`, not `*/15 * * * *`. Verify an expression with
`systemd-analyze calendar '<expr>'`.

`edit` rewrites the units every time, which also repairs drift. Fields other
than `schedule`, `persistent`, and `paused` are read fresh at every run, so
changing them takes effect without touching systemd.

## Scheduling an unattended agent run

```bash
agentcron add <name> --at '08:30' \
  --timeout 5400 \
  --expect '<the literal last line the agent is told to print>' \
  --result-cmd '<command printing one line worth copying>' \
  --shell '<agent-cli> --print @<prompt-file>'
```

Rules that matter when nobody is watching:

- Pass whatever flag the agent CLI uses to skip approval prompts. An
  unattended run cannot answer a question.
- Keep the prompt in a file and reference it, so quoting stays sane and the
  prompt can be edited without touching the job.
- State in the prompt that the run is unattended and must never ask a
  question or wait for confirmation.
- Require one literal status line as the **last line** of the reply. It
  becomes both the panel's summary and the `--expect` target.
- Never let an unattended run write the clipboard. Write a file, then notify.
- Give every agent job at least `--expect`. An agent can exit 0 having done
  nothing at all.

## Reading a run's result

1. Panel row or `agentcron list` — state, next run, history, summary line.
2. `agentcron log <name>` — the command's full output.
3. Whatever `--result-cmd` captured — shown in the panel with a Copy button
   (`c` on the selected row). Use it to hand the user the artifact, the log
   command, or the agent session to reopen.

## Status semantics

| State | Means |
|---|---|
| `ok` | zero exit and every gate passed |
| `attention` | zero exit but `--expect` did not match, or `--verify` failed |
| `failed` | non-zero exit, or killed by `--timeout` |
| `waiting` | an `--ask` job is waiting for approval |
| `running` / `paused` / `never` | self-evident |

A job's failure never fails its unit: the runner records the outcome and exits
0. An `agentcron-*` unit in `systemctl --user --failed` means AgentCron itself
broke — run `agentcron doctor`.

## Notifications

Failures, timeouts, and approval requests notify automatically. Anything else
is the job's own business. `omarchy-notification-send ... --exec <program>
[args...]` makes a notification clickable; the argv is separate words, not one
quoted string. A job that prepares something to paste can write a file and
offer `--exec bash -c "wl-copy < <file>"`, which never touches the clipboard
until the user clicks.

## Files

| Path | Holds |
|---|---|
| `~/.config/agentcron/jobs/<name>.json` | job definition, including the `PATH` captured at creation |
| `~/.config/systemd/user/agentcron-<name>.{service,timer}` | generated units, never hand-edit |
| `~/.local/state/agentcron/runs/<name>.jsonl` | one JSON line per run |
| `~/.local/state/agentcron/logs/<name>/<ts>.log` | captured output, newest 20 kept |
| `~/.local/state/agentcron/revision` | bumped on every change; the widget watches it |

## Limits

- Jobs run with the `PATH` captured at creation. After moving a tool, run
  `agentcron edit <name> --refresh-path` from a shell where it works.
- User timers need `loginctl enable-linger` to fire while logged out, and
  nothing here wakes a suspended machine.
- One run per job at a time; systemd will not start a second copy.
- `Persistent=true` catches up one missed run after boot unless
  `--no-persistent`.
