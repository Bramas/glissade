import { mkdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const outputDirectory = resolve(root, "bin/assets");
const check = process.argv.includes("--check");

const runtimeBuild = await Bun.build({
  entrypoints: [resolve(import.meta.dir, "runtime/index.js")],
  target: "browser",
  format: "iife",
  minify: true,
  write: false,
});
if (!runtimeBuild.success) {
  for (const log of runtimeBuild.logs) console.error(log);
  process.exit(1);
}
const runtime = await runtimeBuild.outputs[0].text();

const javascript = new Bun.Transpiler({
  loader: "js",
  target: "browser",
  minifyWhitespace: true,
  minifyIdentifiers: true,
  minifySyntax: true,
});

function minifyCss(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\s+/g, " ")
    .replace(/\s*([{}:;,>])\s*/g, "$1")
    .replace(/;}/g, "}")
    .trim();
}

async function buildTemplate(name) {
  let html = await readFile(resolve(import.meta.dir, name, "index.html"), "utf8");
  html = html.replace("${morph_runtime_source}", runtime);
  html = html.replaceAll("${title}", "__KINO_TITLE__");
  html = html.replaceAll("${manifest_source}", "globalThis.__KINO_MANIFEST_SOURCE__");
  html = html.replaceAll("${live_reload}", "globalThis.__KINO_LIVE_RELOAD__");

  html = html.replace(/<style>([\s\S]*?)<\/style>/g, (_, css) => `<style>${minifyCss(css)}</style>`);
  html = html.replace(/<script>([\s\S]*?)<\/script>/g, (_, source) => `<script>${javascript.transformSync(source)}</script>`);
  html = html.replace(/>\s+</g, "><").trim();
  html = html
    .replaceAll("$", () => "$$")
    .replaceAll("__KINO_TITLE__", "${title}")
    .replaceAll("globalThis.__KINO_MANIFEST_SOURCE__", "${manifest_source}")
    .replaceAll("globalThis.__KINO_LIVE_RELOAD__", "${live_reload}");

  const output = resolve(outputDirectory, `${name}.min.html`);
  const generated = html + "\n";
  if (check) {
    const existing = await readFile(output, "utf8").catch(() => "");
    if (existing !== generated) {
      console.error(`Outdated generated asset: ${output}`);
      process.exitCode = 1;
    }
  } else {
    await mkdir(outputDirectory, { recursive: true });
    await writeFile(output, generated);
    console.log(`Built ${output}`);
  }
}

await buildTemplate("present");
await buildTemplate("editor");
