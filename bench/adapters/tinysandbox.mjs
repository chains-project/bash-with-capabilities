// Run one script in tinysandbox with WORKDIR mounted (host-backed) at /workspace.
// Usage: node tinysandbox.mjs WORKDIR SCRIPT
// The `cwd` constructor option is not honoured by the 0.9.0 Node binding, hence the `cd` prefix.
import { createRequire } from 'node:module'
const require = createRequire(new URL('../.tools/ts/package.json', import.meta.url))
const { Sandbox } = require('@tinysandbox/tinysandbox')

const [workdir, script] = process.argv.slice(2)
const sandbox = new Sandbox({
  mounts: { workspace: { type: 'local', root: workdir } },
  limits: { wallTimeMs: 10000 },
})
const r = await sandbox.exec('cd /workspace\n' + script)
process.stdout.write(r.stdout)
process.stderr.write(r.stderr)
process.exitCode = r.exitCode
