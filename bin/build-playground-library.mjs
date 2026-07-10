import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const output = join(root, process.argv[2] || "site/glissade.generated.typ");
const modules = [
  "src/utils.typ",
  "src/transitions.typ",
  "src/states.typ",
  "src/primitives.typ",
  "src/animation.typ",
  "src/draw.typ",
];

function stripImports(source) {
  const lines = source.split("\n");
  const kept = [];
  let importDepth = 0;

  for (const line of lines) {
    const trimmed = line.trimStart();
    if (importDepth > 0 || trimmed.startsWith("#import ")) {
      importDepth += (line.match(/\(/g) || []).length;
      importDepth -= (line.match(/\)/g) || []).length;
      importDepth = Math.max(0, importDepth);
      continue;
    }
    kept.push(line);
  }

  return kept.join("\n").trim();
}

const chunks = modules.map(path => {
  const source = stripImports(readFileSync(join(root, path), "utf8"));

  return `// ---- ${path} ----\n${source}`;
});

const header = `// Generated playground bundle from ../src/*.typ. Do not edit by hand.
// Run \`npm run build:playground-lib\` or let CI generate it before deployment.
`;

mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${header}\n${chunks.join("\n\n")}\n`, "utf8");
