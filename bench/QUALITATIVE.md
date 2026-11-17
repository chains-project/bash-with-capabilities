# Qualitative comparison: bash reimplementations for AI agents

Snapshot read on 2026-11-17 at the revisions pinned in `setup.sh`. Paths are relative to each repo root (`bench/.tools/<repo>` after `./setup.sh`). "probe" = command actually run against the built CLI / installed npm package on this host.

## 1. Language, license, embedding API

- **gbash**: Go, Apache-2.0. Go library (`gbash.New`/`Runtime.Run`/`Session.Exec`), CLI, JSON-RPC server (`--server`), js/wasm build for browser/Node. Evidence: `LICENSE`, `README.md:46-53`, `README.md:231-241`.
- **rshell**: Go, Apache-2.0. Go library (`interp.New`/`Runner.Run`) is the product; CLI is "a development and local-validation tool, not a production security boundary". Evidence: `README.md:27-30`, `README.md:44-75`, `LICENSE`.
- **just-bash**: TypeScript, Apache-2.0. npm library (`new Bash().exec`), CLI `just-bash`, browser bundle, `Sandbox` drop-in for `@vercel/sandbox`. Evidence: `README.md` (monorepo, license badge), `packages/just-bash/package.json:1-30`, `packages/just-bash/README.md:581-648`.
- **tinysandbox**: Rust, MIT OR Apache-2.0. Rust crate (`Sandbox::builder()`), Node bindings via napi-rs (`@tinysandbox/tinysandbox`); no CLI. JS/jq run as Wasmtime guests. Evidence: `Cargo.toml:5-15`, `tinysandbox-node/Cargo.toml:14`, `README.md:13-45`.

## 2. Parser (own vs third-party), AST dump

- **gbash**: forked mvdan/sh, now owned in-tree (`internal/shell`, public `shell/syntax`). CLI `--dump-ast` emits typed JSON AST (probe confirmed). `-n` parses without executing. Evidence: `README.md:5`, `README.md:225-229`, `README.md:527`, `docs/AST_ROADMAP.md`.
- **rshell**: third-party `mvdan.cc/sh/v3 v3.14.1` parser plus a restricted-AST validator (`interp/validate.go`). No AST-dump CLI flag (not found in `rshell --help`); `interp.ParseScript` returns the mvdan AST to Go callers. Evidence: `go.mod:26`, `README.md:50`.
- **just-bash**: own hand-written TS parser (`src/parser/`, no external parser import). `parse` and `serialize` exported; AST transform plugin pipeline (parse → transform → re-serialize bash). Evidence: `packages/just-bash/src/index.ts:96,130`, `packages/just-bash/src/transform/README.md`.
- **tinysandbox**: own hand-rolled lexer/parser (`src/shell/{lex,parse}.rs`), public `tinysandbox::shell::parse` returning a `Program` AST (Rust `Debug`, no serde, no CLI dump). Evidence: `src/shell/parse.rs:8`, `README.md:215-216`, `tests/shell_golden.rs:1-4`.

## 3. Shell feature coverage (functions, arrays, arithmetic, case, [[ ]], here-docs, process substitution, traps)

Probe script: `f(){ echo $1; }; a=(1 2); f ${a[1]}; echo $((2+3)); case …; [[ a == a ]]; cat <(echo ps); trap "echo t" EXIT`.
- **gbash**: all eight work (probe printed `2 5 c dd ps t`); docs claim functions, indexed + associative arrays, but "intentionally not a full Bash reimplementation" (no job control). Evidence: `README.md:460-473`, `README.md:430`.
- **rshell**: deliberately minimal POSIX subset. Here-docs ✅; arithmetic, arrays, `case`, functions, `[[ ]]`, `(( ))`, process substitution, positional params, `${var:-…}` all ❌ (rejected before execution, exit 2). No `trap` builtin listed. Evidence: `SHELL_FEATURES.md:156-160`, `:175-178`, `:186-187`, `:239`, `:255-257`.
- **just-bash**: functions, arrays, arithmetic, case, `[[ ]]`, process substitution, here-docs work (probe); `trap` fails (`trap: command not found`) and is listed as a known limitation (job/process control). README's own feature list is short and understates coverage. Evidence: `packages/just-bash/README.md:119-134`, `packages/just-bash/src/spec-tests/bash/KNOWN_LIMITATIONS.md:379-386`.
- **tinysandbox**: only pipelines, `&&`/`||`/`;`, redirects, quoting, `$VAR`, assignments. Globs, `$(...)`, heredocs, subshells, `&` rejected with positioned parse errors. Probe: functions/arrays/case/arith/procsubst → parse error; `if`/`for`/`[[` → *"if: command not found"* (control-flow keywords are not even recognized). Evidence: `README.md:213-228`; probe.

