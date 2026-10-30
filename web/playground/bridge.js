// Adapt typst.ts vector SVG and metadata to the same scenes as the CLI.
(() => {
  const SVG_NS = "http://www.w3.org/2000/svg";
  const colors = new Map([
    ["#ff4fd8", "part-start"], ["#00d5ff", "part-end"],
    ["#19c37d", "morph-start"], ["#ff8a00", "morph-end"],
  ]);
  const token = value => String(value).replace(/[^a-zA-Z0-9_-]+/g, "-").replace(/^[-_]+|[-_]+$/g, "") || "part";

  function markerKind(group) {
    if (group?.localName !== "g" || group.querySelector("use")) return null;
    const paths = group.querySelectorAll("path");
    return paths.length === 1 ? colors.get(paths[0].getAttribute("fill")?.toLowerCase()) : null;
  }

  function visible(element) {
    return Boolean(element.querySelector("use") || [...element.querySelectorAll("path")]
      .some(path => !colors.has(path.getAttribute("fill")?.toLowerCase())));
  }

  function tagPage(page, record) {
    const markers = [...page.querySelectorAll("path")].filter(path => colors.has(path.getAttribute("fill")?.toLowerCase()));
    let partStart = null;
    let morphStart = null;
    let partIndex = 0;
    let morphIndex = 0;
    const removals = new Set();
    for (const path of markers) {
      const kind = colors.get(path.getAttribute("fill").toLowerCase());
      let group = path.parentElement;
      while (markerKind(group.parentElement) === kind) group = group.parentElement;
      const parent = group.parentElement;
      if (kind === "part-start") { partStart = group; continue; }
      if (kind === "morph-start") { morphStart = group; continue; }
      const start = kind === "part-end" ? partStart : morphStart;
      if (!start || start.parentElement !== parent) continue;
      const siblings = [...parent.children];
      let target;
      if (kind === "part-end") {
        target = siblings.slice(0, siblings.indexOf(start)).reverse().find(element => !markerKind(element) && visible(element));
      } else {
        // The vector renderer can flatten Typst's box. Preserve the whole
        // marked fragment, including every glyph and its semantic parts.
        target = document.createElementNS(SVG_NS, "g");
        const contents = siblings.slice(siblings.indexOf(start) + 1, siblings.indexOf(group));
        parent.insertBefore(target, group);
        target.append(...contents);
      }
      if (target) {
        if (kind === "part-end") {
          const part = record.parts[partIndex++];
          if (part) {
            target.id = part.id;
            target.setAttribute("data-glissade-part", "true");
            target.setAttribute("data-glissade-part-key", part.key);
          }
        } else {
          const morph = record.morphs[morphIndex++];
          if (morph) {
            target.id = "glissade-morph-" + token(morph.id);
            target.setAttribute("data-glissade-morph", "true");
            target.setAttribute("data-glissade-morph-id", morph.id);
            if (morph.effect) target.setAttribute("data-glissade-morph-effect", morph.effect);
          }
        }
      }
      removals.add(start);
      removals.add(group);
      if (kind === "part-end") partStart = null;
      else morphStart = null;
    }
    for (const group of removals) group.remove();
  }

  function metadataRecords(metadata) {
    const records = [];
    let record;
    let morph;
    let counts;
    for (const value of metadata) {
      if (value.glissade_slide_scope != null) {
        record = { id: String(value.glissade_slide_scope), parts: [], morphs: [] };
        records.push(record);
        counts = new Map();
        morph = null;
      }
      if (!record) continue;
      if (value.glissade_animation_scope) record.scope = value.glissade_animation_scope;
      if (value["glissade-morph-root"]) {
        morph = value;
        record.morphs.push(value);
      }
      if (value["glissade-formula-part"] && morph) {
        const key = String(value.key);
        const identity = token(morph.id) + "-" + token(key);
        const occurrence = (counts.get(identity) || 0) + 1;
        counts.set(identity, occurrence);
        record.parts.push({ id: "formula-part-" + identity + "-" + occurrence, key: key + "::" + occurrence });
      }
    }
    return records;
  }

  function inlineSvg(svg) {
    const text = new XMLSerializer().serializeToString(svg);
    const bytes = new TextEncoder().encode(text);
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return "data:image/svg+xml;base64," + btoa(binary);
  }

  function buildManifest(svgMarkup, metadata, discovery) {
    const container = document.createElement("template");
    container.innerHTML = svgMarkup;
    const documentSvg = container.content.querySelector("svg");
    if (!documentSvg) throw new Error("Compiler returned no SVG");
    // Vector SVG includes HTML text selection layers and non-rendered hints.
    for (const hint of documentSvg.querySelectorAll("foreignObject, .typst-content-hint, script")) hint.remove();
    // typst.ts represents whitespace with unresolved glyph uses. They paint
    // nothing but would make the morph renderer consider an empty state full.
    for (const use of documentSvg.querySelectorAll("use")) {
      const href = use.getAttribute("href") || use.getAttribute("xlink:href");
      if (href?.startsWith("#") && !documentSvg.querySelector("#" + CSS.escape(href.slice(1)))) use.remove();
    }
    const pages = [...documentSvg.querySelectorAll(".typst-page")];
    const records = metadataRecords(metadata);
    if (pages.length !== records.length) throw new Error("Expected one Glissade frame per page. Use a Glissade deck in the playground.");
    const timelines = discovery.filter(value => value.glissade_timeline).map(value => value.glissade_timeline);
    const frames = records.map((record, index) => {
      const svg = documentSvg.cloneNode(true);
      const clonedPages = [...svg.querySelectorAll(".typst-page")];
      for (const [pageIndex, page] of clonedPages.entries()) if (pageIndex !== index) page.remove();
      const page = clonedPages[index];
      page.removeAttribute("transform");
      const width = Number(pages[index].dataset.pageWidth);
      const height = Number(pages[index].dataset.pageHeight);
      svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
      svg.setAttribute("width", width);
      svg.setAttribute("height", height);
      svg.removeAttribute("style");
      tagPage(page, record);
      return inlineSvg(svg);
    });
    const scenes = timelines.map((timeline, index) => {
      const selected = records.flatMap((record, position) => record.id === String(timeline.id) ? [position] : []);
      const frameCount = selected.length;
      const clamp = value => Math.max(0, Math.min(frameCount - 1, value));
      const blocks = timeline.blocks;
      const morphAnimations = [];
      const record = records[selected[0]];
      for (const morph of record?.morphs || []) {
        for (const block of blocks) {
          const entries = record.scope.variables[morph.state]?.[String(block.index)] || [];
          for (const [, hold, duration, , , effect] of entries) {
            if (!effect) continue;
            const span = block.end_frame - block.start_frame;
            const at = time => block.start_frame + (block.duration ? Math.round(span * time / block.duration) : 0);
            morphAnimations.push({ id: morph.id, effect, start_frame: at(hold), end_frame: at(hold + duration) });
          }
        }
      }
      return {
        id: String(timeline.id), index, name: timeline.title || String(timeline.id),
        fps: timeline.fps, duration: timeline.duration, autoplay: timeline.autoplay,
        frameCount, frames: selected.map(position => frames[position]), blocks, morphAnimations,
        cuts: [...new Map(blocks.filter(block => block.cut).map(block => [clamp(block.end_frame), { frame: clamp(block.end_frame), loop: block.loop }])).values()],
        keyframes: [...new Set([0, frameCount - 1, ...blocks.flatMap(block => [clamp(block.start_frame), clamp(block.end_frame)])])].sort((a, b) => a - b),
      };
    });
    return globalThis.GlissadeMorphRuntime.validateManifest({ schemaVersion: 1, scenes });
  }

  async function compile(mainContent) {
    const typst = globalThis.$typst;
    const mainFilePath = "/glissade-playground.typ";
    await typst.addSource(mainFilePath, mainContent);
    const compiler = await typst.getCompiler();
    const discovery = await compiler.runWithWorld({ mainFilePath, inputs: { query: "1" } }, async world => {
      const result = await world.compile();
      if (result.hasError) throw new Error(JSON.stringify(result.diagnostics));
      return world.query({ selector: "metadata", field: "value" });
    });
    const { vector, metadata } = await compiler.runWithWorld({ mainFilePath, inputs: { query: "0" } }, async world => {
      const result = await world.compile();
      if (result.hasError) throw new Error(JSON.stringify(result.diagnostics));
      return { vector: (await world.vector()).result, metadata: await world.query({ selector: "metadata", field: "value" }) };
    });
    const svg = await typst.svg({ vectorData: vector });
    return buildManifest(svg, metadata, discovery);
  }

  globalThis.GlissadePlaygroundBridge = { compile, buildManifest, tagPage };
})();
