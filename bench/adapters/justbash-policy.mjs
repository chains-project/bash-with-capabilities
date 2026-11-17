// Run a script in just-bash under a benchmark policy (see bench/POLICY.md).
// Usage: node justbash-policy.mjs POLICY.json WORKDIR SCRIPT
// Granted paths are mounted under /work (rw: ReadWriteFs on the host, ro: OverlayFs with readOnly);
// everything else is an empty in-memory base. Exit 99 means the policy cannot be expressed in just-bash.
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
const jb = await import(new URL('../.tools/jb/node_modules/just-bash/dist/bundle/index.js', import.meta.url))
const { Bash, MountableFs, ReadWriteFs, OverlayFs, InMemoryFs } = jb

const [policyPath, workdir, script] = process.argv.slice(2)
const p = JSON.parse(readFileSync(policyPath, 'utf8'))

const grants = p.fs ?? { '.': 'rw' }
const mounts = Object.entries(grants).map(([rel, mode]) => {
  const mountPoint = join('/work', rel)
  const filesystem = mode === 'rw'
    ? new ReadWriteFs({ root: join(workdir, rel) })
    : new OverlayFs({ root: join(workdir, rel), mountPoint: '/', readOnly: true })
  return { mountPoint, filesystem }
})
const opts = {
  fs: new MountableFs({ base: new InMemoryFs(), mounts }),
  cwd: '/work',
  env: p.env ?? {},
  executionLimits: { maxExecutionTimeMs: 10000 },
}
if (p.commands) opts.commands = p.commands.filter((c) => c !== 'curl')
if (p.net?.length) opts.network = { allowedUrlPrefixes: p.net, denyPrivateRanges: false }

let bash
try {
  bash = new Bash(opts)
} catch (e) {
  process.stderr.write(`unsupported: ${e.message}\n`)
  process.exit(99)
}
let r
try {
  r = await bash.exec(script)
} catch (e) { // e.g. EROFS from a read-only mount escapes exec() as an exception
  r = { stdout: '', stderr: `exception: ${e.message}\n`, exitCode: 1 }
}
process.stdout.write(r.stdout)
process.stderr.write(r.stderr)
process.exitCode = r.exitCode
