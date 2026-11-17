// Run a script in tinysandbox under a benchmark policy (see bench/POLICY.md).
// Usage: node tinysandbox-policy.mjs POLICY.json WORKDIR SCRIPT
// Mounts are top-level only and the host-backed (local) mount has no read-only mode, so only rw grants of
// "." or of single top-level directories are expressible. Exit 99 means the policy cannot be expressed.
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { createRequire } from 'node:module'
const require = createRequire(new URL('../.tools/ts/package.json', import.meta.url))
const { Sandbox } = require('@tinysandbox/tinysandbox')

const [policyPath, workdir, script] = process.argv.slice(2)
const p = JSON.parse(readFileSync(policyPath, 'utf8'))
const unsupported = (why) => { process.stderr.write(`unsupported: ${why}\n`); process.exit(99) }

if (p.net?.length) unsupported('the shell has no network command (fetch exists only inside the js guest)')
const grants = p.fs ?? { '.': 'rw' }
const mounts = {}
let cwd = '/'
for (const [rel, mode] of Object.entries(grants)) {
  if (mode !== 'rw') unsupported(`local mounts have no read-only mode (grant ${rel}:${mode})`)
  if (rel === '.') { mounts.workspace = { type: 'local', root: workdir }; cwd = '/workspace'; continue }
  if (rel.includes('/')) unsupported(`mounts are top-level only (grant ${rel})`)
  mounts[rel] = { type: 'local', root: join(workdir, rel) }
}
let disabledCommands = []
if (p.commands) {
  const all = (await new Sandbox().exec('ls /bin')).stdout.split('\n').filter(Boolean)
  disabledCommands = all.filter((c) => !p.commands.includes(c))
}
const sandbox = new Sandbox({ mounts, env: p.env ?? {}, disabledCommands, limits: { wallTimeMs: 10000 } })
// The 0.9.0 binding ignores the `cwd` option, hence the explicit cd.
const r = await sandbox.exec(`cd ${cwd}\n${script}`)
process.stdout.write(r.stdout)
process.stderr.write(r.stderr)
process.exitCode = r.exitCode
