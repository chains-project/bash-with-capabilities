# Prior art

What exists for this project's goal (see `AGENTS.md`): a shell runtime that sandboxes AI agents with
capabilities, keeps bash syntax and semantics, and makes the capability policy declarative and provable.
Snapshot of 2026-11-17. The survey is not exhaustive, so "nothing combines X and Y" means "nothing found",
not "nothing exists".

## Summary

Prior work covers at most two of the three goals:

- Research capability shells (Plash, SHILL) have provable or least-authority policies, but not bash.
- Bash reimplementations for agents (gbash, just-bash, rshell, tinysandbox) are close to bash, but their policies are
  configuration, not an object one can reason about. rshell is the exception: it has a static checker, which it buys
  by dropping most of bash.
- OS-level sandboxes keep real bash, but they cannot see shell structure.

The open combination: SHILL-style capability contracts, over unmodified bash syntax, with a formal semantics in the
spirit of Smoosh, so that a policy can be checked before running.

## Research: capabilities and shells

- **Plash** (Mark Seaborn, ~2005): a "principle of least authority shell" with bash-like syntax. Naming a file as an
  argument grants the command access to that file. It is the closest in spirit to this project, and it is abandoned.
- **SHILL** (Moore, Dimoulas, Chong, OSDI 2014): a capability-safe scripting language. Each script carries a
  declarative contract on its capabilities, enforced through FreeBSD Capsicum. It has strong reasoning properties, but
  its syntax is Racket, not bash.
- **Smoosh** (Greenberg & Blatt, POPL 2020): an executable formal semantics of the POSIX shell, tested against the
  POSIX test suite. It offers a basis for proofs, but no capabilities.
- **CoLiS** (Jeannerod, Marché, Treinen et al.): symbolic execution of Debian maintainer scripts through an
  intermediate language with a formal semantics. It shows that static reasoning about real shell scripts is practical
  on a restricted subset.
- **Capsicum** (Watson et al., USENIX Security 2010): OS capability mode. SHILL is built on it.

## Bash reimplementations for agents

All four are in-process interpreters with their own builtin commands. None of them runs host binaries. They are
compared in [`bench/`](bench/README.md); the measured numbers are in `bench/results/`.

