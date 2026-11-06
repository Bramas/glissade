(() => {
  const header = `#import "glissade.typ": *

#set page(width: 360pt, height: 270pt, margin: 24pt)
#set text(font: "New Computer Modern", size: 18pt)
#show: deck.with(fps: 12)
`;

  const examples = [
    {
      id: "hello",
      label: "Animate a value",
      source: `${header}
#slide(title: "Hello", autoplay: true)[
  = Hello Glissade

  #init(width: 40pt)
  #animate(width: 280pt, duration: 1)
  #wait(duration: .3)
  #animate(width: 40pt, duration: 1)
  #cut(loop: true)

  #v(24pt)
  #context rect(
    width: a("width"),
    height: 32pt,
    radius: 4pt,
    fill: rgb("#2f5e9e"),
  )
]
`,
    },
    {
      id: "formula-morph",
      label: "Formula morph",
      source: `${header}
#slide(title: "Formula morph", autoplay: true)[
  = Move a term across
  #v(30pt)

  // Parts with the same content keep their identity between states.
  #init(eq: formula($part(a) + part(b) part(=) part(c)$))
  #animate(eq: formula($part(a) part(=) part(c) - part(b)$), duration: 1.2)
  #wait(duration: .6)
  #cut(loop: true)

  #align(center, text(size: 34pt, context glissade-morph("eq")))
]
`,
    },
    {
      id: "create",
      label: "Draw-in with create",
      source: `${header}
#slide(title: "Create", autoplay: true)[
  = Introduce content
  #v(24pt)

  #create(card: rect(
    width: 220pt, height: 90pt, radius: 8pt,
    fill: rgb("#d8e9df"), stroke: 1pt + rgb("#246b61"),
  )[
    #align(center + horizon, text(weight: "bold", fill: rgb("#246b61"))[New idea])
  ], duration: 1.5)
  #wait(duration: .5)
  #cut(loop: true)

  #align(center, context glissade-morph("card"))
]
`,
    },
    {
      id: "cuts",
      label: "Cuts and two slides",
      source: `${header}
#slide(title: "Steps")[
  = Playback pauses at cuts

  #init(step: 0)
  #animate(step: 1, duration: .5)
  #cut()
  #animate(step: 2, duration: .5)
  #cut()
  #animate(step: 3, duration: .5)

  #v(20pt)
  #context grid(
    columns: 3, gutter: 10pt,
    ..range(1, 4).map(i => rect(
      width: 90pt, height: 56pt, radius: 6pt,
      fill: if a("step") >= i { rgb("#2f5e9e") } else { rgb("#dfe6e3") },
    )),
  )
]

#slide(title: "Next")[
  = Second slide
  #init(x: 0pt)
  #animate(x: 240pt, duration: 1)
  #context place(dx: a("x"), dy: 40pt, circle(radius: 12pt, fill: rgb("#246b61")))
]
`,
    },
    {
      id: "transitions",
      label: "Transition curves",
      source: `${header}
#let row(label, y, x, color) = [
  #place(dy: y, text(size: 11pt, fill: rgb("#526064"), label))
  #place(dx: 60pt, dy: y + 6pt, line(length: 230pt, stroke: 1pt + rgb("#d5ddda")))
  #place(dx: 60pt + x, dy: y, circle(radius: 7pt, fill: color))
]

#slide(title: "Transitions", autoplay: true)[
  = Interpolation curves

  #init(lin: 0pt, smo: 0pt, sin-x: 0pt)
  #animate(lin: 216pt, duration: 1.2, transition: linear)
  #meanwhile(smo: 216pt, duration: 1.2, transition: smooth)
  #meanwhile(sin-x: 216pt, duration: 1.2, transition: sin)
  #wait(duration: .5)
  #cut(loop: true)

  #context [
    #row("linear", 20pt, a("lin"), rgb("#2f5e9e"))
    #row("smooth", 60pt, a("smo"), rgb("#246b61"))
    #row("sin", 100pt, a("sin-x"), rgb("#b24a7b"))
  ]
]
`,
    },
  ];

  const STORAGE_SOURCE = "glissade.playground.source.v2";
  const STORAGE_EXAMPLE = "glissade.playground.example.v2";
  const LIBRARY_PATH = "/glissade.typ";
  const MAIN_PATH = "/main.typ";

  const $ = selector => document.querySelector(selector);
  const input = $("#typst-source");
  const highlightLayer = $(".editor-highlight");
  const gutterLines = $(".editor-gutter-lines");
  const preview = $("#typst-preview");
  const status = $("[data-status]");
  const exampleSelect = $("[data-example-select]");
  const diagnosticsBox = $("[data-diagnostics]");
  const diagnosticsList = $("[data-diagnostics-list]");
  const diagnosticsTitle = $("[data-diagnostics-title]");
  const frameControls = $(".frame-controls");
  const frameStatus = $("[data-frame-status]");
  const framePlayButton = $('[data-frame-action="play"]');
  const scrubber = $("[data-frame-scrubber]");
  const scrubberMarks = $("[data-scrubber-marks]");
  const toast = $("[data-toast]");

  let bundledLibrary = "";
  let compilerReady = false;
  let compileTimer = 0;
  let compileVersion = 0;
  let compileQueue = Promise.resolve();
  let stageRenderer = null;
  let frameState = null;
  let frameTimer = 0;
  let playbackVersion = 0;
  let errorLines = new Set();
  let lastLineCount = 0;
  let autoplayNext = false;

  // ---------- status and messages ----------

  function setStatus(text, mode = "") {
    status.textContent = text;
    status.dataset.mode = mode;
  }

  function showMessage(text, mode = "") {
    stopFrames();
    frameControls.hidden = true;
    if (stageRenderer) stageRenderer.clear();
    stageRenderer = null;
    frameState = null;
    const message = document.createElement("div");
    message.className = "preview-message" + (mode ? " " + mode : "");
    message.textContent = text;
    preview.replaceChildren(message);
  }

  let toastTimer = 0;
  function notify(text) {
    toast.textContent = text;
    toast.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toast.hidden = true; }, 2200);
  }

  // ---------- editor ----------

  function updateHighlight() {
    const source = input.value;
    const highlighted = globalThis.GlissadeHighlight?.typst
      ? globalThis.GlissadeHighlight.typst(source)
      : source.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
    highlightLayer.innerHTML = highlighted + "\n";
    updateGutter();
  }

  function updateGutter(force = false) {
    const count = input.value.split("\n").length;
    if (!force && count === lastLineCount) return;
    lastLineCount = count;
    const fragment = document.createDocumentFragment();
    for (let line = 1; line <= count; line += 1) {
      const item = document.createElement("div");
      item.textContent = String(line);
      if (errorLines.has(line)) item.className = "has-error";
      fragment.append(item);
    }
    gutterLines.replaceChildren(fragment);
  }

  function syncScroll() {
    highlightLayer.scrollTop = input.scrollTop;
    highlightLayer.scrollLeft = input.scrollLeft;
    gutterLines.style.transform = `translateY(${-input.scrollTop}px)`;
  }

  function setSource(source) {
    input.value = source;
    input.scrollTop = 0;
    input.scrollLeft = 0;
    updateHighlight();
    syncScroll();
  }

  function replaceSelection(text, selectStart, selectEnd) {
    // execCommand keeps the browser undo stack intact.
    input.focus();
    if (!document.execCommand?.("insertText", false, text)) {
      input.setRangeText(text, input.selectionStart, input.selectionEnd, "end");
      input.dispatchEvent(new Event("input"));
    }
    if (selectStart != null) input.setSelectionRange(selectStart, selectEnd ?? selectStart);
  }

  function handleEditorKeys(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      compile();
      return;
    }
    if (event.key === "Tab" && !event.altKey && !event.metaKey && !event.ctrlKey) {
      event.preventDefault();
      const { value, selectionStart: start, selectionEnd: end } = input;
      const lineStart = value.lastIndexOf("\n", start - 1) + 1;
      if (start === end && !event.shiftKey) {
        replaceSelection("  ");
        return;
      }
      const blockEnd = value.indexOf("\n", end - (end > start && value[end - 1] === "\n" ? 1 : 0));
      const stop = blockEnd === -1 ? value.length : blockEnd;
      const lines = value.slice(lineStart, stop).split("\n");
      const changed = lines.map(line => event.shiftKey ? line.replace(/^ {1,2}/, "") : "  " + line).join("\n");
      input.setSelectionRange(lineStart, stop);
      replaceSelection(changed, lineStart, lineStart + changed.length);
      return;
    }
    if (event.key === "Enter" && !event.shiftKey) {
      const { value, selectionStart: start } = input;
      const lineStart = value.lastIndexOf("\n", start - 1) + 1;
      const indent = value.slice(lineStart, start).match(/^[ \t]*/)[0];
      const opens = /[[({]\s*$/.test(value.slice(lineStart, start));
      if (!indent && !opens) return;
      event.preventDefault();
      replaceSelection("\n" + indent + (opens ? "  " : ""));
    }
  }

  // ---------- persistence and sharing ----------

  function storageGet(key) {
    try { return localStorage.getItem(key); } catch { return null; }
  }

  function storageSet(key, value) {
    try { localStorage.setItem(key, value); } catch {}
  }

  function persistSource() {
    storageSet(STORAGE_SOURCE, input.value);
  }

  function toBase64Url(bytes) {
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
  }

  function fromBase64Url(text) {
    const binary = atob(text.replaceAll("-", "+").replaceAll("_", "/"));
    return Uint8Array.from(binary, char => char.charCodeAt(0));
  }

  async function streamBytes(bytes, transform) {
    const stream = new Blob([bytes]).stream().pipeThrough(transform);
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }

  async function encodeShare(source) {
    const bytes = new TextEncoder().encode(source);
    if ("CompressionStream" in window) {
      return "z:" + toBase64Url(await streamBytes(bytes, new CompressionStream("deflate-raw")));
    }
    return "t:" + toBase64Url(bytes);
  }

  async function decodeShare(hash) {
    const value = new URLSearchParams(hash.replace(/^#/, "")).get("code");
    if (!value) return null;
    const [kind, payload] = [value.slice(0, 2), value.slice(2)];
    const bytes = fromBase64Url(payload);
    if (kind === "z:") return new TextDecoder().decode(await streamBytes(bytes, new DecompressionStream("deflate-raw")));
    if (kind === "t:") return new TextDecoder().decode(bytes);
    return null;
  }

  async function copyShareLink() {
    try {
      const url = new URL(location.href);
      url.hash = "code=" + await encodeShare(input.value);
      history.replaceState(null, "", url);
      await navigator.clipboard.writeText(url.href);
      notify("Link copied. It contains the full source.");
    } catch {
      notify("Could not copy. The link is in the address bar.");
    }
  }

  function downloadSource() {
    const blob = new Blob([input.value], { type: "text/plain" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = "main.typ";
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  }

  function loadExample(id, { play = true } = {}) {
    const example = examples.find(item => item.id === id) || examples[0];
    exampleSelect.value = example.id;
    storageSet(STORAGE_EXAMPLE, example.id);
    setSource(example.source);
    persistSource();
    if (location.hash) history.replaceState(null, "", location.pathname + location.search);
    autoplayNext = play;
    scheduleCompile(0);
  }

  // ---------- diagnostics ----------

  function parseRange(range) {
    const match = /^(\d+):(\d+)/.exec(range || "");
    return match ? { line: Number(match[1]) + 1, column: Number(match[2]) + 1 } : null;
  }

  function displayPath(path) {
    if (!path || path === MAIN_PATH) return "main.typ";
    if (path === LIBRARY_PATH) return "glissade.typ";
    return path.replace(/^\//, "");
  }

  function showDiagnostics(error) {
    const diagnostics = Array.isArray(error?.diagnostics)
      ? error.diagnostics
      : [{ severity: "error", message: String(error?.message || error), path: "", range: "" }];
    const items = diagnostics.map(item => ({ ...item, at: parseRange(item.range) }));
    errorLines = new Set(items
      .filter(item => item.at && (!item.path || item.path === MAIN_PATH))
      .map(item => item.at.line));
    updateGutter(true);

    const errors = items.filter(item => item.severity !== "hint" && item.severity !== "warning");
    diagnosticsTitle.textContent = errors.length > 1 ? `${errors.length} errors` : "Compile error";
    diagnosticsList.replaceChildren(...items.map(item => {
      const row = document.createElement("li");
      row.dataset.severity = item.severity || "error";
      const label = document.createElement("span");
      label.className = "diag-severity";
      label.textContent = item.severity === "hint" ? "trace" : (item.severity || "error");
      const message = document.createElement("span");
      message.className = "diag-message";
      message.textContent = item.message;
      row.append(label, message);
      if (item.at) {
        const inMain = !item.path || item.path === MAIN_PATH;
        const location = document.createElement(inMain ? "button" : "span");
        location.className = "diag-location";
        location.textContent = `${displayPath(item.path)}:${item.at.line}:${item.at.column}`;
        if (inMain) {
          location.type = "button";
          location.title = "Jump to this line";
          location.addEventListener("click", () => jumpTo(item.at.line, item.at.column));
        }
        row.append(location);
      }
      return row;
    }));
    diagnosticsBox.hidden = false;
  }

  function clearDiagnostics() {
    diagnosticsBox.hidden = true;
    if (errorLines.size) {
      errorLines = new Set();
      updateGutter(true);
    }
  }

  function jumpTo(line, column) {
    const lines = input.value.split("\n");
    let offset = 0;
    for (let index = 0; index < line - 1 && index < lines.length; index += 1) offset += lines[index].length + 1;
    offset += Math.max(0, column - 1);
    input.focus();
    input.setSelectionRange(offset, offset);
    const lineHeight = parseFloat(getComputedStyle(input).lineHeight) || 22;
    input.scrollTop = Math.max(0, (line - 4) * lineHeight);
    syncScroll();
  }

  // ---------- preview and playback ----------

  function refitPreview() {
    const stack = preview.querySelector(".glissade-stage-stack");
    if (!stack) return;
    const pad = preview.clientWidth < 520 ? 24 : 48;
    const width = Number(stack.dataset.glissadeWidth);
    const height = Number(stack.dataset.glissadeHeight);
    const scale = Math.max(0.05, Math.min((preview.clientWidth - pad) / width, (preview.clientHeight - pad) / height));
    stack.style.width = width * scale + "px";
    stack.style.height = height * scale + "px";
  }

  function setPlaying(playing) {
    framePlayButton.classList.toggle("is-playing", playing);
    framePlayButton.setAttribute("aria-label", playing ? "Pause" : "Play");
  }

  function stopFrames() {
    playbackVersion += 1;
    cancelAnimationFrame(frameTimer);
    frameTimer = 0;
    setPlaying(false);
  }

  function updateFrameUi() {
    if (!frameState) return;
    const { scene, frame } = frameState.frames[frameState.index];
    const slides = frameState.sceneCount;
    frameStatus.textContent = `${slides > 1 ? `Slide ${scene.index + 1}/${slides} · ` : ""}Frame ${frame + 1}/${scene.frameCount}`;
    scrubber.value = String(frameState.index);
  }

  async function showFrame(index) {
    if (!frameState || !stageRenderer) return;
    const currentState = frameState;
    const renderer = stageRenderer;
    frameState.index = Math.max(0, Math.min(index, frameState.frames.length - 1));
    const requestedIndex = frameState.index;
    updateFrameUi();
    const { scene, frame } = frameState.frames[frameState.index];
    await renderer.render(scene, frame);
    if (frameState !== currentState || stageRenderer !== renderer || frameState.index !== requestedIndex) return;
    refitPreview();
  }

  function buildScrubberMarks() {
    const total = frameState.frames.length;
    const marks = [];
    let offset = 0;
    for (const scene of frameState.scenes) {
      if (offset > 0) marks.push({ at: offset, kind: "slide" });
      for (const cut of scene.cuts || []) {
        if (cut.frame < scene.frameCount - 1) marks.push({ at: offset + cut.frame, kind: "cut" });
      }
      offset += scene.frameCount;
    }
    scrubberMarks.replaceChildren(...marks.map(mark => {
      const tick = document.createElement("i");
      tick.className = "mark-" + mark.kind;
      tick.style.left = total > 1 ? `${(mark.at / (total - 1)) * 100}%` : "0";
      return tick;
    }));
  }

  async function setupFrames(manifest, { keepPosition }) {
    const previous = frameState && keepPosition ? frameState.frames[frameState.index] : null;
    stopFrames();
    if (stageRenderer) stageRenderer.clear();
    preview.replaceChildren();
    stageRenderer = GlissadeMorphRuntime.createStageRenderer(preview);
    const frames = manifest.scenes.flatMap(scene => scene.frames.map((_, frame) => ({ scene, frame })));
    frameState = { index: 0, frames, scenes: manifest.scenes, sceneCount: manifest.scenes.length };
    if (frames.length === 0) {
      showMessage("This deck has no slides yet. Add a #slide[...] block.");
      return;
    }
    let index = 0;
    if (previous) {
      const found = frames.findIndex(item => item.scene.index === previous.scene.index
        && item.frame === Math.min(previous.frame, item.scene.frameCount - 1));
      if (found >= 0) index = found;
    }
    scrubber.max = String(frames.length - 1);
    buildScrubberMarks();
    frameControls.hidden = false;
    await showFrame(index);
  }

  function togglePlayback() {
    if (!frameState) return;
    if (frameTimer) { stopFrames(); return; }
    const current = frameState.frames[frameState.index];
    let start = frameState.index;
    if (start >= frameState.frames.length - 1) start = 0;
    else if (current.frame === current.scene.frameCount - 1) start += 1;
    play(start);
  }

  function play(startIndex) {
    stopFrames();
    if (!frameState) return;
    setPlaying(true);
    const startedAt = performance.now();
    const version = ++playbackVersion;
    const initial = frameState.frames[startIndex];
    const tick = async now => {
      if (!frameState || version !== playbackVersion) return;
      const steps = Math.floor((now - startedAt) * initial.scene.fps / 1000);
      const target = GlissadeMorphRuntime.advancePlaybackFrame(initial.scene, initial.frame, steps);
      const index = startIndex - initial.frame + target.frame;
      try {
        if (index !== frameState.index || steps === 0) await showFrame(index);
        if (version !== playbackVersion) return;
        if (target.cut || target.ended) { stopFrames(); return; }
        frameTimer = requestAnimationFrame(tick);
      } catch (error) {
        stopFrames();
        showDiagnostics(error);
      }
    };
    frameTimer = requestAnimationFrame(tick);
  }

  function step(delta) {
    stopFrames();
    if (frameState) showFrame(frameState.index + delta).catch(showDiagnostics);
  }

  // ---------- compilation ----------

  function scheduleCompile(delay = 400) {
    clearTimeout(compileTimer);
    compileTimer = setTimeout(compile, delay);
  }

  async function compile() {
    clearTimeout(compileTimer);
    persistSource();
    if (!bundledLibrary || !compilerReady) return;
    if (!globalThis.$typst?.svg) {
      setStatus("Compiler unavailable", "error");
      return;
    }
    const version = ++compileVersion;
    const source = input.value;
    const wantsAutoplay = autoplayNext;
    autoplayNext = false;
    compileQueue = compileQueue.catch(() => {}).then(async () => {
      if (version !== compileVersion) return;
      setStatus("Compiling…", "busy");
      const startedAt = performance.now();
      try {
        const manifest = await GlissadePlaygroundBridge.compile(source, {
          files: { [LIBRARY_PATH]: bundledLibrary },
          mainFilePath: MAIN_PATH,
        });
        if (version !== compileVersion) return;
        const hadFrames = Boolean(frameState);
        await setupFrames(manifest, { keepPosition: !wantsAutoplay });
        if (version !== compileVersion) return;
        clearDiagnostics();
        setStatus(`Compiled in ${Math.round(performance.now() - startedAt)} ms`, "ok");
        const first = frameState?.frames[0];
        if (frameState && (wantsAutoplay || !hadFrames) && first?.scene.autoplay) play(0);
      } catch (error) {
        if (version !== compileVersion) return;
        setStatus("Error", "error");
        if (!frameState) showMessage("Fix the error below to see the preview.", "error");
        showDiagnostics(error);
      }
    });
    return compileQueue;
  }

  function markReady() {
    if (compilerReady) return;
    compilerReady = true;
    globalThis.$typst?.setCompilerInitOptions?.({
      getModule: () => "https://cdn.jsdelivr.net/npm/@myriaddreamin/typst-ts-web-compiler@0.7.0/pkg/typst_ts_web_compiler_bg.wasm",
    });
    globalThis.$typst?.setRendererInitOptions?.({
      getModule: () => "https://cdn.jsdelivr.net/npm/@myriaddreamin/typst-ts-renderer@0.7.0/pkg/typst_ts_renderer_bg.wasm",
    });
    setStatus("Compiling…", "busy");
    compile();
  }

  // ---------- startup ----------

  for (const example of examples) {
    const option = document.createElement("option");
    option.value = example.id;
    option.textContent = example.label;
    exampleSelect.append(option);
  }
  const custom = document.createElement("option");
  custom.value = "";
  custom.textContent = "Your edits";
  custom.hidden = true;
  exampleSelect.append(custom);

  function markCustomIfEdited() {
    const example = examples.find(item => item.id === exampleSelect.value);
    if (example && example.source !== input.value) {
      custom.hidden = false;
      exampleSelect.value = "";
    }
  }

  async function initialSource() {
    try {
      const shared = await decodeShare(location.hash);
      if (shared != null) return { source: shared, example: "" };
    } catch {
      notify("The shared link could not be decoded.");
    }
    const savedExample = storageGet(STORAGE_EXAMPLE) ?? examples[0].id;
    const saved = storageGet(STORAGE_SOURCE);
    if (saved != null && saved.trim()) return { source: saved, example: savedExample };
    const example = examples.find(item => item.id === savedExample) || examples[0];
    return { source: example.source, example: example.id };
  }

  if (/Mac|iPhone|iPad/.test(navigator.platform)) {
    for (const key of document.querySelectorAll("[data-mod-key]")) key.textContent = "⌘";
  }

  initialSource().then(({ source, example }) => {
    exampleSelect.value = examples.some(item => item.id === example) ? example : examples[0].id;
    setSource(source);
    markCustomIfEdited();
    if (bundledLibrary && compilerReady) compile();
  });

  fetch("glissade.generated.typ")
    .then(response => {
      if (!response.ok) throw new Error("The playground library bundle is missing. Run `npm run build:playground-lib` before serving the site locally.");
      return response.text();
    })
    .then(source => {
      bundledLibrary = source;
      if (compilerReady) compile();
    })
    .catch(error => {
      setStatus("Library unavailable", "error");
      showMessage(String(error?.message || error), "error");
    });

  input.addEventListener("input", () => {
    // A shared link is a snapshot; once edited, local storage holds the truth.
    if (location.hash.includes("code=")) history.replaceState(null, "", location.pathname + location.search);
    updateHighlight();
    markCustomIfEdited();
    scheduleCompile();
  });
  input.addEventListener("scroll", syncScroll);
  input.addEventListener("keydown", handleEditorKeys);

  exampleSelect.addEventListener("change", () => {
    if (exampleSelect.value) loadExample(exampleSelect.value);
  });
  $('[data-action="reset"]').addEventListener("click", () => {
    loadExample(exampleSelect.value || storageGet(STORAGE_EXAMPLE) || examples[0].id);
  });
  $('[data-action="share"]').addEventListener("click", copyShareLink);
  $('[data-action="download"]').addEventListener("click", downloadSource);

  $('[data-frame-action="previous"]').addEventListener("click", () => step(-1));
  $('[data-frame-action="next"]').addEventListener("click", () => step(1));
  framePlayButton.addEventListener("click", togglePlayback);
  scrubber.addEventListener("input", () => {
    stopFrames();
    if (frameState) showFrame(Number(scrubber.value)).catch(showDiagnostics);
  });

  preview.addEventListener("keydown", event => {
    if (event.key === " " || event.key === "k") { event.preventDefault(); togglePlayback(); }
    else if (event.key === "ArrowRight") { event.preventDefault(); step(event.shiftKey ? 10 : 1); }
    else if (event.key === "ArrowLeft") { event.preventDefault(); step(event.shiftKey ? -10 : -1); }
    else if (event.key === "Home") { event.preventDefault(); step(-Infinity); }
    else if (event.key === "End") { event.preventDefault(); step(Infinity); }
  });
  preview.addEventListener("click", () => preview.focus({ preventScroll: true }));

  window.addEventListener("resize", refitPreview);
  if ("ResizeObserver" in window) new ResizeObserver(refitPreview).observe(preview);

  const typstScript = $("#typst");
  typstScript.addEventListener("load", markReady);
  typstScript.addEventListener("error", () => {
    setStatus("Compiler failed to load", "error");
    showMessage("Could not load typst.ts from the CDN. Check your network connection and reload the page.", "error");
  });
  if (globalThis.$typst?.svg) markReady();
})();
