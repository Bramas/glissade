import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const output = join(root, "site", "glissade.typ");
const modules = [
  "src/utils.typ",
  "src/transitions.typ",
  "src/states.typ",
  "src/primitives.typ",
  "src/animation.typ",
  "src/draw.typ",
];

const chunks = modules.map(path => {
  const source = readFileSync(join(root, path), "utf8")
    .split("\n")
    .filter(line => !line.trimStart().startsWith("#import "))
    .join("\n")
    .trim();

  return `// ---- ${path} ----\n${source}`;
});

const header = `// Generated playground bundle from ../src/*.typ. Do not edit by hand.
// Run \`node bin/build-playground-library.mjs\` or let CI generate it before deployment.
`;

mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${header}\n${chunks.join("\n\n")}\n`, "utf8");