## 4. Command set; awk/sed/jq/find/xargs; host binaries

- **gbash**: 90+ registry commands (129 virtual stubs in `/usr/bin` in default CLI, probe), many ported from uutils. find ✅, sed ✅, xargs ✅ (registry); awk/jq/yq/sqlite3 only in `gbash-extras` (contrib, goawk/gojq). Never runs host binaries; awk `system()` is routed back into the sandbox (probe: `system("id")` → virtual `uid=1000(agent)`). Evidence: `README.md:36-37`, `README.md:412-446`, `contrib/awk/awk.go:479-534`.
- **rshell**: ~49 builtins (one dir per command in `builtins/`), incl. awk, sed, jq (own jq 1.8 subset), find, xargs, plus ops tools (ps, ss, ip, ping, journalctl, systemctl, lsof…). No external-command executor; even `--allow-all-commands` rejects `/usr/bin/id` (probe: "unknown command"). Evidence: `SHELL_FEATURES.md:94-147`, `SHELL_FEATURES.md:251`, `README.md:224`.
- **just-bash**: 85 names in `CommandName` union (99 entries in `src/commands/`), incl. awk, sed, jq, find, xargs, yq, sqlite3, rg, tar; optional python3 (CPython-wasm) and js-exec (QuickJS). No host binaries (probe: `id`, `/usr/bin/id` not found); "Use Vercel Sandbox if you need … arbitrary binary execution". Evidence: `packages/just-bash/src/commands/registry.ts:20-105`, `packages/just-bash/README.md:83-117`, `:692-723`.
- **tinysandbox**: 25 commands (`ls /bin` probe): cat ls cp mv rm mkdir touch stat which pwd cd grep head tail sort uniq wc sed echo true false export unset jq js. No awk, find, xargs. jq = jaq in Wasmtime. No host binaries ("no fork/exec"). Evidence: `README.md:230-245`, `README.md:247-251`, `README.md:109-111`.

## 5. Filesystem model, containment, symlinks

- **gbash**: in-memory by default; options for seeded memory, read-only host dir under in-memory overlay (`WithWorkspace`), mountable namespace, read-write host dir, custom backends (SQLite, AgentFS examples). Path checks via `policy.CheckPath`; `SymlinkMode` default `deny`, symlink-hop limit 40. Evidence: `README.md:254-322`, `policy/policy.go:26-31,93-96`, `policy/pathcheck.go:12-16`, `THREAT_MODEL.md:25,49`.
- **rshell**: host-backed only (no VFS); access restricted to `AllowedPaths` roots, each `:ro`/`:rw`, implemented with Go `os.Root` (openat-style containment); explicit symlink-component and hard-link checks on writes. Some inspection builtins (ps, ss, ip route, lsof) read `/proc` bypassing `AllowedPaths` by design. Evidence: `allowedpaths/sandbox.go:7,46-49`, `allowedpaths/check.go:27-79`, `README.md:189-213`, `SHELL_FEATURES.md:113,118,120`.
- **just-bash**: `InMemoryFs` default; `OverlayFs` (copy-on-write over a real dir), `ReadWriteFs` (real dir), `MountableFs`. Symlinks blocked by default (`allowSymlinks: false`) in Overlay/ReadWrite; ReadWriteFs isolates hard-linked files by copy; documented TOCTOU limitation against concurrent host mutation. Evidence: `packages/just-bash/README.md:199-337`, `packages/just-bash/src/fs/overlay-fs/overlay-fs.ts:7,123,207`, `packages/just-bash/src/fs/read-write-fs/read-write-fs.ts:7,86`.
- **tinysandbox**: read-only root mount namespace with top-level mounts (`InMemoryVfs`, `LocalVfs` on Unix, `S3Vfs`, BYO `Vfs` trait); per-mount quotas. `LocalVfs`: `..` clamped lexically, symlinks never followed (`O_NOFOLLOW`), special files refused. Evidence: `README.md:750-813`, `README.md:1075+`.

