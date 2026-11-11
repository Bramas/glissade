// The hero "instrument": the Typst source, the stage and the timeline of one
// real export, kept in step by a shared frame index. The frames come from the
// exported HTML in examples/ and are drawn by the same runtime as a
// presentation. If anything fails, the export itself is shown in an iframe.
(() => {
  const panel = document.querySelector("[data-instrument]");
  if (!panel) return;

  const runtime = globalThis.GlissadeMorphRuntime;
  const highlight = globalThis.GlissadeHighlight;
  const part = name => panel.querySelector(`[data-ins-${name}]`);
  const tabs = [...panel.querySelectorAll("[data-example]")];
  const code = part("code");
  const file = part("file");
  const canvas = part("canvas");
  const openLink = part("open");
  const editLink = part("edit");
  const playButton = part("play");
  const timeLabel = part("time");
  const frameLabel = part("frame");
  const track = part("track");
  const ruler = part("ruler");
  const blocksLayer = part("blocks");
  const cutsLayer = part("cuts");
  const playhead = part("playhead");
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const libraryImport = /^#import "[^"]*lib\.typ": \*/m;
  const texts = new Map();

  let renderer = null;
  let example = "";        // file name of the selected example
  let scene = null;
  let links = [];          // per timeline block: { element, lines }
  let frame = 0;
  let activeBlock = -1;
  let room = { width: 0, height: 0 };
  let selection = 0;       // invalidates loads of a tab that is no longer selected
  let playback = 0;        // invalidates ticks of a playback that was stopped
  let playing = false;
  let wantsPlay = !reducedMotion.matches;
  let onScreen = true;
  let scrubbing = false;

  // ---------- loading ----------

  function text(url) {
    if (!texts.has(url)) {
      texts.set(url, fetch(url).then(response => {
        if (!response.ok) throw new Error(`${url}: ${response.status}`);
        return response.text();
      }).catch(error => {
        texts.delete(url);
        throw error;
      }));
    }
    return texts.get(url);
  }

  // An export embeds its manifest as `Promise.resolve({...})`. Scan for the
  // matching brace instead of assuming what follows it.
  function extractManifest(html) {
    const marker = "Promise.resolve(";
    const at = html.indexOf(marker + "{");
    if (at < 0) throw new Error("The export contains no manifest");
    const start = at + marker.length;
    let depth = 0;
    let quoted = false;
    let escaped = false;
    for (let index = start; index < html.length; index += 1) {
      const character = html.charCodeAt(index);
      if (quoted) {
        if (escaped) escaped = false;
        else if (character === 92) escaped = true;
        else if (character === 34) quoted = false;
      } else if (character === 34) {
        quoted = true;
      } else if (character === 123) {
        depth += 1;
      } else if (character === 125) {
        depth -= 1;
        if (depth === 0) return JSON.parse(html.slice(start, index + 1));
      }
    }
    throw new Error("The export's manifest is incomplete");
  }

  function toBase64Url(value) {
    let binary = "";
    for (const byte of new TextEncoder().encode(value)) binary += String.fromCharCode(byte);
    return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
  }

  // ---------- source ----------

  function callEnd(lines, start) {
    let depth = 0;
    for (let index = start; index < lines.length; index += 1) {
      let quoted = false;
      for (const character of lines[index]) {
        if (character === '"') quoted = !quoted;
        else if (quoted) continue;
        else if (character === "(") depth += 1;
        else if (character === ")" && --depth === 0) return index;
      }
    }
    return start;
  }

  // Finds the source lines behind each timeline block: `animate` and `create`
  // open a block, while `meanwhile`, `then`, `wait` and `cut` belong to the
  // current one. Gives up (null) when a call places its block explicitly.
  function mapBlocks(lines) {
    const blocks = [];
    let current = null;
    for (let index = 0; index < lines.length; index += 1) {
      const call = /^\s*#(animate|create|meanwhile|then|wait|cut)\(/.exec(lines[index]);
      if (!call) continue;
      const end = callEnd(lines, index);
      const source = lines.slice(index, end + 1).join("\n");
      if (/\bblock:/.test(source)) return null;
      const range = [];
      for (let line = index; line <= end; line += 1) range.push(line);
      if (call[1] === "animate" || call[1] === "create") {
        const state = /\(\s*([a-zA-Z][\w-]*):/.exec(source);
        current = { kind: call[1], state: state ? state[1] : "", lines: range };
        blocks.push(current);
      } else if (current) {
        current.lines.push(...range);
      }
      index = end;
    }
    return blocks;
  }

  function showSource(source) {
    const shown = source.trim().replace(libraryImport, '#import "@preview/glissade:0.1.0": *');
    const lines = shown.split("\n");
    const marked = highlight ? highlight.typst(shown).split("\n") : lines.map(line => line.replaceAll("&", "&amp;").replaceAll("<", "&lt;"));
    const elements = marked.map(line => {
      const element = document.createElement("span");
      element.className = "ln";
      element.innerHTML = line + "\n";
      return element;
    });
    code.replaceChildren(...elements);
    return { lines, elements };
  }

  // Start at the slide body, or a little above the first animation when the
  // slide opens with a long preamble.
  function scrollSource(lines, elements, blocks) {
    const pre = code.parentElement;
    const slide = Math.max(0, lines.findIndex(line => line.startsWith("#slide(")));
    const first = blocks && blocks.length > 0 ? blocks[0].lines[0] : slide;
    const top = elements[Math.max(slide, first - 5)];
    pre.scrollLeft = 0;
    if (top) pre.scrollTop += top.getBoundingClientRect().top - pre.getBoundingClientRect().top - 8;
  }

  // ---------- timeline ----------

  function lastFrame() { return Math.max(1, scene.frameCount - 1); }
  function position(value) { return (value / lastFrame()) * 100; }

  function buildTimeline(blocks, lineElements) {
    const seconds = lastFrame() / scene.fps;
    const step = seconds <= 2.5 ? 0.5 : seconds <= 12 ? 1 : seconds <= 30 ? 5 : 10;
    const ticks = [];
    for (let time = 0; time <= seconds + 1e-6; time += step) {
      const left = position(time * scene.fps);
      if (left > 97) break;
      const tick = document.createElement("span");
      tick.className = "ins-tick";
      tick.style.left = left + "%";
      tick.textContent = `${Number(time.toFixed(1))}s`;
      ticks.push(tick);
    }
    ruler.replaceChildren(...ticks);

    links = scene.blocks.map((block, index) => {
      const element = document.createElement("span");
      element.className = "ins-block";
      element.style.left = position(block.start_frame) + "%";
      element.style.width = `calc(${position(block.end_frame) - position(block.start_frame)}% - 2px)`;
      const info = blocks ? blocks[index] : null;
      if (info) {
        const state = document.createElement("b");
        state.textContent = info.state;
        element.append(info.kind + " ", state);
      } else {
        element.textContent = String(index + 1);
      }
      const lines = info ? info.lines.map(line => lineElements[line]).filter(Boolean) : [];
      for (const line of lines) line.dataset.block = String(index);
      element.addEventListener("pointerenter", () => setHot(index, true));
      element.addEventListener("pointerleave", () => setHot(index, false));
      return { element, lines };
    });
    blocksLayer.replaceChildren(...links.map(link => link.element));

    cutsLayer.replaceChildren(...scene.cuts.map(cut => {
      const element = document.createElement("span");
      element.className = "ins-cut" + (position(cut.frame) < 20 ? " at-start" : "");
      element.style.left = position(cut.frame) + "%";
      const label = document.createElement("span");
      label.textContent = cut.loop ? "cut · loops" : "cut";
      element.append(label);
      return element;
    }));

    track.setAttribute("aria-valuemax", String(scene.frameCount - 1));
  }

  function setHot(index, hot) {
    const link = links[index];
    if (!link) return;
    link.element.classList.toggle("is-hot", hot);
    for (const line of link.lines) line.classList.toggle("is-hot", hot);
  }

  function setActive(index) {
    if (index === activeBlock) return;
    for (const [at, link] of links.entries()) {
      const active = at === index;
      link.element.classList.toggle("is-active", active);
      for (const line of link.lines) line.classList.toggle("is-active", active);
    }
    activeBlock = index;
  }

  function update() {
    const seconds = frame / scene.fps;
    playhead.style.left = position(frame) + "%";
    timeLabel.textContent = seconds.toFixed(2) + " s";
    frameLabel.textContent = `frame ${frame + 1} / ${scene.frameCount}`;
    track.setAttribute("aria-valuenow", String(frame));
    track.setAttribute("aria-valuetext", `${seconds.toFixed(1)} of ${(lastFrame() / scene.fps).toFixed(1)} seconds`);
    const blocks = scene.blocks;
    setActive(blocks.findIndex((block, index) => frame >= block.start_frame
      && (frame < block.end_frame || index === blocks.length - 1)));
  }

  // ---------- stage ----------

  function fit(stack = canvas.querySelector(".glissade-stage-stack")) {
    if (!stack || room.width <= 0 || room.height <= 0) return;
    const width = Number(stack.dataset.glissadeWidth);
    const height = Number(stack.dataset.glissadeHeight);
    const scale = Math.max(0.05, Math.min(room.width / width, room.height / height));
    stack.style.width = width * scale + "px";
    stack.style.height = height * scale + "px";
  }

  function draw() {
    return renderer.render(scene, frame);
  }

  function showFallback(error) {
    if (error) console.warn("Glissade: showing the export in a frame instead.", error);
    stop();
    scene = null;
    links = [];
    panel.classList.add("is-fallback", "is-ready");
    const frameElement = document.createElement("iframe");
    frameElement.src = `examples/${example}.html`;
    frameElement.title = "Exported Glissade example";
    canvas.replaceChildren(frameElement);
  }

  // ---------- playback ----------

  function setPlaying(value) {
    playing = value;
    playButton.classList.toggle("is-playing", value);
    playButton.setAttribute("aria-label", value ? "Pause" : "Play");
  }

  function stop() {
    playback += 1;
    setPlaying(false);
  }

  function start() {
    if (!scene || playing) return;
    if (frame >= scene.frameCount - 1) frame = 0;
    const run = ++playback;
    const current = scene;
    const from = frame;
    let startedAt = 0;
    let drawn = false;
    setPlaying(true);
    const tick = async now => {
      if (run !== playback) return;
      if (!startedAt) startedAt = now;
      const steps = Math.floor((now - startedAt) * current.fps / 1000);
      const target = runtime.advancePlaybackFrame(current, from, steps);
      if (target.frame !== frame || !drawn) {
        frame = target.frame;
        drawn = true;
        update();
        try {
          await draw();
        } catch (error) {
          showFallback(error);
          return;
        }
        if (run !== playback) return;
      }
      if (target.cut || target.ended) {
        wantsPlay = false;
        stop();
        return;
      }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  // Playback runs only while it is wanted and can be seen.
  function sync() {
    const should = wantsPlay && onScreen && !document.hidden && !scrubbing && Boolean(scene);
    if (should && !playing) start();
    else if (!should && playing) stop();
  }

  function seek(target) {
    if (!scene) return;
    frame = Math.max(0, Math.min(Math.round(target), scene.frameCount - 1));
    update();
    draw().catch(showFallback);
  }

  function seekPointer(event) {
    const bounds = track.getBoundingClientRect();
    seek(((event.clientX - bounds.left) / bounds.width) * (scene.frameCount - 1));
  }

  // ---------- examples ----------

  async function select(tab) {
    const name = tab.dataset.example;
    const token = ++selection;
    example = name;
    for (const item of tabs) {
      const selected = item === tab;
      item.setAttribute("aria-selected", String(selected));
      item.tabIndex = selected ? 0 : -1;
    }
    file.textContent = `${name}.typ`;
    openLink.href = `examples/${name}.html`;
    editLink.href = "playground.html";
    stop();

    let source = null;
    try {
      source = await text(`examples/${name}.typ`);
    } catch {
      // Without the source, the excerpt already in the page stays.
    }
    if (token !== selection) return;
    let shown = null;
    if (source !== null) {
      shown = showSource(source);
      editLink.href = "playground.html#code=t:"
        + toBase64Url(source.trim().replace(libraryImport, '#import "glissade.typ": *'));
    }

    try {
      if (!runtime) throw new Error("The Glissade runtime did not load");
      const manifest = runtime.validateManifest(extractManifest(await text(`examples/${name}.html`)));
      if (token !== selection) return;
      const next = manifest.scenes[0];
      if (!next || next.frameCount < 1) throw new Error("The export has no slide");

      scene = next;
      const mapped = shown ? mapBlocks(shown.lines) : null;
      const blocks = mapped && mapped.length === scene.blocks.length ? mapped : null;
      activeBlock = -1;
      buildTimeline(blocks, shown ? shown.elements : []);
      if (shown) scrollSource(shown.lines, shown.elements, blocks);

      if (renderer) renderer.clear();
      canvas.replaceChildren();
      renderer = runtime.createStageRenderer(canvas, { onSize: (_, stack) => fit(stack) });
      panel.classList.remove("is-fallback");
      wantsPlay = !reducedMotion.matches;
      // Without motion, rest on the finished slide instead of an empty one.
      frame = wantsPlay ? 0 : scene.frameCount - 1;
      update();
      await draw();
      if (token !== selection) return;
      panel.classList.add("is-ready");
      sync();
    } catch (error) {
      if (token === selection) showFallback(error);
    }
  }

  // ---------- events ----------

  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => select(tab));
    tab.addEventListener("keydown", event => {
      const delta = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
      if (!delta) return;
      const next = tabs[(index + delta + tabs.length) % tabs.length];
      next.focus();
      select(next);
    });
  });

  playButton.addEventListener("click", () => {
    wantsPlay = !playing;
    sync();
  });

  track.addEventListener("pointerdown", event => {
    if (!scene || (event.pointerType === "mouse" && event.button !== 0)) return;
    scrubbing = true;
    wantsPlay = false;
    track.setPointerCapture(event.pointerId);
    sync();
    seekPointer(event);
  });
  track.addEventListener("pointermove", event => {
    if (scrubbing) seekPointer(event);
  });
  for (const type of ["pointerup", "pointercancel"]) {
    track.addEventListener(type, () => { scrubbing = false; });
  }
  track.addEventListener("keydown", event => {
    if (!scene) return;
    const stride = event.shiftKey ? 10 : 1;
    const targets = {
      ArrowLeft: frame - stride,
      ArrowDown: frame - stride,
      ArrowRight: frame + stride,
      ArrowUp: frame + stride,
      Home: 0,
      End: scene.frameCount - 1,
    };
    if (event.key === " " || event.key === "Enter") {
      event.preventDefault();
      wantsPlay = !playing;
      sync();
    } else if (event.key in targets) {
      event.preventDefault();
      wantsPlay = false;
      sync();
      seek(targets[event.key]);
    }
  });

  const blockOfLine = event => {
    const line = event.target instanceof Element ? event.target.closest(".ln[data-block]") : null;
    return line ? Number(line.dataset.block) : -1;
  };
  code.addEventListener("pointerover", event => setHot(blockOfLine(event), true));
  code.addEventListener("pointerout", event => setHot(blockOfLine(event), false));
  code.addEventListener("click", event => {
    const index = blockOfLine(event);
    if (index < 0 || !scene || String(getSelection()) !== "") return;
    stop();
    seek(scene.blocks[index].start_frame);
    wantsPlay = true;
    sync();
  });

  new ResizeObserver(entries => {
    const box = entries[0].contentRect;
    room = { width: box.width, height: box.height };
    fit();
  }).observe(canvas);
  new IntersectionObserver(entries => {
    onScreen = entries[entries.length - 1].isIntersecting;
    sync();
  }).observe(panel);
  document.addEventListener("visibilitychange", sync);

  select(tabs.find(tab => tab.getAttribute("aria-selected") === "true") || tabs[0]);
})();
