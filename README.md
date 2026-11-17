# bash-with-capabilities

This project studies shells that sandbox AI agents with **capabilities**. The goal (see [`AGENTS.md`](AGENTS.md)) is a
shell runtime with three properties:

- bash syntax and semantics, so that off-the-shelf LLMs use it correctly;
- a declarative capability policy restricting what an agent can do;
- a policy one can reason about and, ideally, prove things about.

The repository holds a survey of prior art and a reproducible benchmark of the existing bash reimplementations for
agents.

## Main take-away: gbash is the best

[gbash](https://github.com/ewhauser/gbash) (Go) is the best bash reimplementation for agents in our benchmark of
2026-11-17. The others are [just-bash](https://github.com/vercel-labs/just-bash) (Vercel),
[rshell](https://github.com/DataDog/rshell) (Datadog) and
[tinysandbox](https://github.com/danthegoodman1/tinysandbox).

- 🎯 **Closest to bash.**
  - 131/137 conformance scripts match GNU bash exactly, against 126 for just-bash, 63 for rshell and 13 for
    tinysandbox. A script counts as a match only if both its stdout and exit code equal bash's.
  - gbash's remaining errors have two causes: `grep -r` prints sandbox-absolute paths, and `${x:?}` returns the
    wrong exit code.
- 🔐 **Enforces every policy we could state.** gbash and just-bash are the only two that can express all 5
  strict-policy scenarios:
  - a command allowlist, with 17 bypass attempts;
  - read-only and read-write path grants;
  - a read-only workspace;
  - a URL allowlist;
  - an environment allowlist.

  All four tools block everything they can express.
- ⚡ **Fast and light.**
  - Startup is 13 ms, against 324 ms for just-bash and 183 ms for tinysandbox.
  - On text processing gbash is 5–80× faster than just-bash, with a smaller memory footprint.
- 🧯 **Contains runaway scripts** (loops, recursion, memory blow-up, fork bomb, output floods) with its own limits.

Caveats:

- gbash describes itself as alpha software.
- Its stock policy treats an empty list as "allow everything".
- Its command-line tool applies no wall-clock limit by default.
- Its policy is a Go interface (callbacks) with no static checker. rshell is the only tool that checks a policy
  before running (`Runner.Check`), but it supports only a small subset of bash.

## Contents

- [`PRIOR-ART.md`](PRIOR-ART.md): a survey covering:
  - research capability shells (Plash, SHILL) and formal shell semantics (Smoosh, CoLiS);
  - bash reimplementations for agents;
  - OS-level enforcers (agentsh, sandbox-runtime, …);
  - the detailed benchmark findings.
- [`bench/`](bench/README.md): the benchmark.
  - Six suites, all compared against GNU bash:
    - conformance (137 scripts);
    - security escapes (48 probes);
    - strict policies (68 probes, [`bench/POLICY.md`](bench/POLICY.md));
    - resource exhaustion (8 probes);
    - performance (9 tasks);
    - a qualitative rubric with evidence ([`bench/QUALITATIVE.md`](bench/QUALITATIVE.md)).
  - Results: [`bench/results/2026-11-17.md`](bench/results/2026-11-17.md).

## Reproduce

```bash
cd bench
./setup.sh             # fetch and build the pinned tool versions (git, go, node, npm)
./run.py selfcheck     # validate the instruments: real bash is the known positive, a no-op the known negative
./run.py all --json results/$(date +%F).json --report results/$(date +%F).md
```

The harness needs Linux and Python 3 (standard library only). The resource suite also needs `systemd-run --user` and
`prlimit`.
