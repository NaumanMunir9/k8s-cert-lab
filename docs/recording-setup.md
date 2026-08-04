# Recording setup

A work laptop typically also holds live production cloud credentials
(`~/.kube/config`, AWS SSO tokens, GCP ADC, Jira API tokens) and will be on
camera. `bin/record.sh <profile>` hands you a shell that cannot see any of
that: no inherited `KUBECONFIG` pointing at the real file, work credential
env vars unset, history disabled, and a minimal `[profile]` prompt so no
internal hostnames or paths show on screen.

## Measured bitrate

From `~/Videos/2026-06-04 21-00-17.mkv`: 8,054,705 bytes over 153.8 s of
1080p OBS footage of this repo's terminal window.

- **≈ 3.0 MiB/min** (2.997 MiB/min, 1024-based)
- ≈ 3.1 MB/min (1000-based — this is likely where the "3.1" figure some
  planning notes cite came from; use the MiB figure for actual disk-budget
  math)

Use this to size the footage drive instead of re-measuring every session:
a 30-minute recording is roughly 90 MiB, well inside the ~125 GiB typically
free on the footage partition.

## Pre-record checklist

1. Run `bin/record.sh <profile> --check` first. It verifies, without
   opening a shell:
   - the footage directory exists and is writable
   - disk and memory floors for the profile (`bin/preflight.sh --recording`,
     which adds an OBS memory allowance on top of the profile's normal
     floor)
   - no work kubeconfig is active in the environment
2. For memory-heavy profiles (`trio`, `nocni`), close the browser before
   starting. `bin/preflight.sh` will refuse to proceed if available memory
   is too low, but browser tabs can still eat into the margin during the
   recording itself.
3. Enter the shell with `bin/record.sh <profile>` (no `--check`) and
   confirm the prompt shows only `[<profile>]` — nothing else. If a
   directory name, hostname, or path other than the current working
   directory is visible in the prompt, stop and fix it before recording.
4. In OBS, set the recording output path to the footage directory
   (`$LAB_FOOTAGE_DIR`, defaulting to `~/k8s-lab-footage`) — not the default
   OBS output folder. Set `LAB_FOOTAGE_DIR` to a path on an external drive
   if you do not want footage accumulating on the OS disk.

## OBS capture scope

OBS must capture **only the terminal window**, never the whole desktop.
A window capture (not a display/monitor capture) means:

- desktop notifications (email, chat, calendar) cannot appear in frame
- other open windows (browser tabs, editors with work files open) cannot
  leak even if they're behind the terminal
- switching desktops/workspaces mid-recording does not expose anything

This is a one-time OBS scene setting, not something `record.sh` can
enforce from inside the shell — check it before every session, not just
once.

## Terminal font size

Set the terminal font to at least 16pt (or the equivalent "large" preset)
before recording. At 1080p, anything smaller is difficult to read once the
video is re-encoded and viewed at typical YouTube playback sizes.

## What `record.sh` actually blocks

| Vector | How it's blocked |
|---|---|
| `~/.kube/config` (10 real contexts, current context is a live prod GKE cluster) | `KUBECONFIG` is set from `guard_init`'s repo-local path (`.work/kubeconfig-<profile>`) and passed explicitly into the `env -i` shell — the real file is never read, referenced, or inherited. |
| AWS SSO tokens/profiles | `AWS_PROFILE`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION` are unset inside the clean shell, and `env -i` means nothing else from the outer environment is inherited in the first place. |
| GCP ADC (`~/.config/gcloud`) | `GOOGLE_APPLICATION_CREDENTIALS` and `CLOUDSDK_CORE_PROJECT` are unset; `env -i` drops any other `CLOUDSDK_*`/`GOOGLE_*` vars from the outer shell. |
| Jira API token | `JIRA_API_TOKEN` and `JIRA_URL` are unset. |
| `GITHUB_TOKEN` / `GH_TOKEN` | Unset, same reasoning. |
| Shell history | `HISTFILE` is exported as an empty string and `HISTSIZE`/`HISTFILESIZE` are set to 0. A bare `unset HISTFILE` is not enough on its own — an interactive bash started with `HISTFILE` absent from the environment re-defaults it to `~/.bash_history`, so the real fix is exporting an explicit empty value, which `history -a` then refuses to write to at all. |
| Employer/work paths in the prompt | `PS1` is hard-set to `[<profile>] <basename-of-cwd> $` — no `\h`, `\u@\h`, or absolute path components that could show a work directory name. |
| Stray env vars in general | `env -i` clears everything except the explicit allowlist (`HOME`, `USER`, `TERM`, `PATH`, `LANG`, `KUBECONFIG`, `KUBE_CONTEXT`, `LAB_PROFILE`) before the clean shell even starts, so anything not on that list — work-repo env vars, tokens set by direnv, etc. — cannot leak by omission from the unset list above. |

`tests/record.bats` drives the actual clean shell non-interactively (piped
stdin, not a TTY) and asserts on its real output for the credential,
history, and kubeconfig checks, rather than only grepping the script text —
see that file for the assertions and a sanity check proving they can fail.