- **gbash** (<https://github.com/ewhauser/gbash>, Go, Apache-2.0, "alpha"):
  - Shell: an owned fork of the mvdan/sh parser, with an AST dump (`--dump-ast`). It is tested differentially against
    the Oils spec corpus (~2.5k cases) with pinned bash, dash, mksh and zsh.
  - Filesystem: in-memory, a host directory under an overlay, or mounts.
  - Policy: the Go interface `policy.Policy` (callbacks). The stock `policy.Static` allows everything when its lists
    are empty (`policy/policy.go:80-121`), so it is not default-deny inside the sandbox.
  - Limits: command, loop and glob budgets. Network: a curl allowlist by URL prefix.
  - No static policy check.
- **just-bash** (<https://github.com/vercel-labs/just-bash>, TypeScript, Apache-2.0, "beta", npm 3.6.1):
  - Shell: broad bash coverage, without `trap`. About 85 commands, including awk, sed, jq, sqlite3, and optional
    python3 and js running in WebAssembly.
  - Filesystem: in-memory, overlay or read-write.
  - Policy: an options object holding a command allowlist (all commands by default) and network URL prefixes (off by
    default), plus about 40 execution limits in `normal` and `hardened` profiles.
  - Static analysis: `CommandCollectorPlugin` collects literal command names only, so it misses `$cmd` and `eval`.
  - Has a threat model (`THREAT_MODEL.md`).
- **rshell** (<https://github.com/DataDog/rshell>, Go, Apache-2.0): archived on 2026-11-02 and moved to
  `DataDog/datadog-agent/pkg/rshell`.
  - Default-deny on every surface:
    - commands: namespaced grants such as `rshell:cat`;
    - paths: `AllowedPaths` with `:ro` or `:rw`;
    - environment: empty, the host's is not inherited;
    - writes: only in remediation mode;
    - systemd: grants per unit and action.
  - Grants are plain data (`RemotePolicy`). `Check` and `CheckRemote` give a static three-valued verdict per command
    site (allowed, denied or indeterminate) without running anything, and arguments are expanded only after the
    command is authorized.
  - The cost is a deliberately small subset of bash: no functions, arrays, arithmetic, `case` or `[[`.
  - It is the closest existing piece to the goal of a declarative, checkable policy.
- **tinysandbox** (<https://github.com/danthegoodman1/tinysandbox>, Rust with Node bindings, MIT/Apache-2.0, 0.9.0):
  - Filesystem: a virtual filesystem with quotas; its host-backed backend never follows symlinks (`O_NOFOLLOW`).
  - JavaScript and jq run in Wasmtime guests with no capabilities.
  - The shell is minimal: pipelines, `&&` and `||`, redirects, and 25 commands. `if` and `for` are not supported.
  - Policy: a command denylist and the choice of mounts.

### Benchmark findings (2026-11-17)

Full tables are in `bench/results/2026-11-17.md`, and the evidence per tool is in `bench/QUALITATIVE.md`.

- **Conformance**: the share of 137 scripts that match bash (stdout and exit code):
  - gbash: 95%;
  - just-bash: 91%;
  - rshell: 45%;
  - tinysandbox: 9%.

  The number that matters most for agents is *silent* mismatches: wrong output with no error.
  - gbash (6): `grep -r` and `xargs grep` print sandbox-absolute paths (`/home/agent/project/src/...`) where bash
    prints relative ones, and `${x:?}` returns exit code 127 instead of 1.
  - just-bash (6): `uniq -c` pads counts to width 4 instead of 7, which breaks `sort -k1nr`; `sort` and `ls`
    ignore `LC_ALL=C` ordering; `grep -r .` drops the `./` prefix.
  - rshell (3): ignores `set -u` and `set -C` (noclobber), so `>` silently overwrites a file.
  - tinysandbox (4): ignores `set -u`, and pads `wc` output.

  rshell and tinysandbox mostly fail *loudly* ("not supported", parse error), which is the safer failure mode.
- **Security**: all four block all 48 escape probes (read, write, exec, net and env outside the granted directory)
  in the configuration used here, so the boundary does not separate them. What does separate them is how expressive
  and how checkable the policy is (see the qualitative rubric).
- **Resource limits**:
  - gbash and just-bash stop loops, recursion, memory blow-up, the fork bomb and output floods with their own
    limits. Neither CLI applies a wall-clock deadline, so `sleep 100000` runs until killed. just-bash's library
    default is one hour.
  - rshell is contained by its timeout, and refuses most of the other probes up front because it does not support
    functions or `yes`, for example.
  - tinysandbox refuses all eight probes up front: it has no loops or functions.
- **Performance** (median over 5 runs, on tasks sized under every tool's default limits): startup is 13 ms for gbash
  and 7 ms for rshell, against 324 ms for just-bash and 183 ms for tinysandbox, which both start Node. just-bash is
  10–100× slower than bash on text processing over 3 MB. The default caps found along the way: gbash allows 10k
  commands and 8 MiB per file, rshell 5 MiB of `sort` input.

## Policy enforcement at the OS layer

These keep real bash, so they keep exact semantics, but their policy acts on system calls, not on shell structure.

- **agentsh** (<https://agentsh-website.pages.dev/>, Canyon Road, Apache-2.0): a shim replacing `/bin/sh` and
  `/bin/bash`. It applies a policy to file, network and process operations: allow, deny, ask a human, soft-delete or
  redirect. Rules match first-rule-wins.
- **Anthropic sandbox-runtime**, **OpenAI Codex sandbox** (bubblewrap, Landlock and seccomp on Linux, Seatbelt on
  macOS), **Firejail**, **landrun**: declarative file and network rules applied to the whole process tree.
- **Claude Code permission rules** (`Bash(git:*)`): allowlists by command prefix over parsed bash. They are coarse,
  and wrappers or `eval` defeat them.
- **`rbash`**: bash's restricted mode. It is well known to be easy to escape.

## Related tooling

- **Oils/OSH** (<https://oils.pub>): a bash-compatible shell with a large spec-test corpus, which gbash and just-bash
  reuse. It has no capabilities.
- **ShellCheck**: a static linter. It does not reason about policies.
- **mvdan/sh**: a Go bash parser and interpreter, used by rshell and forked by gbash.
