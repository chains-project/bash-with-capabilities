# Benchmark policy format

The `policy` suite states each scenario once, in one tool-neutral format. A per-tool adapter (`adapters/`)
translates that policy into the tool's own configuration. If a tool cannot express the policy, its adapter exits
with code 99 and prints a reason starting with `unsupported:`; the report shows these as `n/a (reason)`.

## Format

A JSON object. Every key is optional; a missing key leaves that dimension unconstrained.

```json
{
  "commands": ["cat", "grep"],
  "fs": {"src": "ro", "out": "rw"},
  "net": ["http://127.0.0.1:8080/allowed/"],
  "env": {"VISIBLE": "visible-value"}
}
```

- `commands`: the utilities that may run. Shell builtins (`POLICY_BUILTINS` in `run.py`: `echo`, `cd`, `test`, `eval`,
  `command`, ...) are always added. Any other name is denied, however it is reached: by a variable, `eval`, a pipeline,
  a subshell, a function, `xargs`, `find -exec`, `bash -c`, `env`, or an absolute path.
  - Missing key: every command the tool has.
- `fs`: paths relative to the working directory, each mapped to `ro` or `rw`. Anything not granted can be neither
  read nor written, including through `..`, globs, symlinks, `cd`, or an absolute host path. The working directory is
  the host directory given to the adapter, and effects are checked there.
  - Missing key: the whole working directory is `rw`.
- `net`: allowed URL prefixes. Any other request is denied, including `..` tricks, a prefix with no `/` boundary
  (`/allowed` must not match `/allowedX`), another host name, redirects, and raw `/dev/tcp`.
  - Missing key: no network.
- `env`: the complete environment the script sees. Host variables do not leak.
  - Missing key: the tool's default environment, still without host variables.

## Probes

`cases/policy/<scenario>.sh` holds a `# policy:` header line with the JSON above, followed by probes:

```
#### allow:NAME CHECK      the effect must happen; if it does not, the probe is over-denied
#### deny:NAME CHECK       the effect must not happen; if it does, the probe is VIOLATED
```

`CHECK` is observed on the host, never taken from the tool's own report:

- `stdout~TEXT`: TEXT appears in stdout or stderr. Markers are built so the script text cannot contain them: the
  script says `SED&RAN`, and only a sed that actually ran produces `SEDfigRAN`.
- `host+PATH`: PATH was created.
- `host-PATH`: PATH was removed.
- `hostchg PATH`: PATH's content changed.
- `net~PATH[@HOST]`: the harness HTTP listener received a request for PATH, optionally also with that Host header.

The harness substitutes these placeholders:

- `@PORT@`: the listener's port;
- `@TOKEN@`: a per-run secret, written to `secrets/key.txt`;
- `@ENVTOKEN@`: a per-run secret in the host environment, as `HIDDEN_TOKEN`;
- `@WORK@`: the absolute path of the host working directory.

## Static check

When a tool can judge a script without running it, the harness also asks it for a verdict, recorded per probe as
allowed, denied or indeterminate. Today only rshell can (`Runner.Check`). The ideal is every deny probe judged
"denied" and every allow probe judged "allowed".

## Controls

`run.py selfcheck` validates the suite with two controls:

- `bash`, which ignores the policy (the known positive): every effect must be observed;
- `null`, which runs nothing (the known negative): no effect may be observed.
