(() => {
  const defaultExample = `#import "glissade.typ": *

#set page(width: 128mm, height: 96mm, margin: 10mm)
#set text(size: 18pt)

#show: deck.with(fps: 5)
#slide[
    = Hello

    #init(a: 1)
    #animate(a:5)
    #context [
      a value : #a("a")
    ]
]`;

  const mainSample = defaultExample;
  const morphExample = `#import "glissade.typ": *
#set page(width: 128mm, height: 96mm, margin: 10mm)
#set text(size: 22pt)
#show: deck.with(fps: 12)
#slide[
  = Formula morph
  #init(eq: formula($part(a) = part(b)$))
  #animate(eq: formula($part(b) = part(a) / (1+c)$))
  #context glissade-morph("eq")
]`;

  const input = document.querySelector("#typst-source");
  const highlightLayer = document.querySelector(".editor-highlight");
  const preview = document.querySelector("#typst-preview");
  const status = document.querySelector("[data-status]");
  const compileButton = document.querySelector('[data-action="compile"]');
  const resetButton = document.querySelector('[data-action="reset"]');
  const defaultButton = document.querySelector('[data-action="default-example"]');
  const frameControls = document.querySelector(".frame-controls");
  const frameStatus = document.querySelector("[data-frame-status]");
  const framePlayButton = document.querySelector('[data-frame-action="play"]');
  let bundledLibrary = "";
  let compileTimer = 0;
  let compileVersion = 0;
  let compilerReady = false;
  let frameState = null;
  let frameTimer = 0;
  let playbackVersion = 0;

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
    preview.innerHTML = "";
    const message = document.createElement("div");
    message.className = "preview-message" + (mode ? " " + mode : "");
    message.textContent = text;
    preview.append(message);
  }

  function loadSource() {
    try { input.value = localStorage.getItem("glissade.playground.source.main") || mainSample; }
    catch { input.value = mainSample; }
    updateHighlight();
  }

  function persistSource() {
    try { localStorage.setItem("glissade.playground.source.main", input.value); } catch {}
  }

  function updateHighlight() {
    const highlighted = globalThis.GlissadeHighlight?.typst
      ? globalThis.GlissadeHighlight.typst(input.value)
      : input.value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
    highlightLayer.innerHTML = highlighted + "\n";
  }

  function compilerInput() {
    return input.value.replace(/^\s*#import\s+"glissade\.typ"\s*:\s*\*\s*$/m, bundledLibrary);
  }

  function refitPreview() {
    const stack = preview.querySelector(".glissade-stage-stack");
    if (!stack) return;
    const scale = Math.min((preview.clientWidth - 56) / Number(stack.dataset.glissadeWidth),
      (preview.clientHeight - 56) / Number(stack.dataset.glissadeHeight));
    stack.style.width = Number(stack.dataset.glissadeWidth) * scale + "px";
    stack.style.height = Number(stack.dataset.glissadeHeight) * scale + "px";
  }

  let stageRenderer = null;
  let manifest = null;
  let compileQueue = Promise.resolve();

  function stopFrames() {
    playbackVersion += 1;
    cancelAnimationFrame(frameTimer);
    frameTimer = 0;
    if (framePlayButton) framePlayButton.textContent = "\u25b6";
  }

  async function showFrame(index) {
    if (!frameState || !stageRenderer) return;
    const currentState = frameState;
    const renderer = stageRenderer;
    frameState.index = Math.max(0, Math.min(index, frameState.frames.length - 1));
    const requestedIndex = frameState.index;
    const { scene, frame } = frameState.frames[frameState.index];
    await stageRenderer.render(scene, frame);
    if (frameState !== currentState || stageRenderer !== renderer || frameState.index !== requestedIndex) return;
    refitPreview();
    frameStatus.textContent = `Slide ${scene.index + 1} · Frame ${frame + 1} / ${scene.frameCount} · ${scene.fps} fps`;
  }

  async function setupFrames(value) {
    stopFrames();
    manifest = value;
    if (stageRenderer) stageRenderer.clear();
    preview.replaceChildren();
    stageRenderer = GlissadeMorphRuntime.createStageRenderer(preview);
    frameState = { index: 0, frames: manifest.scenes.flatMap(scene =>
      scene.frames.map((_, frame) => ({ scene, frame }))) };
    frameControls.hidden = frameState.frames.length <= 1;
    await showFrame(0);
  }

  function toggleFrames() {
    if (!frameState) return;
    if (frameTimer) { stopFrames(); return; }
    if (frameState.index >= frameState.frames.length - 1) showFrame(0).catch(showCompileError);
    else {
      const current = frameState.frames[frameState.index];
      if (current.frame === current.scene.frameCount - 1) showFrame(frameState.index + 1).catch(showCompileError);
    }
    framePlayButton.textContent = "\u275a\u275a";
    const startedAt = performance.now();
    const startIndex = frameState.index;
    const version = ++playbackVersion;
    const tick = async now => {
      if (!frameTimer || !frameState || version !== playbackVersion) return;
      const initial = frameState.frames[startIndex];
      const steps = Math.floor((now - startedAt) * initial.scene.fps / 1000);
      const target = GlissadeMorphRuntime.advancePlaybackFrame(initial.scene, initial.frame, steps);
      const index = startIndex - initial.frame + target.frame;
      try {
        if (index !== frameState.index) await showFrame(index);
        if (!frameTimer || version !== playbackVersion) return;
        if (target.cut || target.ended) { stopFrames(); return; }
        frameTimer = requestAnimationFrame(tick);
      } catch (error) { showCompileError(error); }
    };
    frameTimer = requestAnimationFrame(tick);
  }

  function showCompileError(error) {
    stopFrames();
    setStatus("Compile error", "error");
    showMessage(String(error?.message || error), "error");
  }

  function scheduleCompile(delay = 350) {
    compileVersion += 1;
    clearTimeout(compileTimer);
    compileTimer = setTimeout(compile, delay);
  }

  async function compile() {
    clearTimeout(compileTimer);
    persistSource();
    if (!bundledLibrary) {
      setStatus("Loading glissade.typ…");
      return;
    }
    if (!compilerReady || !globalThis.$typst?.svg) {
      setStatus("typst.ts unavailable", "error");
      showMessage("The browser compiler is not loaded yet. Check the network connection or try again.", "error");
      return;
    }

    const version = ++compileVersion;
    const source = compilerInput();
    compileQueue = compileQueue.catch(() => {}).then(async () => {
      if (version !== compileVersion) return;
      setStatus("Compiling…");
      try {
        const value = await GlissadePlaygroundBridge.compile(source);
        if (version !== compileVersion) return;
        await setupFrames(value);
        if (version !== compileVersion) return;
        setStatus("Rendered");
      } catch (error) {
        if (version === compileVersion) showCompileError(error);
      }
    });
    return compileQueue;
  }

  function markReady() {
    compilerReady = true;
    if (globalThis.$typst?.setCompilerInitOptions) {
      globalThis.$typst.setCompilerInitOptions({
        getModule: () =>
          "https://cdn.jsdelivr.net/npm/@myriaddreamin/typst-ts-web-compiler@0.7.0/pkg/typst_ts_web_compiler_bg.wasm",
      });
    }
    if (globalThis.$typst?.setRendererInitOptions) {
      globalThis.$typst.setRendererInitOptions({
        getModule: () =>
          "https://cdn.jsdelivr.net/npm/@myriaddreamin/typst-ts-renderer@0.7.0/pkg/typst_ts_renderer_bg.wasm",
      });
    }
    setStatus("Ready");
    compile();
  }

  loadSource();
  fetch("glissade.generated.typ")
    .then(response => {
      if (!response.ok) throw new Error("The playground bundle has not been generated. Run `npm run build:playground-lib` before serving the site locally.");
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
    persistSource();
    updateHighlight();
    scheduleCompile();
  });
  input.addEventListener("scroll", () => {
    highlightLayer.scrollTop = input.scrollTop;
    highlightLayer.scrollLeft = input.scrollLeft;
  });
  compileButton.addEventListener("click", compile);
  document.querySelector('[data-action="morph-example"]').addEventListener("click", () => {
    input.value = morphExample;
    updateHighlight();
    scheduleCompile(0);
  });
  defaultButton.addEventListener("click", () => {
    input.value = defaultExample;
    persistSource();
    updateHighlight();
    scheduleCompile(0);
  });
  resetButton.addEventListener("click", () => {
    input.value = mainSample;
    persistSource();
    updateHighlight();
    scheduleCompile(0);
  });
  document.querySelector('[data-frame-action="previous"]').addEventListener("click", () => {
    stopFrames();
    if (frameState) showFrame(frameState.index - 1).catch(showCompileError);
  });
  document.querySelector('[data-frame-action="next"]').addEventListener("click", () => {
    stopFrames();
    if (frameState) showFrame(frameState.index + 1).catch(showCompileError);
  });
  framePlayButton.addEventListener("click", toggleFrames);
  window.addEventListener("resize", refitPreview);
  if ("ResizeObserver" in window) {
    new ResizeObserver(refitPreview).observe(preview);
  }

  const typstScript = document.querySelector("#typst");
  typstScript.addEventListener("load", markReady);
  typstScript.addEventListener("error", () => {
    setStatus("typst.ts failed to load", "error");
    showMessage("Could not load typst.ts from the CDN. A vendored bundle would make this page work offline.", "error");
  });
  if (globalThis.$typst?.svg) markReady();
})();
