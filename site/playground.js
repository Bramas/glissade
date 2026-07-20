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

  function setStatus(text, mode = "") {
    status.textContent = text;
    status.dataset.mode = mode;
  }

  function showMessage(text, mode = "") {
    stopFrames();
    frameControls.hidden = true;
    preview.innerHTML = "";
    const message = document.createElement("div");
    message.className = "preview-message" + (mode ? " " + mode : "");
    message.textContent = text;
    preview.append(message);
  }

  function loadSource() {
    input.value = localStorage.getItem("glissade.playground.source.main") || mainSample;
    updateHighlight();
  }

  function persistSource() {
    localStorage.setItem("glissade.playground.source.main", input.value);
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

  function detectFps(source) {
    const match = source.match(/deck\.with\s*\([^)]*\bfps\s*:\s*(\d+(?:\.\d+)?)/);
    return match ? Math.max(1, Number(match[1])) : 5;
  }

  function parseTranslate(transform) {
    const total = { x: 0, y: 0 };
    for (const match of String(transform || "").matchAll(/translate\(\s*([-\d.]+)(?:[\s,]+([-\d.]+))?/g)) {
      total.x += Number(match[1]) || 0;
      total.y += Number(match[2]) || 0;
    }
    return total;
  }

  function fitPreviewSvg(svg, width, height) {
    if (!svg || !width || !height) return;
    const styles = getComputedStyle(preview);
    const pixels = value => Number(String(value || "0").replace("px", "")) || 0;
    const availableWidth = preview.clientWidth - pixels(styles.paddingLeft) - pixels(styles.paddingRight);
    const availableHeight = preview.clientHeight - pixels(styles.paddingTop) - pixels(styles.paddingBottom);
    const scale = Math.min(availableWidth / width, availableHeight / height);
    if (!Number.isFinite(scale) || scale <= 0) return;
    const fittedWidth = Math.max(1, Math.floor(width * scale));
    const fittedHeight = Math.max(1, Math.floor(height * scale));
    svg.style.width = `${fittedWidth}px`;
    svg.style.height = `${fittedHeight}px`;
  }

  function refitPreview() {
    const svg = preview.querySelector("svg");
    if (!svg) return;
    if (frameState) {
      const box = frameState.pageBoxes[frameState.index];
      fitPreviewSvg(svg, box?.width, box?.height);
      return;
    }
    const page = svg.querySelector(".typst-page");
    fitPreviewSvg(
      svg,
      Number(page?.dataset.pageWidth) || Number(svg.dataset.width) || Number(svg.getAttribute("width")),
      Number(page?.dataset.pageHeight) || Number(svg.dataset.height) || Number(svg.getAttribute("height")),
    );
  }

  function stopFrames() {
    clearInterval(frameTimer);
    frameTimer = 0;
    if (framePlayButton) framePlayButton.textContent = "\u25b6";
  }

  function showFrame(index) {
    if (!frameState) return;
    const { svg, pages, originals, pageBoxes } = frameState;
    frameState.index = (index + pages.length) % pages.length;
    pages.forEach((page, pageIndex) => {
      page.hidden = pageIndex !== frameState.index;
      page.style.display = pageIndex === frameState.index ? "" : "none";
      page.setAttribute("transform", originals[pageIndex]);
    });
    const page = pages[frameState.index];
    const box = pageBoxes[frameState.index];
    if (box) {
      const shiftX = -box.x;
      const shiftY = -box.y;
      const original = originals[frameState.index];
      page.setAttribute("transform", `translate(${shiftX} ${shiftY}) ${original}`.trim());
      svg.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
      svg.setAttribute("width", box.width);
      svg.setAttribute("height", box.height);
      fitPreviewSvg(svg, box.width, box.height);
    }
    frameStatus.textContent = `Frame ${frameState.index + 1} / ${pages.length} · ${frameState.fps} fps`;
  }

  function setupFrames() {
    stopFrames();
    const svg = preview.querySelector("svg");
    if (!svg) {
      frameControls.hidden = true;
      frameState = null;
      return;
    }
    const pages = [...svg.querySelectorAll(".typst-page")];
    if (pages.length <= 1) {
      frameControls.hidden = true;
      frameState = null;
      refitPreview();
      return;
    }
    const originals = pages.map(page => page.getAttribute("transform") || "");
    const pageBoxes = pages.map(page => {
      const translation = parseTranslate(page.getAttribute("transform"));
      return {
        x: translation.x,
        y: translation.y,
        width: Math.max(1, Number(page.dataset.pageWidth) || Number(svg.dataset.width) || 1),
        height: Math.max(1, Number(page.dataset.pageHeight) || Number(svg.dataset.height) / pages.length || 1),
      };
    });
    frameState = {
      svg,
      pages,
      originals,
      pageBoxes,
      fps: detectFps(input.value),
      index: 0,
    };
    frameControls.hidden = false;
    showFrame(0);
  }

  function toggleFrames() {
    if (!frameState) return;
    if (frameTimer) {
      stopFrames();
      return;
    }
    framePlayButton.textContent = "\u275a\u275a";
    frameTimer = setInterval(() => showFrame(frameState.index + 1), 1000 / frameState.fps);
  }

  function scheduleCompile(delay = 350) {
    clearTimeout(compileTimer);
    compileTimer = setTimeout(compile, delay);
  }

  async function compile() {
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
    setStatus("Compiling…");
    try {
      const svg = await globalThis.$typst.svg({ mainContent: compilerInput() });
      if (version !== compileVersion) return;
      preview.innerHTML = svg;
      setupFrames();
      setStatus("Rendered");
    } catch (error) {
      if (version !== compileVersion) return;
      setStatus("Compile error", "error");
      showMessage(String(error?.message || error), "error");
    }
  }

  function markReady() {
    compilerReady = true;
    if (globalThis.$typst?.setCompilerInitOptions) {
      globalThis.$typst.setCompilerInitOptions({
        getModule: () =>
          "https://cdn.jsdelivr.net/npm/@myriaddreamin/typst-ts-web-compiler/pkg/typst_ts_web_compiler_bg.wasm",
      });
    }
    if (globalThis.$typst?.setRendererInitOptions) {
      globalThis.$typst.setRendererInitOptions({
        getModule: () =>
          "https://cdn.jsdelivr.net/npm/@myriaddreamin/typst-ts-renderer/pkg/typst_ts_renderer_bg.wasm",
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
    if (frameState) showFrame(frameState.index - 1);
  });
  document.querySelector('[data-frame-action="next"]').addEventListener("click", () => {
    stopFrames();
    if (frameState) showFrame(frameState.index + 1);
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
