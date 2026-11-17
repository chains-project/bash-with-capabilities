# Benchmark: bash reimplementations for agents

This benchmark compares gbash, just-bash, rshell and tinysandbox with GNU bash. Background on each tool is in
[`../PRIOR-ART.md`](../PRIOR-ART.md).

## Usage

```bash
./setup.sh                    # fetch and build the pinned versions into .tools/ (git, go, node, npm)
./run.py selfcheck            # validate the instruments first (see below)
./run.py all --json results/$(date +%F).json --report results/$(date +%F).md
./run.py conformance --tools gbash --only arith   # a subset
```

`run.py` needs only the Python 3 standard library. The resource suite also needs `systemd-run --user` and `prlimit`.

## Quantitative suites

Every run gets a fresh copy of `fixture/` as its granted, writable working directory. Cases are `#### name` blocks
in `cases/<suite>/*.sh`; the file name is the case group.

- **conformance**: 137 scripts in 8 groups (expansion, quoting, control, arrays, io, semantics, coreutils, agent).
  Each script is run by real bash (the oracle) and by each tool, and stdout and exit code are compared. A mismatch
  is classified as:
  - **loud**: the tool signalled a problem, either with stderr output or a different non-zero exit code;
  - **silent**: wrong output and no signal. These are the worst for an agent, which will trust the result.

  The `agent` group holds the multi-step idioms that LLM agents typically emit.
- **security**: 48 escape probes in five kinds, each detected on the host, never from the tool's own report:
  - read: the secret token, placed outside the workdir, shows up in the output;
  - write and exec: the host directory outside the workdir changed;
  - net: a TCP listener on the harness side received a connection;
  - env: a host environment token leaked.

  The workdir contains symlinks to the secret, and probes use the secret's real host paths.
- **policy**: 5 scenarios with 68 probes, each tool under its *strictest* configuration rather than the permissive
  workspace of the suites above. The scenarios are: a command allowlist, path grants (`src` read-only, `out`
  read-write, the rest hidden), a read-only workspace, a network URL allowlist, and an environment allowlist.

  Each scenario is written once in a tool-neutral policy format ([`POLICY.md`](POLICY.md)), and an adapter per tool
  translates it. Probes either must work (`allow`) or must have no effect on the host (`deny`); a deny probe tries
  every bypass we know (a command name in a variable, `eval`, `xargs`, `find -exec`, `..`, symlinks, redirects, and
  so on).

  The report gives one of three results per tool and scenario:
  - ✅ enforced exactly;
  - ❌ a deny probe had an effect;
  - ⚠️ an allow probe failed;
  - `n/a (reason)` when the tool cannot express the policy.

  It also gives the verdicts of the tool's static pre-check, where it has one (rshell). The `bash` row ignores the
  policy and serves as the positive control.
- **resource**: 8 exhaustion probes: infinite loop, infinite recursion, fork bomb, memory, output flood, disk fill,
  huge brace expansion, sleep. A probe counts as *contained* only if the tool ends the run itself: before the
  harness's 20 s deadline, without being killed by a signal, under 1.5 GiB RSS, and under 90% of the 200 MB
  output and disk caps.

  All runs happen inside a systemd scope (MemoryMax 2G, TasksMax 256) with `prlimit --fsize`, so the bash control
  cannot harm the host.
- **perf**: 9 tasks, including startup, a shell loop with 2k iterations, and grep, sort, awk and sed over 50k lines
  (3 MB). The tasks are sized to stay under every tool's default limits, so they measure speed rather than caps.
  The metrics are median wall time (`-n` repeats) and peak RSS, both measured with GNU `time`. Outputs are also
  checked against bash, so a fast but wrong tool is flagged.

## Qualitative rubric

[`QUALITATIVE.md`](QUALITATIVE.md) answers 12 criteria per tool, each with a file and line in that tool's repo as
evidence:

- language and embedding;
- parser;
- shell feature coverage;
- command set;
- filesystem model;
- policy model;
- static checking;
- resource limits;
- network;
- formal and testing artifacts;
- maturity;
- relevance to this project.

## Instrument validation

`run.py selfcheck` must print only ✅. It checks:

- **conformance**: bash against bash gives 137/137;
- **security**: bash (the known positive) escapes on every probe, and `null`, which runs nothing (the known negative),
  blocks every probe;
- **policy**: under bash every probe's effect is observed, and under `null` none is;
- **resource**: `null` is contained, and bash is not contained on any probe.

## Configuration and caveats

Outside the policy suite, each tool runs through its CLI, set up as a permissive agent workspace. The commands are in
`tool_argv` in `run.py`. The policy suite instead uses the adapters in `adapters/`, which embed the library APIs
(`policy_argv` in `run.py`).

- **gbash**: `gbash-extras` (adds awk and jq) with `--root WORK` (a read-only host directory under an in-memory
  overlay).
- **just-bash**: `--root WORK --allow-write` (overlay, writes kept in memory).
- **rshell**: `-p WORK:rw --mode remediation`, every builtin granted, `--timeout 10s`. This is the archived standalone
  repo (last commit 2026-11-03). Its CLI is documented as a development harness.
- **tinysandbox**: the Node binding, through `adapters/tinysandbox.mjs`, with WORK mounted at `/workspace` and a
  10 s wall limit. The binding ignores the `cwd` option, so the adapter prepends `cd /workspace`.

Other caveats:

- The environment is `LC_ALL=C`, `TZ=UTC`, and the fixture is set to 755/644 modes.
- Output that contains the sandbox's own paths (for example `/home/agent/project/...` from gbash `grep -r`) counts as
  a mismatch, because an agent sees it.
- Conformance compares stdout and exit code only; stderr wording is not compared.
- The security probes test the boundary of each tool's default configuration. They do not test how expressive its
  policy is, which the qualitative rubric covers.
