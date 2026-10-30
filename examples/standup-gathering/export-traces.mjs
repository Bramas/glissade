#!/usr/bin/env node
// Read the public Simulant project; write only this presentation's trace data.
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const simulator = process.argv[2];
if (!simulator) {
  console.error('Usage: node examples/standup-gathering/export-traces.mjs /path/to/simulant [--check]');
  process.exit(2);
}
const program = String.raw`
import { projects } from './projects/standup-gathering/src/projects.ts';
import { System } from './packages/engine/src/system.ts';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

const scenarios = [
  {id:'h3-clean', algorithm:'h-plus-three', positions:[0,2,4], phi:5},
  {id:'h3-convoy', algorithm:'h-plus-three', positions:[0,1,2,5,8], phi:6},
  {id:'h3-even-occupied', algorithm:'h-plus-three', positions:[0,1,3,4], phi:5},
  {id:'h3-paper', algorithm:'h-plus-three', positions:[...'....>..X...X...X...XXXX.X...<<'].flatMap((c,i)=>c==='.'?[]:[i]), phi:7},
  {id:'h3-border-crash', algorithm:'h-plus-three', positions:[0,2,4], phi:5, crashNode:0, crashRound:1},
  {id:'h3-interior-crash', algorithm:'h-plus-three', positions:[0,3,6], phi:6, crashNode:3, crashRound:2},
  {id:'h3-partial-crash', algorithm:'h-plus-three', positions:[0,0,1,2], phi:4, crashNode:0, crashRound:1, crashCount:1},
  {id:'h1-four-block', algorithm:'h-plus-one', positions:[0,1,2,3,7], phi:5},
  {id:'h1-five-block', algorithm:'h-plus-one', positions:[0,1,2,3,4], phi:4},
  {id:'h1-paper', algorithm:'h-plus-one', positions:[3,7,8,9,11,12,14,15,17], phi:5},
  {id:'h1-border-crash', algorithm:'h-plus-one', positions:[0,2,4], phi:4, crashNode:0, crashRound:1},
  {id:'h1-partial-crash', algorithm:'h-plus-one', positions:[0,0,1,2], phi:4, crashNode:0, crashRound:1, crashCount:1},
];
const traces = {};
for (const scenario of scenarios) {
  const project = projects['standup-gathering-'+scenario.algorithm];
  const settings = { positions:scenario.positions, phi:scenario.phi, crashNode:scenario.crashNode??scenario.positions[0] };
  if (project.settingsWarnings(settings).length) throw new Error(scenario.id+': outside the declared domain');
  const base = project.setup(settings).system;
  // Keep physical tracks for the drawings. IDs never enter a robot's view.
  const system = new System(base.exp, base.params, {sortAgents:false});
  let config = system.initial()[0].config;
  const snapshot = (C,round) => {
    const occupied = [...new Set(C.agents.map(a=>a.pos))].sort((a,b)=>a-b);
    return {round, positions:C.agents.map(a=>a.pos), crashed:C.agents.map(a=>Boolean(a.f.crashed)), occupied,
      occupiedCount:occupied.length, diameter:occupied.at(-1)-occupied[0]};
  };
  const states = [snapshot(config,0)];
  const transitions = [];
  for (let round=1; round<=80 && system.verdict(config)!=='success'; round++) {
    const next = system.successors(config).find(s => {
      const crashes=s.config.agents.filter(a=>a.f.crashed);
      if (!scenario.crashRound || round<scenario.crashRound) return crashes.length===0;
      return crashes.length===(scenario.crashCount??1) && crashes.every(a=>a.pos===scenario.crashNode);
    });
    if (!next) throw new Error(scenario.id+': no matching crash branch at round '+round);
    const explanations = system.explainAll(config,next.key);
    const moves = config.agents.map((a,i)=>({
      track:i, from:a.pos, to:next.config.agents[i].pos,
      crashed: Boolean(next.config.agents[i].f.crashed),
      newCrash: !a.f.crashed && Boolean(next.config.agents[i].f.crashed),
      rule: explanations[i]?.calls.find(c=>/^h[13][A-Z]/.test(c.fn)&&c.result==='true')?.fn??(a.f.crashed?'crashed':'default stay'),
    }));
    if (moves.some(m=>Math.abs(m.to-m.from)>1)) throw new Error('Non-local move');
    transitions.push({round,moves});
    config=next.config;
    states.push(snapshot(config,round));
  }
  if (system.verdict(config)!=='success') throw new Error(scenario.id+': failed to gather');
  if (scenario.crashRound && !config.agents.every(a=>a.pos===scenario.crashNode)) throw new Error('Wrong rescue site');
  if (system.successors(config).some(s=>s.config.agents.some((a,i)=>a.pos!==config.agents[i].pos))) throw new Error('Gathering not closed');
  if (!scenario.crashRound && scenario.positions.filter((p,i,ps)=>!ps.slice(0,i).includes(p)).length%2===1
      && states.some(s=>(scenario.algorithm==='h-plus-three'||s.diameter>=4)&&s.occupiedCount%2!==1)) throw new Error('Bulk parity lost in '+scenario.id);
  // Algorithm 2's checked terminal traces may have even occupancy at D <= 3.
  // Do not turn the bulk parity argument into an invariant of every round.
  traces[scenario.id]={...scenario, generatedBy:'Simulant public project', states, transitions};
}
const files=['projects/standup-gathering/sim/model.sim','projects/standup-gathering/sim/h-plus-three.sim','projects/standup-gathering/sim/h-plus-one.sim'];
console.log(JSON.stringify({
  schemaVersion:1,
  source:'Simulant public standup-gathering project; original execution data, not a reimplementation of its rules',
  sourceHashes:Object.fromEntries(files.map(file=>[file,createHash('sha256').update(readFileSync(file)).digest('hex')])),
  conventions:{roundZero:'initial configuration',tracks:'drawing-only physical tracks; robots have no IDs',movement:'one edge or stay; intermediate SVG frames are visual interpolation'},
  traces
},null,2));
`;
const result = spawnSync(process.execPath, ['--import', 'tsx', '--import', './packages/vite-plugin/src/register.ts', '--input-type=module', '-e', program], {
  cwd: resolve(simulator), encoding: 'utf8', maxBuffer: 16 * 1024 * 1024,
});
if (result.status !== 0) {
  console.error(result.stderr || result.stdout || result.error);
  process.exit(result.status || 1);
}
const data = JSON.parse(result.stdout);
// An intentionally incorrect strategy, kept separate from the paper algorithms.
const positions = [0,2,5,12,17];
let current = positions;
const states = [];
const transitions = [];
for (let round=0; round<=12; round++) {
  const occupied=[...new Set(current)].sort((a,b)=>a-b);
  states.push({round,positions:current,crashed:current.map(()=>false),occupied,occupiedCount:occupied.length,diameter:occupied.at(-1)-occupied[0]});
  if(round===12)break;
  const low=Math.min(...current), high=Math.max(...current);
  const next=current.map(p=>p===low?p+1:p===high?p-1:p);
  transitions.push({round:round+1,moves:current.map((p,i)=>({track:i,from:p,to:next[i],crashed:false,newCrash:false,rule:'naive: only the true borders move inward'}))});
  current=next;
}
if (states.at(-1).diameter !== 1 || states.some(s=>s.occupiedCount===1)) throw new Error('Expected a non-gathering edge-symmetric loop');
data.traces['naive-border']={id:'naive-border',algorithm:'intentionally incorrect border-only strategy',generatedBy:'Independent counterexample, not a paper-algorithm trace',positions,phi:8,states,transitions};
const output = resolve(directory, 'traces.json');
const encoded = JSON.stringify(data, null, 2) + '\n';
if (process.argv.includes('--check')) {
  if (readFileSync(output, 'utf8') !== encoded) throw new Error('Committed traces differ from the simulator');
  console.log('All presentation traces agree with the public Simulant project.');
} else {
  writeFileSync(output, encoded);
  for (const [id, trace] of Object.entries(data.traces)) console.log(`${id}: ${trace.states.length - 1} rounds; final occupied nodes ${trace.states.at(-1).occupied.join(', ')}`);
}
