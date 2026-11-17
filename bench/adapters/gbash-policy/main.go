// Command gbash-policy runs a script in gbash under a benchmark policy (see bench/POLICY.md).
//
// Usage: gbash-policy POLICY.json WORKDIR SCRIPT
// WORKDIR is mounted read-write as the sandbox root "/" (gbash.ReadWriteDirectoryFileSystem), so effects are
// visible on the host. Exit 99 means the policy cannot be expressed in gbash.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path"
	"time"

	"github.com/ewhauser/gbash"
	"github.com/ewhauser/gbash/contrib/extras"
	"github.com/ewhauser/gbash/policy"
)

type Policy struct {
	Commands []string          `json:"commands"` // nil: all commands
	FS       map[string]string `json:"fs"`       // nil: whole workdir rw; else relative path -> "ro" | "rw"
	Net      []string          `json:"net"`      // URL prefixes; nil or empty: no network
	Env      map[string]string `json:"env"`
}

func main() {
	if len(os.Args) != 4 {
		fmt.Fprintln(os.Stderr, "usage: gbash-policy POLICY.json WORKDIR SCRIPT")
		os.Exit(2)
	}
	raw, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	var p Policy
	if err := json.Unmarshal(raw, &p); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	cfg := &policy.Config{AllowedCommands: p.Commands}
	if p.FS != nil {
		for rel, mode := range p.FS {
			abs := path.Clean("/" + rel)
			cfg.ReadRoots = append(cfg.ReadRoots, abs)
			if mode == "rw" {
				cfg.WriteRoots = append(cfg.WriteRoots, abs)
			}
		}
		// Command lookup stats the registry stubs in /bin and /usr/bin, so they must stay readable.
		cfg.ReadRoots = append(cfg.ReadRoots, "/bin", "/usr/bin")
		// policy.NewStatic turns an empty root list into "/" (allow all); an impossible root expresses "none".
		if len(cfg.WriteRoots) == 0 {
			cfg.WriteRoots = []string{"/.no-write-grant"}
		}
		if len(cfg.ReadRoots) == 0 {
			cfg.ReadRoots = []string{"/.no-read-grant"}
		}
	}
	if p.Commands != nil && len(p.Commands) == 0 {
		cfg.AllowedCommands = []string{".no-command-grant"} // same empty-means-all rule
	}
	opts := []gbash.Option{
		gbash.WithRegistry(extras.FullRegistry()),
		gbash.WithFileSystem(gbash.ReadWriteDirectoryFileSystem(os.Args[2], gbash.ReadWriteDirectoryOptions{})),
		gbash.WithPolicy(policy.NewStatic(cfg)),
		gbash.WithBaseEnv(p.Env),
	}
	if len(p.Net) > 0 {
		opts = append(opts, gbash.WithNetwork(&gbash.NetworkConfig{AllowedURLPrefixes: p.Net}))
	}
	gb, err := gbash.New(opts...)
	if err != nil {
		fmt.Fprintln(os.Stderr, "unsupported:", err)
		os.Exit(99)
	}
	res, err := gb.Run(context.Background(), &gbash.ExecutionRequest{Script: os.Args[3], Timeout: 10 * time.Second})
	if res != nil {
		fmt.Fprint(os.Stdout, res.Stdout)
		fmt.Fprint(os.Stderr, res.Stderr)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		if res == nil || res.ExitCode == 0 {
			os.Exit(1)
		}
	}
	os.Exit(res.ExitCode)
}
