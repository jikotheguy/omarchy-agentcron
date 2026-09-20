# AgentCron

Scheduled jobs for [Omarchy](https://omarchy.org), with their state in the
bar: what runs next, what failed, and what is waiting for your approval.

**systemd does the timing, not this plugin.** Each job is a plain systemd user
timer. The bar widget is a viewer and a set of buttons, so restarting or
crashing `omarchy-shell` never loses a schedule and nothing keeps a timer in
memory.

It runs any non-interactive command — a backup, a sync, a report. It is built
for the ones where a zero exit code does not prove the work happened, which is
the normal case for a headless AI agent run.

## Install

```bash
omarchy plugin add https://github.com/jikotheguy/omarchy-agentcron.git --enable
~/.config/omarchy/plugins/jikotheguy.agentcron/install.sh
```

The first command installs the bar widget. The second symlinks the `agentcron`
CLI into `~/.local/bin`; it is separate because `omarchy plugin add` never
executes code from a plugin.

Place the widget where you want it:

```bash
omarchy bar move jikotheguy.agentcron --section right
```

For jobs that must run while you are logged out:

```bash
sudo loginctl enable-linger $USER
```

## Create a job

```bash
agentcron add backup --at 'Mon..Fri 02:00' --desc 'Nightly restic backup' \
  --shell 'restic backup ~/Documents'

# ask first: posts a notification and runs nothing until you approve it
agentcron add upgrade --at 'Sun 09:00' --ask --shell 'paru -Syu --noconfirm'
```

Schedules are systemd `OnCalendar` expressions, validated with
`systemd-analyze calendar` when the job is created. Five-field cron is not
accepted: write `*:0/15`, not `*/15 * * * *`.

| Expression | Runs |
|---|---|
| `daily` / `hourly` / `weekly` | midnight / on the hour / Mondays |
| `Mon..Fri 09:30` | weekdays at 09:30 |
| `*:0/15` | every 15 minutes |
| `2026-12-25 09:00` | once |

A run missed while the machine was off is caught up at the next boot unless
you pass `--no-persistent`.

## When an exit code is not enough

A scheduled agent can exit 0 and still have done nothing: no matching input,
an empty queue, a silent refusal. Two optional gates turn that into a visible
`attention` state instead of a silent success.

```bash
agentcron add digest --at 'Mon..Fri 08:30' \
  --expect 'processed [0-9]+ items' \
  --verify 'test -s ~/reports/today.csv' \
  --shell 'my-agent --print "summarise today"'
```

- `--expect REGEX` — the run's output must match, or the run is `attention`.
- `--verify SHELL` — after a zero exit, this command must also exit zero.

Have the job print one literal status line as its last line and match that:
it becomes both the panel's summary and the `--expect` target.

## States

| State | Meaning |
|---|---|
| `ok` | last run succeeded and passed its gates |
| `attention` | ran, exited zero, but `--expect` or `--verify` did not pass |
| `failed` | non-zero exit, or killed by `--timeout` |
| `waiting` | an `--ask` job is waiting for approval |
| `running` | executing now |
| `paused` | scheduling disabled, definition kept |
| `never` | created, never run |

Failures, timeouts, and approval requests raise a desktop notification. The
bar glyph takes the worst state across all jobs and badges how many are failed
or waiting.

## Commands

| Command | Does |
|---|---|
| `add <name>` | create a job (`--at`, `--ask`, `--desc`, `--cwd`, `--env`, `--timeout`, `--expect`, `--verify`, `--result-cmd`, `--no-persistent`, then `--shell` or `--run`) |
| `edit <name>` | change any field in place; an empty string clears a gate, `--refresh-path` recaptures `PATH` |
| `list` | one line per job: state, next run, last result |
| `status [--json]` | summary; `--json` is the contract the bar widget reads |
| `show <name>` | job definition plus its current status |
| `run <name>` | run now |
| `pause` / `resume` | stop and restart scheduling |
| `approve` / `skip` | answer a waiting `--ask` request |
| `log <name> [-n N] [--path]` | last run's output |
| `rm <name>` | delete the job and its units; logs are kept |
| `doctor` | check the manager, linger, units, and each job's command |

`--run` takes bare words and consumes the rest of the line, so it must come
last. Use `--shell` when you need pipes, globs, or redirection.

## Handing you the next step

`--result-cmd '<shell>'` runs after the job and stores its first line of
output on the run record. The panel shows that line with a **Copy** button
(`c` on the selected row), so a job can hand you the way into whatever it
produced — a report path, a container id, a session to reopen.

```bash
agentcron add report --at 'Mon 08:30' \
  --result-cmd 'ls -t ~/reports/*.csv | head -1' \
  --shell 'make -C ~/reports weekly'
```

For an agent CLI that keeps session files, print its resume command there
and one click takes you back into the run's full transcript.

The panel never touches the clipboard on its own; only Copy does.

## Letting your agent drive it

`skills/agentcron/SKILL.md` is a skill file for coding agents: what the
commands are, how to schedule an unattended run, how to read a result, and
the traps. Drop it where your agent looks for skills, for example:

```bash
ln -s ~/.config/omarchy/plugins/jikotheguy.agentcron/skills/agentcron ~/.claude/skills/agentcron
```

Then "run my backup every weekday at 2am and tell me when it fails" is one
sentence instead of a man page.

## Files

| Path | Holds |
|---|---|
| `~/.config/agentcron/jobs/<name>.json` | job definition, including the `PATH` captured at creation |
| `~/.config/systemd/user/agentcron-<name>.{service,timer}` | generated units — never hand-edit |
| `~/.local/state/agentcron/runs/<name>.jsonl` | one line per run: times, status, exit code, log path, summary |
| `~/.local/state/agentcron/logs/<name>/<ts>.log` | captured output, newest 20 kept |
| `~/.local/state/agentcron/pending/<name>.json` | a waiting approval request |
| `~/.local/state/agentcron/revision` | bumped on every change; the widget watches it |

The units are plain systemd, so `systemctl --user list-timers 'agentcron-*'`
and `journalctl --user -u agentcron-<name>` work as usual.

**A job that fails does not fail its unit.** The run record is the source of
truth for the job's outcome, so the runner exits zero after recording. A
failed `agentcron-*` unit therefore means AgentCron itself broke — run
`agentcron doctor`.

## Limits

- Jobs run with the `PATH` captured when they were created. After moving a
  tool, run `agentcron edit <name> --refresh-path` from a shell where the
  command works.
- User timers need `enable-linger` to fire while you are logged out, and
  nothing here wakes a suspended machine.
- One run per job at a time: systemd will not start a second copy while the
  service is active.
- `--ask` requests are answered from the panel or the CLI, not from the
  notification itself.

## License

MIT