## 6. Policy / capability model

- **gbash**: `policy.Policy` Go interface (`AllowCommand`, `AllowBuiltin`, `AllowPath(action,target)`, `Limits`, `SymlinkMode`) — callbacks; stock `policy.Static` built from a plain `Config` struct (command/builtin allowlists, read/write roots, limits). NOT default-deny inside the sandbox: empty allowlist = all allowed, empty roots = `/`. Network via `WithHTTPAccess`/`WithNetwork` URL prefixes. Code options only; CLI has no policy flags (only `--root`, `--readwrite-root`, `--inherit-env`). Evidence: `policy/policy.go:54-69,80-121`, `options.go:115,204,234`, `gbash --help`.
- **rshell**: default-deny on every surface: commands (`AllowedCommands`, namespaced `rshell:cat`), paths (`AllowedPaths` with `:ro`/`:rw`), env (empty, host not inherited), write mode (`ModeRemediation`), systemd units×actions, sudo-elevatable commands. Expressed as Go functional options, CLI flags, and a plain data struct `RemotePolicy`; integration decodes grants from signed protobuf tasks. Mostly declarative data (no callbacks in `RemotePolicy`). Evidence: `README.md:187-197`, `interp/api.go:925-940`, `interp/check_remote.go:28-45`, `README.md:157-168`.
- **just-bash**: options object to `new Bash({...})`: `commands` allowlist (default: all built-ins), choice of FS backend, `network` (URL prefixes, methods, header transforms), `python`/`javascript` toggles, `executionLimits`/profile. Mostly JSON-like data, but custom commands, `invokeTool`, `fetch`, lazy files are code callbacks. Not default-deny for commands; default-deny for network/python/js. Evidence: `packages/just-bash/src/Bash.ts:148-196`, `packages/just-bash/README.md:340-407,661-691`.
- **tinysandbox**: builder/options: `without_command` / `disabledCommands` (denylist; default all 25 enabled), `mounts` (data: type/root/quota/readOnly for S3), `limits`, `env`, `cwd`, `fetch` handler (callback), JS host globals (callbacks). Node options are mostly plain data except callbacks. No per-path rules beyond mount selection. Evidence: `src/sandbox/mod.rs:1013-1187`, `tinysandbox-node/index.d.ts:80-133`, `README.md:293`.

## 7. Static analysis / pre-execution checking

- **gbash**: no policy pre-check found. Only parse-only (`-n`, `--dump-ast`) and a runtime observer API (`shell/analysis`, "read-only semantic observation hooks for … execution"), i.e. dynamic, not static. Evidence: `shell/analysis/doc.go:1-8`, `options.go:276`.
- **rshell**: `Runner.Check` (local) and `CheckRemote` (pure, no FS/env access) return `allowed`/`denied`/`indeterminate` per command site with line/col. Sound-ish direction: every syntactic branch checked, loops once, denial wins; assignments in branches/loops, globs, `$(...)`, paths after `cd`, awk/sed/jq programs, `find` expressions, xargs input → `indeterminate`. Explicitly "authorization preview, not an execution-success guarantee"; Run re-enforces. Also expands only the command name before authorizing, so denied commands can't trigger substitutions in args. Plus a separate Go-level static import/symbol allowlist (`analysis/`) on the interpreter's own code. Evidence: `README.md:77-185`, `SHELL_FEATURES.md:8-60`, `interp/check.go:110`, `interp/check_remote.go:74`, `README.md:228`, `analysis/README.md:1-12`.
- **just-bash**: `CommandCollectorPlugin` lists command names from the AST before execution, but only literal names (`word.parts.length === 1 && Literal`); `$cmd`, `eval`, `bash -c "$x"` silently omitted → unsound as a policy check, no verdict concept. Evidence: `packages/just-bash/src/transform/plugins/command-collector.ts:52-60,171`.
- **tinysandbox**: not found (parse errors are reported before execution, nothing policy-related).

