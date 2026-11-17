// Command rshell-policy runs (or statically checks) a script in rshell under a benchmark policy
// (see bench/POLICY.md).
//
// Usage: rshell-policy [--check] POLICY.json WORKDIR SCRIPT
// The process working directory must be WORKDIR. With --check, prints the interp.Runner.Check report as
// JSON and runs nothing. Exit 99 means the policy cannot be expressed in rshell.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/DataDog/rshell/builtins"
	"github.com/DataDog/rshell/interp"
)

type Policy struct {
	Commands []string          `json:"commands"`
	FS       map[string]string `json:"fs"`
	Net      []string          `json:"net"`
	Env      map[string]string `json:"env"`
}

func main() {
	args := os.Args[1:]
	check := len(args) > 0 && args[0] == "--check"
	if check {
		args = args[1:]
	}
	if len(args) != 3 {
		fmt.Fprintln(os.Stderr, "usage: rshell-policy [--check] POLICY.json WORKDIR SCRIPT")
		os.Exit(2)
	}
	raw, err := os.ReadFile(args[0])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	var p Policy
	if err := json.Unmarshal(raw, &p); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	if len(p.Net) > 0 {
		fmt.Fprintln(os.Stderr, "unsupported: rshell has no HTTP client, so a URL allowlist cannot be granted")
		os.Exit(99)
	}
	work := args[1]
	if _, ok := p.FS["."]; p.FS != nil && !ok {
		// The runner starts in the first granted root and cannot cd into an ungranted parent (there is no
		// traverse-only grant), so paths relative to WORKDIR cannot be resolved.
		fmt.Fprintln(os.Stderr, "unsupported: the working directory must lie inside a granted root (no traverse-only grant)")
		os.Exit(99)
	}
	cmds := p.Commands
	if cmds == nil {
		if r, err := interp.New(); err == nil { // the builtin registry is filled lazily by the first New
			r.Close()
		}
		cmds = builtins.Names()
	}
	grants := make([]string, 0, len(cmds))
	for _, c := range cmds { // grants for names rshell lacks are accepted and inert
		if !strings.Contains(c, ":") { // ":" cannot be granted (the grant syntax is rshell:NAME)
			grants = append(grants, "rshell:"+c)
		}
	}
	var paths []string
	writable := false
	if p.FS == nil {
		paths, writable = []string{work + ":rw"}, true
	}
	for rel, mode := range p.FS {
		paths = append(paths, filepath.Join(work, rel)+":"+mode)
		writable = writable || mode == "rw"
	}
	env := []string{}
	for k, v := range p.Env {
		env = append(env, k+"="+v)
	}
	mode := interp.ModeReadOnly
	if writable {
		mode = interp.ModeRemediation
	}
	runner, err := interp.New(
		interp.StdIO(nil, os.Stdout, os.Stderr),
		interp.AllowedCommands(grants),
		interp.AllowedPaths(paths),
		interp.Env(env...),
		interp.WithMode(mode),
		interp.MaxExecutionTime(10*time.Second),
	)
	if err != nil {
		fmt.Fprintln(os.Stderr, "unsupported:", err)
		os.Exit(99)
	}
	defer runner.Close()
	ctx := context.Background()
	if check {
		rep, err := runner.Check(ctx, args[2])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(2)
		}
		_ = json.NewEncoder(os.Stdout).Encode(rep)
		return
	}
	prog, err := interp.ParseScript(args[2], "")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	err = runner.Run(ctx, prog)
	var es interp.ExitStatus
	switch {
	case err == nil:
		os.Exit(0)
	case errors.As(err, &es):
		os.Exit(int(es))
	default:
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
