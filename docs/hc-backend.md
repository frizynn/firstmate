# hc runtime backend

hc is an experimental session-provider backend for herdr-core, the terminal core under Herdr.app.
It provides task terminals while Treehouse continues to provide git worktrees, the same split tmux uses.
herdr-core is not Herdr 1: the `herdr` backend ([`herdr-backend.md`](herdr-backend.md)) talks to the `herdr` multiplexer, and the two share no socket, id space, or CLI.
[`configuration.md`](configuration.md#runtime-backend-configbackend--fm_backend) owns shared selection and metadata semantics.
The adapter header in `bin/backends/hc.sh` owns design decisions and measured CLI facts; this page is the operator-facing mirror and must not contradict it.
[`verification/runtime-backends.md`](verification/runtime-backends.md#hc) records what was exercised against a real core.

## Setup

Prerequisites:

- `hc` on `PATH` (measured on `hc 0.1.13`); `hc` starts its own core on first use.
- `jq` for JSON responses.
- The universal harness and toolchain requirements in [`configuration.md`](configuration.md#toolchain).

Select hc with local `config/backend` containing `hc`, `FM_BACKEND=hc` for one launch, or an explicit request to Firstmate.
It is never runtime auto-detected; see "Selection is explicit" below.

The core a task lands on is the one `HC_SESSION` names when the task is spawned, or hc's `default` session when it is unset.
Herdr.app shows the `default` session's terminals.

## Selection is explicit

hc is explicit-only, like zellij, orca, Paseo, and tern.
hc stamps `HC_TERMINAL_ID` into every process an hc terminal starts, including a tmux server or Herdr 1 client started inside one, so its presence never proves the captain chose hc and `fm_backend_detect` ignores it.

## Task shape and metadata

Each task is one hc terminal running the user's login shell in the project directory, started with `--no-parent --outlive-parent --no-notify` so it is independent of whichever hc terminal Firstmate itself runs in.
The terminal carries these labels:

| Label | Value | Purpose |
| --- | --- | --- |
| `firstmate.task` | `fm-<id>` | Task identity checked before input or close. |
| `firstmate.home` | `<hometag>` from `bin/fm-backend-hometag-lib.sh` | Keeps two homes with the same task id apart. |
| `herdr.space` | `FM_HC_SPACE`, default `fm-<hometag>` | Groups a home's tasks in one Herdr.app space. |
| `herdr.tab` | `<hometag>-fm-<id>` | One Herdr.app tab per task. |

```text
backend=hc
window=<session>:<address>
hc_session=<session>
hc_terminal=<address>
```

`<address>` is hc's terminal address such as `t7`.
Every adapter call sets exactly the recorded `HC_SESSION`, so a task keeps reaching its own core even when the caller's environment names another one.
An input, capture, or close that carries the task label refuses a terminal whose `firstmate.task` or `firstmate.home` label does not match, and a close without a label still refuses a terminal that lacks this home's labels.

## Operations

| Operation | hc command |
| --- | --- |
| Container ensure | `hc server status` |
| Create task | `hc run --bg --no-parent --outlive-parent --no-notify --cwd <project> --label ...` |
| Capture | `hc read --lines <n>` |
| Visible capture | `hc read --lines 0` |
| Send a line and submit | `hc send` |
| Type without submitting | `hc keys`, one key per character |
| Named key | `hc keys` |
| Current path | `hc get`, the foreground process's `cwd` |
| Busy state | `hc get`, native `status.state` (`working` is busy) |
| Agent state | `hc get`, the foreground process and its process group, through the shared classifier |
| Close | `hc kill`, then `hc rm`, then `hc get` must answer not found |

## Limits

- `hc send` always presses Enter.
  Typing without submitting goes through `hc keys`, which has keys only for letters, digits, space, hyphen, slash, apostrophe, semicolon, backtick, backslash, equals, period, comma, and brackets; text with any other character is refused rather than half-typed.
  The spawn launch line `. '<launch file>'` fits that set unless the home path contains another character, such as `_`.
- Submitting a message uses `hc send` and then reads the composer; only a proven pending composer gets Enter retries.
- hc reports one foreground process per terminal.
  When that process is a launcher, the adapter also reads the rest of its process group from `ps`, which works only for terminals on the local machine.
- Right after a terminal starts, `hc get` can report no foreground process yet, and agent state reads `unreadable` until the shell is up.
- `--secondmate` spawns are refused.
- Firstmate's cleared launch environment does not forward `HC_TERMINAL_ID`, so a worker cannot address its own terminal through hc, and whether hc's native agent status still reports under that environment is not verified.
- Naming a Herdr.app space needs the app window and is not done; whether the labels above display as intended in Herdr.app is not verified.
- hc has no event stream this adapter consumes; supervision polls like tmux.

## Tests

`tests/fm-backend-hc.test.sh` pins the adapter against a fake `hc`.
`tests/fm-backend-hc-smoke.test.sh` drives the real `hc` against a private core with its own `HC_SESSION` and scratch XDG directories, and skips when `hc` or `jq` is missing.
