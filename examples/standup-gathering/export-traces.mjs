#!/usr/bin/env node
// Record the executions drawn in the talk with the public Simulant engine.
//
//   node examples/standup-gathering/export-traces.mjs /path/to/simulant [--check]
//
// The traces of the H+1 algorithm come from the public project
// `projects/standup-gathering/sim/h-plus-one.sim`. Each "without" trace runs a
// copy of that file with exactly one rule removed; the copies are written to a
// temporary directory and the Simulant checkout is never modified.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const simulator = process.argv[2];
if (!simulator) {
  console.error('Usage: node examples/standup-gathering/export-traces.mjs /path/to/simulant [--check]');
  process.exit(2);
}

// Every scenario is fault-free unless it names a crash node and round.
const scenarios = [
  // Recap of the problem.
  { id: 'gather', positions: [0, 3, 5, 6, 7], phi: 4 },
  { id: 'gather-crash', positions: [0, 3, 5, 6, 7], phi: 4, crashNode: 5, crashRound: 1 },
  // The parity-preserving merge of a border 3-block.
  { id: 'merge', positions: [0, 1, 2, 5, 8], phi: 4 },
  // Trick 1: a myopic robot believes it is next to a border.
  { id: 'false-border', positions: [0, 4, 8, 9, 10, 12, 15], phi: 5 },
  { id: 'false-border-without', positions: [0, 4, 8, 9, 10, 12, 15], phi: 5, without: ['neig, false-merge'] },
  // Trick 2: the border waits one round.
  { id: 'border-wait', positions: [0, 3, 5, 6, 7], phi: 4 },
  { id: 'border-wait-without', positions: [0, 3, 5, 6, 7], phi: 4, without: ['border-idle,1'] },
  // Trick 3: blocks of four or more nodes split.
  { id: 'long-block', positions: [0, 2, 3, 4, 5], phi: 4 },
  { id: 'long-block-without', positions: [0, 2, 3, 4, 5], phi: 4, without: ['4-merge,1', '4-merge,2'] },
];

// Remove one rule (its `-- name` comment and its guarded branches) from the
// public algorithm. Throws if the source no longer has that exact shape.
function withoutRule(source, name) {
  const lines = source.split('\n');
  const at = lines.findIndex(line => line.trim() === `-- ${name}`);
  if (at < 0) throw new Error(`rule ${name} not found`);
  const symmetric = lines[at + 1].includes('∨');
  const length = symmetric ? 2 : 4;
  for (const line of lines.slice(at + 1, at + 1 + length)) {
    if (!/^\s+(else )?if |^\s+(move|stay)/.test(line)) throw new Error(`unexpected shape for rule ${name}: ${line}`);
  }
  lines.splice(at, length + 1);
  const first = lines.findIndex(line => /^\s+(else )?if /.test(line));
  lines[first] = lines[first].replace('else if', 'if');
  return lines.join('\n');
}

const sources = join(simulator, 'projects/standup-gathering/sim');
const algorithm = readFileSync(join(sources, 'h-plus-one.sim'), 'utf8');
const work = mkdtempSync(join(tmpdir(), 'suig-variants-'));
writeFileSync(join(work, 'model.sim'), readFileSync(join(sources, 'model.sim'), 'utf8'));
const files = {};
for (const scenario of scenarios) {
  const name = scenario.without ? `without-${scenario.id}` : 'h-plus-one';
  if (!files[name]) {
    const text = (scenario.without ?? []).reduce(withoutRule, algorithm);
    files[name] = join(work, `${name}.sim`);
    writeFileSync(files[name], text);
  }
  scenario.file = files[name];
}

