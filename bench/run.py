#!/usr/bin/env python3
"""Benchmark bash reimplementations for AI agents against GNU bash.

Suites:
  conformance  same script, same fixture: stdout and exit code compared with real bash (the oracle).
               Mismatches are split into "loud" (the shell signalled a problem: stderr or a different
               non-zero exit) and "silent" (wrong output, no signal) -- silent ones mislead agents.
  security     escape probes (read/write/exec/net/env outside the granted workdir), detected on the host.
  resource     exhaustion probes run in a systemd scope; "contained" = the shell stopped itself.
  perf         wall time (median of N) and peak RSS on common tasks; output also checked against bash.

Instrument controls: `bash` must score 100% conformance and escape every probe it can (known positive);
`null` (runs nothing) must block everything (known negative). Run `run.py selfcheck` to verify both.

Usage: run.py [conformance|security|resource|perf|all|selfcheck] [--tools a,b] [--only SUBSTR]
              [--json OUT] [--report OUT.md] [-n REPEATS] [-j JOBS]
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import os
import platform
import re
import secrets
import shutil
import socket
import statistics
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS_DIR = HERE / ".tools"
BIN = TOOLS_DIR / "bin"
CASES = HERE / "cases"
FIXTURE = HERE / "fixture"
TIMEOUT = 20.0  # harness deadline per run (s); shells are configured with 10 s where they support it
OUT_CAP = 50 * 1024 * 1024
FSIZE_CAP = 200 * 1024 * 1024
MEM_CAP = "2G"

RSHELL_CMDS = ["[", "awk", "break", "cat", "cd", "continue", "cut", "df", "du", "echo", "exit", "false", "find", "free", "grep", "head", "ip", "jq", "logrotate", "ls", "lsof", "ping", "pmap", "printf", "ps", "pwd", "read", "rm", "sed", "sha256sum", "sort", "ss", "stat", "strings", "tail", "tee", "test", "tr", "true", "truncate", "uname", "uniq", "uptime", "vmstat", "wc", "xargs", "help"]

BASE_ENV = {"PATH": "/usr/local/bin:/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC", "HOME": "/nonexistent"}


def tool_argv(tool: str, work: Path, script: str) -> list[str]:
    """Command line running `script` with `work` as the granted, writable working directory."""
    if tool == "bash":
        return ["bash", "--norc", "--noprofile", "-c", script]
    if tool == "gbash":
        return [str(BIN / "gbash-extras"), "--root", str(work), "--cwd", "/home/agent/project", "-c", script]
    if tool == "just-bash":
        return [str(TOOLS_DIR / "jb/node_modules/.bin/just-bash"), "--root", str(work), "--allow-write", "-c", script]
    if tool == "rshell":
        return [str(BIN / "rshell"), "-p", f"{work}:rw", "--mode", "remediation", "--timeout", "10s",
                "--allowed-commands", ",".join("rshell:" + c for c in RSHELL_CMDS), "-c", script]
    if tool == "tinysandbox":
        return ["node", str(HERE / "adapters/tinysandbox.mjs"), str(work), script]
    if tool == "null":
        return ["true"]
    raise SystemExit(f"unknown tool {tool}")


ALL_TOOLS = ["bash", "gbash", "just-bash", "rshell", "tinysandbox"]


@dataclass
class Case:
    suite: str
    group: str
    name: str
    script: str

    @property
    def id(self) -> str:
        return f"{self.group}/{self.name}"


def load_cases(suite: str) -> list[Case]:
    out: list[Case] = []
    for f in sorted((CASES / suite).glob("*.sh")):
        name, buf = None, []
        for line in f.read_text().splitlines(keepends=True) + ["#### \n"]:
            if line.startswith("#### "):
                if name:
                    out.append(Case(suite, f.stem, name, "".join(buf).rstrip("\n") + "\n"))
                name, buf = line[5:].strip(), []
            elif name is not None:
                buf.append(line)
    return out


@dataclass
class Run:
    stdout: bytes
    stderr: bytes
    exit: int | None  # None = killed by the harness deadline
    wall: float
    maxrss_kb: int
    signal: int | None = None
    extra: dict = field(default_factory=dict)


def execute(argv: list[str], cwd: Path, env: dict, sandboxed: bool = False, timeout: float = TIMEOUT) -> Run:
    """Run argv with stdout/stderr to files, a deadline, and peak RSS measured by GNU time.

    Peak RSS comes from /usr/bin/time, not from wait4: a child forked from this Python process
    reports Python's own RSS as its floor. When sandboxed, the command runs in a systemd user scope
    (memory, task limits) under prlimit (file size limit); `env -i` then restores the clean env.
    """
    with tempfile.TemporaryFile() as fo, tempfile.TemporaryFile() as fe, tempfile.NamedTemporaryFile("r") as ft:
        argv = ["/usr/bin/time", "-f", "%M", "-o", ft.name] + argv
        run_env = env
        if sandboxed:
            argv = (["systemd-run", "--user", "--scope", "-q", "-p", f"MemoryMax={MEM_CAP}", "-p", "MemorySwapMax=0",
                     "-p", "TasksMax=256", "prlimit", f"--fsize={FSIZE_CAP}", "--", "env", "-i"]
                    + [f"{k}={v}" for k, v in env.items()] + argv)
            run_env = {**env, **{k: os.environ[k] for k in ("XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS")
                                 if k in os.environ}}
        t0 = time.monotonic()
        p = subprocess.Popen(argv, cwd=cwd, env=run_env, stdin=subprocess.DEVNULL, stdout=fo, stderr=fe,
                             start_new_session=True)
        killed = False
        while True:
            pid, status, _ = os.wait4(p.pid, os.WNOHANG)
            if pid:
                break
            if time.monotonic() - t0 > timeout:
                killed = True
                try:
                    os.killpg(p.pid, 9)
                except ProcessLookupError:
                    pass
                _, status, _ = os.wait4(p.pid, 0)
                break
            time.sleep(0.002)
        wall = time.monotonic() - t0
        p.returncode = 0  # reaped by wait4; keep Popen from complaining
        if not killed:  # kill leftovers (backgrounded children) of the session
            try:
                os.killpg(p.pid, 9)
            except (ProcessLookupError, PermissionError):
                pass
        fo.seek(0)
        fe.seek(0)
        out, err = fo.read(OUT_CAP + 1), fe.read(OUT_CAP + 1)
        tail = ft.read().strip().splitlines()
    if sandboxed and b"Failed to" in err[:300] and b"bus" in err[:300]:
        raise SystemExit(f"systemd-run could not create a scope: {err[:300]!r}")
    # GNU time prefixes "Command terminated by signal N" / "Command exited with non-zero status N".
    rss = int(tail[-1]) if tail and tail[-1].isdigit() else -1
    sig = next((int(l.rsplit(" ", 1)[1]) for l in tail if l.startswith("Command terminated by signal")), None)
    if os.WIFSIGNALED(status):
        sig = os.WTERMSIG(status)
    code = None if killed else (128 + sig if sig else os.WEXITSTATUS(status))
    return Run(out, err, code, wall, rss, sig)


def make_env(token_env: str = "") -> dict:
    env = dict(BASE_ENV)
    env["HOST_SECRET_ENV"] = token_env or "not-a-secret"
    return env


def new_workspace(with_links: bool = False) -> tuple[Path, Path, Path, str]:
    """root/{work,outside/secret.txt}; returns (root, work, outside, token)."""
    root = Path(tempfile.mkdtemp(prefix="shbench-"))
    work, outside = root / "work", root / "outside"
    shutil.copytree(FIXTURE, work)
    for p in [work, *work.rglob("*")]:  # normalise: the user's umask must not change results
        p.chmod(0o755 if p.is_dir() else 0o644)
    outside.mkdir()
    token = "TOKEN-" + secrets.token_hex(8)
    (outside / "secret.txt").write_text(token + "\n")
    if with_links:
        (work / "link_rel").symlink_to("../outside/secret.txt")
        (work / "link_abs").symlink_to(outside / "secret.txt")
    return root, work, outside, token


def snapshot(d: Path) -> dict[str, tuple[int, float]]:
    """Listing of root and outside/ (not work/), to detect writes outside the grant."""
    res = {}
    for p in [d, *d.glob("*"), *(d / "outside").rglob("*")]:
        if p == d / "work":
            continue
        st = p.lstat()
        res[str(p.relative_to(d))] = (st.st_size, st.st_mtime_ns, st.st_ino)
    return res


# ---------------------------------------------------------------- conformance

def classify(ref: Run, got: Run) -> str:
    if got.exit is None:
        return "timeout"
    if got.stdout == ref.stdout and got.exit == ref.exit:
        return "pass"
    signalled = (got.exit != ref.exit and got.exit != 0) or (got.stderr.strip() and not ref.stderr.strip())
    return "loud" if signalled else "silent"


def run_one(tool: str, script: str, with_links: bool = False, token_env: str = "") -> tuple[Run, Path, str]:
    root, work, _, token = new_workspace(with_links)
    r = execute(tool_argv(tool, work, script), work, make_env(token_env))
    return r, root, token


def suite_conformance(tools: list[str], only: str, jobs: int) -> list[dict]:
    cases = [c for c in load_cases("conformance") if only in c.id]

    def one(c: Case) -> list[dict]:
        ref, rroot, _ = run_one("bash", c.script)
        shutil.rmtree(rroot)
        rows = []
        for t in tools:
            got, root, _ = run_one(t, c.script)
            shutil.rmtree(root)
            rows.append({"suite": "conformance", "case": c.id, "tool": t, "verdict": classify(ref, got),
                         "exit": got.exit, "ref_exit": ref.exit, "wall": round(got.wall, 4),
                         "stdout": got.stdout.decode(errors="replace")[:2000],
                         "ref_stdout": ref.stdout.decode(errors="replace")[:2000],
                         "stderr": got.stderr.decode(errors="replace")[:500]})
        return rows

    with cf.ThreadPoolExecutor(jobs) as ex:
        return [r for rows in ex.map(one, cases) for r in rows]


# ---------------------------------------------------------------- security

class Listener:
    def __init__(self) -> None:
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(16)
        self.sock.settimeout(0.2)
        self.port = self.sock.getsockname()[1]
        self.hits = 0
        self._stop = False
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self) -> None:
        while not self._stop:
            try:
                c, _ = self.sock.accept()
                self.hits += 1
                c.close()
            except OSError:
                pass

    def close(self) -> None:
        self._stop = True
        self.sock.close()


def suite_security(tools: list[str], only: str, jobs: int) -> list[dict]:
    cases = [c for c in load_cases("security") if only in c.id]

    def one(arg: tuple[Case, str]) -> dict:
        c, t = arg
        kind = c.name.split("-")[0]
        root, work, outside, token = new_workspace(with_links=True)
        env_token = "ENVTOKEN-" + secrets.token_hex(8)
        lst = Listener()
        script = (c.script.replace("@SECRET@", str(outside / "secret.txt"))
                  .replace("@OUTSIDE@", str(outside)).replace("@PORT@", str(lst.port)))
        before = snapshot(root)
        r = execute(tool_argv(t, work, script), work, make_env(env_token))
        time.sleep(0.05)
        lst.close()
        after = snapshot(root)
        text = r.stdout + r.stderr
        if kind == "read":
            escaped = token.encode() in text
        elif kind == "env":
            escaped = env_token.encode() in text
        elif kind in ("write", "exec"):
            escaped = before != after
        elif kind == "net":
            escaped = lst.hits > 0
        else:
            raise SystemExit(f"bad kind in {c.id}")
        shutil.rmtree(root, ignore_errors=True)
        return {"suite": "security", "case": c.id, "kind": kind, "tool": t,
                "verdict": "ESCAPED" if escaped else "blocked", "exit": r.exit,
                "stderr": r.stderr.decode(errors="replace")[:300]}

    with cf.ThreadPoolExecutor(jobs) as ex:
        return list(ex.map(one, [(c, t) for c in cases for t in tools]))


# ---------------------------------------------------------------- resource

def dir_bytes(d: Path) -> int:
    return sum(p.lstat().st_size for p in d.rglob("*"))


REFUSAL = re.compile(r"not supported|unsupported|parse error|command not found|command not allowed|"
                     r"not allowed|permission denied", re.IGNORECASE)


def resource_verdict(row: dict) -> dict:
    """contained = a limit of the shell stopped the probe; refused = the shell rejected the syntax or command
    up front, so no limit was exercised; NOT contained = a harness cap or deadline had to stop it."""
    why = []
    if row["exit"] is None:
        why.append("deadline")
    sig = row.get("signal") or (row["exit"] - 128 if row["exit"] and row["exit"] > 128 else None)
    if sig:
        why.append(f"signal {sig}")
    if row["maxrss_mib"] > 1500:
        why.append(f"rss {row['maxrss_mib']} MiB")
    if row["output_bytes"] >= FSIZE_CAP * 0.9:
        why.append("output cap")
    if row["disk_bytes"] >= FSIZE_CAP * 0.9:
        why.append("disk cap")
    if why:
        verdict = "NOT contained"
    elif REFUSAL.search(row["stderr"]) and row["wall"] < 1.0 and row["exit"] != 0 or (
            row["exit"] == 0 and "command not allowed" in row["stderr"]):
        verdict, why = "refused", [row["stderr"].strip().splitlines()[-1][:60] if row["stderr"].strip() else ""]
    else:
        verdict = "contained"
    return {**row, "verdict": verdict, "why": ", ".join(why)}


def suite_resource(tools: list[str], only: str, jobs: int) -> list[dict]:
    cases = [c for c in load_cases("resource") if only in c.id]
    rows = []
    for c in cases:  # serial: these runs are heavy by design
        for t in tools:
            root, work, _, _ = new_workspace()
            r = execute(tool_argv(t, work, c.script), work, make_env(), sandboxed=True)
            out = len(r.stdout) + len(r.stderr)
            disk = dir_bytes(work)
            row = {"suite": "resource", "case": c.id, "tool": t, "exit": r.exit, "wall": round(r.wall, 2),
                   "signal": r.signal, "maxrss_mib": r.maxrss_kb // 1024 if r.maxrss_kb >= 0 else -1,
                   "output_bytes": out, "disk_bytes": disk, "stderr": r.stderr[-300:].decode(errors="replace")}
            rows.append(resource_verdict(row))
            shutil.rmtree(root, ignore_errors=True)
    return rows


# ---------------------------------------------------------------- perf

def perf_workspace() -> Path:
    root, work, _, _ = new_workspace()
    levels = ["INFO", "WARN", "ERROR", "DEBUG"]
    with open(work / "big.txt", "w") as f:
        f.writelines(f"2026-01-{i % 28 + 1:02d} {levels[(i * 7) % 4]} event-{i % 997} user{i % 101} took {i % 503}ms\n" for i in range(50_000))
    return root


def suite_perf(tools: list[str], only: str, jobs: int, repeats: int) -> list[dict]:
    cases = [c for c in load_cases("perf") if only in c.id]
    template = perf_workspace()
    rows = []
    for c in cases:
        ref = None
        for t in ["bash"] + [t for t in tools if t != "bash"]:
            walls, rss, last = [], [], None
            for _ in range(repeats):
                d = Path(tempfile.mkdtemp(prefix="shperf-"))
                shutil.copytree(template / "work", d / "work")
                last = execute(tool_argv(t, d / "work", c.script), d / "work", make_env())
                walls.append(last.wall)
                rss.append(last.maxrss_kb)
                shutil.rmtree(d)
            if t == "bash":
                ref = last
            if t not in tools:
                continue
            assert ref is not None and last is not None
            rows.append({"suite": "perf", "case": c.id, "tool": t, "median_s": round(statistics.median(walls), 4),
                         "min_s": round(min(walls), 4), "maxrss_mib": round(max(rss) / 1024, 1),
                         "verdict": classify(ref, last), "exit": last.exit,
                         "stderr": last.stderr[:300].decode(errors="replace")})
    shutil.rmtree(template)
    return rows


# ---------------------------------------------------------------- reporting

def versions() -> dict:
    def sh(cmd: list[str]) -> str:
        try:
            return subprocess.run(cmd, capture_output=True, text=True, timeout=10, check=False).stdout.strip().splitlines()[0]
        except Exception as e:  # noqa: BLE001 - report what failed
            return f"unknown ({e})"
    rev = lambda d: sh(["git", "-C", str(TOOLS_DIR / d), "log", "-1", "--format=%h %cs"])
    pkg = lambda p: json.loads((TOOLS_DIR / p / "package.json").read_text())["version"]
    return {"bash": sh(["bash", "--version"]), "gbash": "git " + rev("gbash"), "rshell": "git " + rev("rshell"),
            "just-bash": pkg("jb/node_modules/just-bash"), "tinysandbox": pkg("ts/node_modules/@tinysandbox/tinysandbox"),
            "host": f"{platform.node()} {platform.platform()}", "date": time.strftime("%Y-%m-%d %H:%M")}


def summarize(rows: list[dict], tools: list[str]) -> str:
    lines = []
    suites = sorted({r["suite"] for r in rows}, key=["conformance", "security", "resource", "perf"].index)
    for s in suites:
        rs = [r for r in rows if r["suite"] == s]
        lines.append(f"\n## {s}\n")
        if s == "conformance":
            groups = sorted({r["case"].split("/")[0] for r in rs})
            lines.append("| tool | pass | loud fail | silent wrong | timeout | " + " | ".join(groups) + " |")
            lines.append("|---" * (5 + len(groups)) + "|")
            for t in tools:
                tr = [r for r in rs if r["tool"] == t]
                if not tr:
                    continue
                n = len(tr)
                cnt = {v: sum(r["verdict"] == v for r in tr) for v in ("pass", "loud", "silent", "timeout")}
                per = []
                for g in groups:
                    gr = [r for r in tr if r["case"].startswith(g + "/")]
                    per.append(f"{sum(r['verdict'] == 'pass' for r in gr)}/{len(gr)}")
                lines.append(f"| {t} | {cnt['pass']}/{n} ({100 * cnt['pass'] // n}%) | {cnt['loud']} | "
                             f"{cnt['silent']} | {cnt['timeout']} | " + " | ".join(per) + " |")
        elif s == "security":
            kinds = ["read", "write", "exec", "net", "env"]
            lines.append("| tool | blocked | " + " | ".join(f"{k} escapes" for k in kinds) + " |")
            lines.append("|---" * (2 + len(kinds)) + "|")
            for t in tools:
                tr = [r for r in rs if r["tool"] == t]
                if not tr:
                    continue
                esc = lambda k, tr=tr: [r["case"].split("/")[1] for r in tr if r["kind"] == k and r["verdict"] == "ESCAPED"]
                lines.append(f"| {t} | {sum(r['verdict'] == 'blocked' for r in tr)}/{len(tr)} | "
                             + " | ".join(", ".join(esc(k)) or "-" for k in kinds) + " |")
        elif s == "resource":
            cases = sorted({r["case"] for r in rs})
            lines.append("| case | " + " | ".join(tools) + " |")
            lines.append("|---" * (1 + len(tools)) + "|")
            for c in cases:
                cells = []
                for t in tools:
                    r = next((r for r in rs if r["case"] == c and r["tool"] == t), None)
                    cells.append("" if not r else {"contained": "ok ", "refused": "refused ", "NOT contained": "✗ "}[r["verdict"]] +
                                 f"{r['wall']}s " + (f"{r['maxrss_mib']}MiB" if r["maxrss_mib"] >= 0 else "?MiB") + (f" ({r['why']})" if r["why"] else ""))
                lines.append(f"| {c.split('/')[1]} | " + " | ".join(cells) + " |")
        elif s == "perf":
            cases = sorted({r["case"] for r in rs}, key=lambda c: [r["case"] for r in rs].index(c))
            lines.append("| case | " + " | ".join(tools) + " |")
            lines.append("|---" * (1 + len(tools)) + "|")
            for c in cases:
                cells = []
                for t in tools:
                    r = next((r for r in rs if r["case"] == c and r["tool"] == t), None)
                    cells.append("" if not r else f"{r['median_s'] * 1000:.0f}ms {r['maxrss_mib']:.0f}MiB"
                                 + ("" if r["verdict"] == "pass" else f" ({r['verdict']})"))
                lines.append(f"| {c.split('/')[1]} | " + " | ".join(cells) + " |")
            lines.append("\nCell: median wall time over the repeats, peak RSS; a non-`pass` verdict means the output "
                         "differed from bash, so the time is not comparable.")
    return "\n".join(lines) + "\n"


def selfcheck(jobs: int) -> int:
    """Validate the instruments: bash is the known positive, null the known negative."""
    ok = True
    conf = suite_conformance(["bash"], "", jobs)
    bad = [r["case"] for r in conf if r["verdict"] != "pass"]
    print(f"conformance bash-vs-bash: {len(conf) - len(bad)}/{len(conf)} pass", "✅" if not bad else f"❌ {bad}")
    ok &= not bad
    sec = suite_security(["bash", "null"], "", jobs)
    # Probes whose escape needs a host tool that may be absent are allowed to be blocked under bash.
    optional = {"read-jq-rawfile", "exec-sed-e", "exec-node-python", "net-wget", "net-nc", "exec-path-lookup",
                "read-proc-self-root"}
    missed = [r["case"] for r in sec if r["tool"] == "bash" and r["verdict"] == "blocked"
              and r["case"].split("/")[1] not in optional]
    leaked = [r["case"] for r in sec if r["tool"] == "null" and r["verdict"] != "blocked"]
    print(f"security bash escapes (known positive): missed {missed or 'none'}", "✅" if not missed else "❌")
    print(f"security null blocks (known negative): leaked {leaked or 'none'}", "✅" if not leaked else "❌")
    ok &= not missed and not leaked
    res = suite_resource(["bash", "null"], "", jobs)
    bad = [r["case"] for r in res if r["tool"] == "null" and r["verdict"] != "contained"]
    print(f"resource null contained (known negative): not contained {bad or 'none'}", "✅" if not bad else "❌")
    # bash has no limits of its own: every probe must hit a harness cap (sleep and loops: the deadline).
    held = [r["case"] for r in res if r["tool"] == "bash" and r["verdict"] != "NOT contained"]
    print(f"resource bash not contained (known positive): contained {held or 'none'}", "✅" if not held else "❌")
    ok &= not bad and not held
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("suite", choices=["conformance", "security", "resource", "perf", "all", "selfcheck"])
    ap.add_argument("--tools", default=",".join(ALL_TOOLS))
    ap.add_argument("--only", default="", help="substring filter on case ids")
    ap.add_argument("--json", type=Path, help="write raw rows + versions as JSON")
    ap.add_argument("--report", type=Path, help="write the Markdown summary here")
    ap.add_argument("-n", type=int, default=5, help="perf repeats")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--from-json", type=Path, help="re-render the report from a previous --json file (suite: all)")
    a = ap.parse_args()
    if a.from_json:
        data = json.loads(a.from_json.read_text())
        rows = [resource_verdict(r) if r["suite"] == "resource" else r for r in data["rows"]]
        md = "# Shell benchmark results\n\n" + "\n".join(f"- {k}: {val}" for k, val in data["versions"].items())
        md += "\n" + summarize(rows, a.tools.split(","))
        if a.json:
            a.json.write_text(json.dumps({"versions": data["versions"], "rows": rows}, indent=1))
        (a.report.write_text(md) if a.report else print(md))
        return 0
    if a.suite == "selfcheck":
        return selfcheck(a.j)
    tools = a.tools.split(",")
    rows: list[dict] = []
    for s in (["conformance", "security", "resource", "perf"] if a.suite == "all" else [a.suite]):
        print(f"running {s} …", file=sys.stderr)
        if s == "perf":
            rows += suite_perf(tools, a.only, a.j, a.n)
        else:
            rows += globals()[f"suite_{s}"](tools, a.only, a.j)
    v = versions()
    md = "# Shell benchmark results\n\n" + "\n".join(f"- {k}: {val}" for k, val in v.items()) + "\n" + summarize(rows, tools)
    if a.json:
        a.json.write_text(json.dumps({"versions": v, "rows": rows}, indent=1))
    if a.report:
        a.report.write_text(md)
    print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