## 8. Resource limits

- **gbash**: defaults: 10k commands, 10k loop iterations, 100k glob ops, 100k brace words, substitution depth 50, function depth 1000, stdout/stderr 1 MiB, file 8 MiB, variable 32 MiB / total 256 MiB; per-request `Timeout`; `Unlimited=-1` per field. Evidence: `internal/runtime/runtime.go:116-130`, `policy/policy.go:36-52`, `execution_types.go:28`.
- **rshell**: whole-run timeout (`MaxExecutionTime`, `--timeout`); source ≤5 MiB, nesting ≤5000; ≤16,384 expanded args / 10 MiB per command, 64 MiB expanded text per Run; vars 1 MiB each, ~1 MiB total; heredoc 10 MiB; per-builtin caps (sed 256 MiB buffers, du depth 256…). No loop-iteration cap found (timeout only). Evidence: `README.md:230-232`, `SHELL_FEATURES.md:233-234,247`, `interp/api.go:497-506`.
- **just-bash**: ~40 limits with `normal` (default) and `hardened` profiles: call depth, command count, loop/awk/sed/jq iterations, source bytes, output size, FS bytes, archive/db bytes, wall-clock (`maxExecutionTimeMs`, default 1 h in normal), sqlite/python/js timeouts, QuickJS 64 MB memory. Evidence: `packages/just-bash/src/limits.ts:164-210`, `packages/just-bash/README.md:661-691`.
- **tinysandbox**: `Limits`: wall time 30 s, stdout/stderr 1 MiB, 1,024 command stages, shell input 1 MiB, host input 8 MiB, open files, path depth, jq/JS Wasm memory, fetch response bytes; process-wide `Pools` (JS workers, jq evals, handles); Wasmtime epoch interruption for JS/jq. No loop cap needed (no loops). Evidence: `src/sandbox/command.rs:120-148,251-259`, `README.md:1206-1268`.

## 9. Network

- **gbash**: off by default; enabling registers `curl`. Allowlist = URL prefixes (origin + path-boundary aware), methods, max response bytes, `DenyPrivateRanges`; or inject custom client. Evidence: `README.md:341-392`.
- **rshell**: no HTTP client. `ping` (ICMP to arbitrary host, gated only by the command grant; flood/broadcast blocked) and read-only socket/interface inspection (`ss`, `ip`). No host allowlist found. Evidence: `SHELL_FEATURES.md:112-114,120,125`.
- **just-bash**: off by default (`curl` absent unless configured). Allowlist: exact origin + path prefix, methods (GET/HEAD default), redirect re-check, header-injection transforms for secrets, `denyPrivateRanges`, or `dangerouslyAllowFullInternetAccess`. Evidence: `packages/just-bash/README.md:340-407`, `packages/just-bash/src/network/fetch.ts:124-181`.
- **tinysandbox**: no network in the shell; only JS guest `fetch()`, entirely delegated to a host callback (none → rejects). Granularity = whatever the host callback implements. Evidence: `README.md:684-694`.

## 10. Formal artifacts (threat model, spec, fuzzing, differential testing, test-suite size)