const program = String.raw`
import { simProject } from '@bramas/simulant-ui/sim/project';
import { System } from './packages/engine/src/system.ts';
import { pathToFileURL } from 'node:url';

const scenarios = JSON.parse(process.env.SUIG_SCENARIOS);
const traces = {};
for (const scenario of scenarios) {
  const module = await import(pathToFileURL(scenario.file).href);
  const project = simProject(module, 'hPlusOne', { defaults: { positions: [0, 2, 4] } });
  const settings = { positions: JSON.stringify(scenario.positions), phi: scenario.phi,
    crashNode: scenario.crashNode ?? scenario.positions[0] };
  const base = project.setup(settings).system;
  // Keep physical tracks for the drawings. IDs never enter a robot's view.
  const system = new System(base.exp, base.params, { sortAgents: false });
  let config = system.initial()[0].config;
  const snapshot = (C, round) => {
    const occupied = [...new Set(C.agents.map(a => a.pos))].sort((a, b) => a - b);
    return { round, positions: C.agents.map(a => a.pos), crashed: C.agents.map(a => Boolean(a.f.crashed)),
      occupied, occupiedCount: occupied.length, diameter: occupied.at(-1) - occupied[0] };
  };
  const states = [snapshot(config, 0)];
  const rules = [];
  const seen = new Set();
  let outcome = 'timeout';
  for (let round = 1; round <= 40; round++) {
    if (system.verdict(config) === 'success') { outcome = 'gathered'; break; }
    const key = JSON.stringify(config.agents.map(a => [a.pos, Boolean(a.f.crashed)]));
    if (seen.has(key)) { outcome = 'cycle'; break; }
    seen.add(key);
    const next = system.successors(config).find(s => {
      const crashes = s.config.agents.filter(a => a.f.crashed);
      if (!scenario.crashRound || round < scenario.crashRound) return crashes.length === 0;
      return crashes.length === (scenario.crashCount ?? 1) && crashes.every(a => a.pos === scenario.crashNode);
    });
    if (!next) throw new Error(scenario.id + ': no matching branch at round ' + round);
    const explanations = system.explainAll(config, next.key);
    rules.push(config.agents.map((a, i) => explanations[i]?.calls.find(c => /^h1[A-Z]/.test(c.fn) && c.result === 'true')?.fn
      ?? (a.f.crashed ? 'crashed' : 'stay')));
    if (config.agents.some((a, i) => Math.abs(next.config.agents[i].pos - a.pos) > 1)) throw new Error('Non-local move');
    config = next.config;
    states.push(snapshot(config, round));
  }
  if (outcome === 'timeout' && system.verdict(config) === 'success') outcome = 'gathered';
  const { file, ...rest } = scenario;
  traces[scenario.id] = { ...rest, outcome, states, rules };
}
console.log(JSON.stringify(traces));
`;

const result = spawnSync(process.execPath, [
  '--import', 'tsx', '--import', './packages/vite-plugin/src/register.ts', '--input-type=module', '-e', program,
], { cwd: resolve(simulator), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
  env: { ...process.env, SUIG_SCENARIOS: JSON.stringify(scenarios) } });
rmSync(work, { recursive: true, force: true });
if (result.status !== 0) {
  console.error(result.stderr || result.stdout || result.error);
  process.exit(result.status || 1);
}
const traces = JSON.parse(result.stdout);

// The talk relies on these outcomes; fail loudly if the engine disagrees.
for (const [id, trace] of Object.entries(traces)) {
  const expected = trace.without ? 'cycle' : 'gathered';
  if (trace.outcome !== expected) throw new Error(`${id}: expected ${expected}, got ${trace.outcome}`);
  if (trace.crashRound && !trace.states.at(-1).positions.every(p => p === trace.crashNode)) {
    throw new Error(`${id}: correct robots did not gather at the crash node`);
  }
}

const hash = file => readFileSync(file, 'utf8');
const { createHash } = await import('node:crypto');
const commit = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: resolve(simulator), encoding: 'utf8' }).stdout.trim();
const data = {
  schemaVersion: 2,
  source: 'Simulant public standup-gathering project, executed by the Simulant engine',
  simulantCommit: commit,
  sourceHashes: Object.fromEntries(['model.sim', 'h-plus-one.sim'].map(name =>
    [`projects/standup-gathering/sim/${name}`, createHash('sha256').update(hash(join(sources, name))).digest('hex')])),
  conventions: {
    roundZero: 'initial configuration',
    tracks: 'drawing-only physical tracks; robots have no IDs',
    movement: 'one edge or stay; intermediate frames are visual interpolation',
    without: 'the public algorithm with the listed rules removed, to show why they are needed',
  },
  traces,
};
const output = resolve(directory, 'traces.json');
const encoded = JSON.stringify(data, null, 2) + '\n';
if (process.argv.includes('--check')) {
  if (readFileSync(output, 'utf8') !== encoded) throw new Error('Committed traces differ from the simulator');
  console.log('All presentation traces agree with the public Simulant project.');
} else {
  writeFileSync(output, encoded);
  for (const [id, trace] of Object.entries(traces)) {
    const counts = trace.states.map(s => s.occupiedCount).join(' ');
    console.log(`${id.padEnd(22)} ${trace.outcome.padEnd(9)} ${trace.states.length - 1} rounds · occupied ${counts}`);
  }
}