- **gbash**: `THREAT_MODEL.md` (192 lines, threat table TM-xxx), `SPEC.md` ("Draft v0.1", 962 lines), `SECURITY.md`. 70 Go `Fuzz*` functions. Differential: vendored Oils spec corpus (123 files, ~2,546 `####` cases) run against pinned bash/dash/mksh/zsh oracles via Nix (`make conformance-test`, gated by `GBASH_RUN_CONFORMANCE=1`); manifest has 321 xfail + 25 skip. Also GNU coreutils compatibility report. Evidence: `internal/conformance/README.md`, `internal/conformance/manifest.json`, `README.md:37,515`.
- **rshell**: no THREAT_MODEL file; `SECURITY.md`, `docs/RULES.md` (builtin security rules), `docs/PRIVILEGED_HELPER.md`; many `*_vuln_hunt_test.go`/`*_pentest_test.go`. 119 `Fuzz*` functions in 40 files. 3,448 YAML scenarios; differential vs real bash in Docker `debian:bookworm-slim` (opt-in `RSHELL_BASH_TEST=1`), 1,051 scenarios marked `skip_assert_against_bash`. Evidence: `tests/scenarios_test.go:34,43,458-515`, `tests/scenarios/`, `interp/*_vuln_hunt_test.go`.
- **just-bash**: `THREAT_MODEL.md` (400 lines: actors, trust boundaries, attack surface, known gaps). Grammar/flag/malformed fuzzers with sandbox and DoS oracles (`src/security/fuzzing/`). Oils spec tests: 136 files, ~2,728 cases (bash/awk/grep/jq/sed). Differential: 57 comparison fixture files recorded from real bash, replayed in CI (`RECORD_FIXTURES=1` to re-record). Evidence: `THREAT_MODEL.md`, `packages/just-bash/src/spec-tests/bash/README.md`, `packages/just-bash/src/comparison-tests/README.md:1-10`.
- **tinysandbox**: no threat model / spec doc found. proptest-based property tests (`tests/shell_proptest.rs`, `tests/vfs_proptest.rs`), VFS conformance suite (also exported as `runConformance`), 184 `#[test]`/proptest entries in `tests/`. Differential: README claims "verified against the real tools in the test suite", but the shell golden corpus (36 cases) says "manually checked against bash" — no automated bash oracle found. Evidence: `README.md:113-115`, `tests/fixtures/shell_golden.txt:1-4`, `tests/`.

## 11. Maturity

All four clones are shallow (depth 1), so `git shortlog -sn | wc -l` = 1 for each and is meaningless.
- **gbash**: "alpha software"; SPEC "Draft v0.1". Last commit Fri Oct 23 2026. Evidence: `README.md:7-8`, `SPEC.md:3`.
- **rshell**: archived 2026-11-02, moved to `DataDog/datadog-agent/pkg/rshell`; last commit Tue Nov 3 2026 (archival notice). Production-integrated at Datadog (Private Action Runner, Landlock+seccomp helper). Evidence: `README.md:7-22`, `README.md:215-222`.
- **just-bash**: "beta software", npm 3.6.1. Last commit Mon Nov 16 2026. Evidence: `packages/just-bash/README.md:7`, `packages/just-bash/package.json:3`.
- **tinysandbox**: v0.9.0, no explicit status label found. Last commit Wed Oct 21 2026. Evidence: `Cargo.toml:7`.

## 12. Relevance to our goal (OPINION)

- **gbash**: best bash fidelity (owned mvdan fork, Oils differential against 4 shells, AST dump) and a clean `Policy` seam, but policy is an imperative Go interface, permissive by default and without any static checker. Good substrate for semantics; capability layer would have to be rebuilt.
- **rshell**: closest to the capability/provability goal: default-deny, data-shaped grants (`RemotePolicy`), three-valued static `CheckRemote`, authorize-before-expand ordering, Landlock derivation from the same grants. Price: it buys analyzability by amputating bash (no functions, arrays, arithmetic, case, `[[`), so it fails "bash-identical"; and it is now archived upstream.
- **just-bash**: broad bash coverage and the richest limits/network config, but command policy is just an optional name allowlist and its only static tool (`CommandCollectorPlugin`) is unsound; security rests on JS-realm hardening rather than declared capabilities.
- **tinysandbox**: strongest isolation story for embedded interpreters (Wasmtime for JS/jq, `O_NOFOLLOW` VFS, per-tenant pools) but the shell is not a shell (no `if`/`for`); irrelevant for semantics, possibly useful as a VFS/limits reference.
