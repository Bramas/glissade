(() => {
  const runtime = globalThis.__glissadeMorphRuntime || (globalThis.__glissadeMorphRuntime = {});
  const {
    SVG_NS,
    parseSvgMarkup,
    decodeDataUri,
    decompressGzip,
    intrinsicSize,
    inverseParentTransform,
    safeBBox,
    safeGlobalBBox,
    interpolateRect,
    rectTransform,
    rectTranslationForElement,
    morphSelector,
    smoothRate,
    sceneKeyframes,
    advancePlaybackFrame,
    segmentForFrame,
    planGeometryMorph,
    makeGeometryOverlay,
    planDrawIn,
    makeDrawOverlay,
  } = runtime;

  function elementSelector(id) {
    return "#" + CSS.escape(id);
  }

  function frameSourceKey(source) {
    return typeof source === "string" ? source : JSON.stringify(source);
  }

  function parseSvgFragment(markup) {
    const document = new DOMParser().parseFromString(
      '<svg xmlns="' + SVG_NS + '" xmlns:xlink="http://www.w3.org/1999/xlink">' + markup + "</svg>",
      "image/svg+xml",
    );
    const parseError = document.querySelector("parsererror");
    if (parseError) throw new Error("Failed to parse SVG delta fragment");
    return document.documentElement.firstElementChild;
  }

  function replaceSvgNodeAtPath(svg, path, markup) {
    let parent = svg;
    for (let index = 0; index < path.length - 1; index += 1) {
      parent = parent.children[path[index]];
      if (!parent) throw new Error("Invalid SVG delta path");
    }
    const childIndex = path[path.length - 1];
    const current = parent.children[childIndex];
    const replacement = parseSvgFragment(markup);
    if (!current || !replacement) throw new Error("Invalid SVG delta replacement");
    parent.replaceChild(replacement, current);
  }

  function applySvgDelta(baseText, source) {
    const svg = parseSvgMarkup(baseText);
    for (const patch of source.patches || []) {
      replaceSvgNodeAtPath(svg, patch.path || [], patch.svg || "");
    }
    return new XMLSerializer().serializeToString(svg);
  }

  function partSelector(key) {
    return '[data-glissade-part="true"][data-glissade-part-key="' + CSS.escape(key) + '"]';
  }

  function analyzeSvg(svg) {
    const roots = new Map();
    svg.querySelectorAll('[data-glissade-morph="true"]').forEach(root => {
      const rootId = root.getAttribute("data-glissade-morph-id") || root.id;
      const parts = new Map();
      root.querySelectorAll('[data-glissade-part="true"]').forEach(part => {
        const key = part.getAttribute("data-glissade-part-key");
        if (!key) return;
        parts.set(key, {
          key,
          elementId: part.id,
          bbox: safeGlobalBBox(part),
        });
      });
      roots.set(rootId, {
        id: rootId,
        elementId: root.id,
        bbox: safeBBox(root),
        effect: root.getAttribute("data-glissade-morph-effect") || null,
        parts,
      });
    });
    return { roots };
  }

  function collectMorphMatches(startAnalysis, endAnalysis) {
    const matches = [];
    const leaving = [];
    for (const [rootId, startRoot] of startAnalysis.roots.entries()) {
      const endRoot = endAnalysis.roots.get(rootId);
      if (!endRoot) {
        leaving.push({ rootId, startRoot, endRoot: null });
        continue;
      }
      const sharedPartKeys = [];
      for (const key of startRoot.parts.keys()) {
        if (endRoot.parts.has(key)) sharedPartKeys.push(key);
      }
      matches.push({
        rootId,
        startRoot,
        endRoot,
        sharedPartKeys,
      });
    }
    const entering = [];
    for (const [rootId, endRoot] of endAnalysis.roots.entries()) {
      if (startAnalysis.roots.has(rootId)) continue;
      entering.push({ rootId, startRoot: null, endRoot });
    }
    return { matches, entering, leaving };
  }

  function isDrawEffect(effect) {
    return effect === "draw-border-then-fill" || effect === "create" || effect === "write";
  }

  function keepSelectedBranch(element, selectedIds) {
    if (!(element instanceof Element)) return false;
    if (element.localName === "defs") return true;
    if (selectedIds.has(element.id)) return true;
    const children = [...element.children];
    let keepAny = false;
    for (const child of children) {
      if (!keepSelectedBranch(child, selectedIds)) {
        child.remove();
      } else {
        keepAny = true;
      }
    }
    return keepAny;
  }

  function keepMorphBranch(element, allowedRootIds) {
    if (!(element instanceof Element)) return false;
    if (element.localName === "defs") return true;
    if (element.matches('[data-glissade-morph="true"]')) {
      return allowedRootIds.has(element.getAttribute("data-glissade-morph-id") || element.id);
    }
    const children = [...element.children];
    let keepAny = false;
    for (const child of children) {
      if (!keepMorphBranch(child, allowedRootIds)) {
        child.remove();
      } else {
        keepAny = true;
      }
    }
    return keepAny;
  }

  function prepareOverlaySvg(svg, allowedRootIds) {
    [...svg.children].forEach(child => {
      if (!(child instanceof Element)) return;
      if (child.localName === "defs") return;
      if (!keepMorphBranch(child, allowedRootIds)) {
        child.remove();
      }
    });
    return svg;
  }

  function prepareElementOverlaySvg(svg, selectedIds) {
    [...svg.children].forEach(child => {
      if (!(child instanceof Element)) return;
      if (child.localName === "defs") return;
      if (!keepSelectedBranch(child, selectedIds)) {
        child.remove();
      }
    });
    return svg;
  }

  function wrapMorphRoot(root, transform, opacity) {
    const parent = root.parentNode;
    if (!parent) return;
    const wrapper = document.createElementNS(SVG_NS, "g");
    wrapper.setAttribute("opacity", String(opacity));
    if (transform) wrapper.setAttribute("transform", transform);
    parent.insertBefore(wrapper, root);
    wrapper.appendChild(root);
  }

  function hideMorphRoots(svg, matches) {
    for (const match of matches) {
      const root = svg.querySelector(morphSelector(match.rootId));
      if (root) root.setAttribute("visibility", "hidden");
    }
  }

  function hideElementsById(svg, elementIds) {
    for (const elementId of elementIds) {
      const element = svg.querySelector(elementSelector(elementId));
      if (element) element.setAttribute("visibility", "hidden");
    }
  }

  function insertRootOverlayGroups(baseSvg, overlay, generatedAttribute) {
    let inserted = 0;
    for (const group of [...overlay.querySelectorAll("[" + generatedAttribute + "]")]) {
      const rootId = group.getAttribute(generatedAttribute);
      if (!rootId || rootId.includes("::")) continue;
      const target = baseSvg.querySelector(morphSelector(rootId));
      if (!target?.parentNode) continue;
      const transform = group.getAttribute("data-glissade-insertion-transform");
      group.removeAttribute("data-glissade-insertion-transform");
      if (transform) group.setAttribute("transform", transform);
      target.parentNode.insertBefore(group, target);
      inserted += 1;
    }
    return inserted;
  }

  function ensureRootComposite(baseSvg, plan, rootId) {
    const selector = '[data-glissade-composite-root="' + CSS.escape(rootId) + '"]';
    const existing = baseSvg.querySelector(selector);
    if (existing) return existing;
    const target = baseSvg.querySelector(morphSelector(rootId));
    if (!target?.parentNode) return null;
    const composite = document.createElementNS(SVG_NS, "g");
    composite.setAttribute("data-glissade-composite-root", rootId);
    const transform = plan.compositeTransforms.get(rootId);
    if (transform) composite.setAttribute("transform", transform);
    target.parentNode.insertBefore(composite, target);
    return composite;
  }

  function appendGeneratedLayer(composite, overlay) {
    for (const group of [...overlay.children]) {
      group.removeAttribute?.("data-glissade-insertion-transform");
      group.removeAttribute?.("transform");
      composite.appendChild(group);
    }
  }

  let compositeLayerIndex = 0;
  function namespaceSvgIds(svg) {
    const prefix = "glissade-composite-" + compositeLayerIndex++ + "-";
    const replacements = new Map();
    for (const element of svg.querySelectorAll("[id]")) {
      const oldId = element.id;
      const newId = prefix + oldId;
      replacements.set(oldId, newId);
      element.id = newId;
    }
    for (const element of svg.querySelectorAll("*")) {
      for (const attribute of [...element.attributes]) {
        let value = attribute.value;
        for (const [oldId, newId] of replacements) {
          if (value === "#" + oldId) value = "#" + newId;
          value = value.replaceAll("url(#" + oldId + ")", "url(#" + newId + ")");
        }
        if (value !== attribute.value) element.setAttribute(attribute.name, value);
      }
    }
  }

  function appendSvgLayer(composite, svg, size) {
    namespaceSvgIds(svg);
    svg.removeAttribute("class");
    svg.setAttribute("x", "0");
    svg.setAttribute("y", "0");
    svg.setAttribute("width", String(size.width));
    svg.setAttribute("height", String(size.height));
    composite.appendChild(svg);
  }

  function splitFadeOpacities(progress) {
    const overlap = 0.08;
    const startEnd = 0.5 + overlap / 2;
    const endStart = 0.5 - overlap / 2;
    return {
      start: Math.max(0, Math.min(1, 1 - progress / startEnd)),
      end: Math.max(0, Math.min(1, (progress - endStart) / (1 - endStart))),
    };
  }

  function rootHasRenderableContent(root) {
    if (!root) return false;
    return root.querySelector("path, use") !== null;
  }

  function drawProgressForRoot(scene, rootId, frameIndex, fallback) {
    const animations = (scene.morphAnimations || [])
      .filter(item => item.id === rootId && isDrawEffect(item.effect))
      .sort((left, right) => left.start_frame - right.start_frame);
    if (animations.length === 0) return fallback;
    const active = animations.find(item => (
      frameIndex >= item.start_frame && frameIndex <= item.end_frame
    ));
    if (active) {
      const span = active.end_frame - active.start_frame;
      const linear = span > 0 ? (frameIndex - active.start_frame) / span : 1;
      return smoothRate(linear);
    }
    return frameIndex < animations[0].start_frame ? 0 : 1;
  }

  function rootPlanForMatch(match, startRootElement, endRootElement) {
    const matchedPartKeys = match.sharedPartKeys;
    if (matchedPartKeys.length === 0) {
      const effect = match.endRoot?.effect || match.startRoot?.effect;
      if (isDrawEffect(effect) && !rootHasRenderableContent(startRootElement) && rootHasRenderableContent(endRootElement)) {
        const drawPlan = planDrawIn(match.rootId, endRootElement);
        return {
          rootId: match.rootId,
          rootGeometryPlan: null,
          rootDrawPlan: drawPlan,
          rootFallback: drawPlan === null,
          matchedPartIds: [],
          partGeometryPlans: [],
          partFallbacks: [],
        };
      }
      const geometryPlan = planGeometryMorph(match.rootId, startRootElement, endRootElement);
      return {
        rootId: match.rootId,
        rootGeometryPlan: geometryPlan,
        rootDrawPlan: null,
        rootFallback: geometryPlan === null,
        matchedPartIds: [],
        partGeometryPlans: [],
        partFallbacks: [],
      };
    }

    const matchedPartIds = [];
    const partGeometryPlans = [];
    const partFallbacks = [];
    for (const key of matchedPartKeys) {
      const startPartInfo = match.startRoot.parts.get(key);
      const endPartInfo = match.endRoot.parts.get(key);
      if (!startPartInfo || !endPartInfo) continue;
      matchedPartIds.push(startPartInfo.elementId, endPartInfo.elementId);
      const startPartElement = startRootElement.querySelector(partSelector(key));
      const endPartElement = endRootElement.querySelector(partSelector(key));
      const planId = match.rootId + "::" + key;
      const geometryPlan = planGeometryMorph(planId, startPartElement, endPartElement);
      if (geometryPlan) {
        partGeometryPlans.push(geometryPlan);
      } else {
        partFallbacks.push({
          key,
          startId: startPartInfo.elementId,
          endId: endPartInfo.elementId,
          startBox: startPartInfo.bbox,
          endBox: endPartInfo.bbox,
        });
      }
    }

    return {
      rootId: match.rootId,
      rootGeometryPlan: null,
      rootDrawPlan: null,
      rootFallback: true,
      matchedPartIds,
      partGeometryPlans,
      partFallbacks,
    };
  }

  class SvgFrameStore {
    constructor() {
      this.textCache = new Map();
      this.analysisCache = new Map();
      this.planCache = new Map();
    }

    async loadText(source, frames = null) {
      if (!this.textCache.has(source)) {
        this.textCache.set(source, (async () => {
          if (source && typeof source === "object") {
            if (source.kind !== "svg-delta-v1") {
              throw new Error("Unsupported Glissade frame source: " + source.kind);
            }
            if (!frames || !Number.isInteger(source.base) || !frames[source.base]) {
              throw new Error("Invalid Glissade SVG delta base");
            }
            return applySvgDelta(await this.loadText(frames[source.base], frames), source);
          }
          const inline = await decodeDataUri(source);
          if (inline !== null) return inline;
          const response = await fetch(source);
          if (!response.ok) {
            throw new Error("Failed to load frame " + source + ": " + response.status);
          }
          if (source.split("?", 1)[0].endsWith(".svg.gz")) {
            return decompressGzip(new Uint8Array(await response.arrayBuffer()));
          }
          return response.text();
        })());
      }
      return this.textCache.get(source);
    }

    async instantiate(source, frames = null) {
      return parseSvgMarkup(await this.loadText(source, frames));
    }

    async analyzed(source, sandbox, frames = null) {
      if (!this.analysisCache.has(source)) {
        this.analysisCache.set(source, (async () => {
          const svg = await this.instantiate(source, frames);
          sandbox.replaceChildren(svg);
          const analysis = analyzeSvg(svg);
          const size = intrinsicSize(svg);
          sandbox.replaceChildren();
          return { analysis, size };
        })());
      }
      return this.analysisCache.get(source);
    }

    async segmentPlan(startSource, endSource, sandbox, frames = null) {
      const cacheKey = frameSourceKey(startSource) + "::" + frameSourceKey(endSource);
      if (!this.planCache.has(cacheKey)) {
        this.planCache.set(cacheKey, (async () => {
          const [startData, endData] = await Promise.all([
            this.analyzed(startSource, sandbox, frames),
            this.analyzed(endSource, sandbox, frames),
          ]);
          const morphEvents = collectMorphMatches(startData.analysis, endData.analysis);
          const matches = morphEvents.matches;
          const startSvg = await this.instantiate(startSource, frames);
          const endSvg = await this.instantiate(endSource, frames);
          sandbox.replaceChildren(startSvg, endSvg);
          const geometryPlans = [];
          const drawPlans = [];
          const fallbackMatches = [];
          const partPlans = [];
          const compositeTransforms = new Map();
          for (const match of matches) {
            const startRootElement = startSvg.querySelector(morphSelector(match.rootId));
            const endRootElement = endSvg.querySelector(morphSelector(match.rootId));
            compositeTransforms.set(
              match.rootId,
              inverseParentTransform(startRootElement || endRootElement),
            );
            const plan = rootPlanForMatch(
              match,
              startRootElement,
              endRootElement,
            );
            if (plan.rootGeometryPlan) {
              geometryPlans.push(plan.rootGeometryPlan);
            }
            if (plan.rootDrawPlan) {
              drawPlans.push(plan.rootDrawPlan);
            }
            if (plan.rootFallback) {
              fallbackMatches.push({
                ...match,
                matchedPartIds: plan.matchedPartIds,
              });
            }
            if (plan.partGeometryPlans.length > 0 || plan.partFallbacks.length > 0) {
              partPlans.push({
                rootId: match.rootId,
                geometryPlans: plan.partGeometryPlans,
                fallbacks: plan.partFallbacks,
              });
            }
          }
          const enteringFallbacks = [];
          for (const enter of morphEvents.entering) {
            const effect = enter.endRoot?.effect;
            if (isDrawEffect(effect)) {
              const drawPlan = planDrawIn(
                enter.rootId,
                endSvg.querySelector(morphSelector(enter.rootId)),
              );
              if (drawPlan) {
                drawPlans.push(drawPlan);
                continue;
              }
            }
            enteringFallbacks.push(enter);
          }
          const leavingFallbacks = morphEvents.leaving;
          sandbox.replaceChildren();
          return {
            size: startData.size,
            geometryPlans,
            drawPlans,
            fallbackMatches,
            enteringFallbacks,
            leavingFallbacks,
            partPlans,
            compositeTransforms,
            allMatches: matches,
          };
        })());
      }
      return this.planCache.get(cacheKey);
    }
  }

  class StageRenderer {
    constructor(stage, options = {}) {
      this.stage = stage;
      this.store = options.store || new SvgFrameStore();
      this.sandbox = document.createElement("div");
      this.sandbox.className = "glissade-measure-sandbox";
      this.stage.appendChild(this.sandbox);
      this.renderToken = 0;
      this.currentSize = { width: 1024, height: 768 };
      this.onSize = options.onSize || null;
    }

    async render(scene, frameIndex) {
      const token = ++this.renderToken;
      const source = scene.frames[frameIndex];
      const baseSvg = await this.store.instantiate(source, scene.frames);
      if (token !== this.renderToken) return this.currentSize;

      const size = intrinsicSize(baseSvg);
      this.currentSize = size;
      const stack = document.createElement("div");
      stack.className = "glissade-stage-stack";
      stack.dataset.glissadeWidth = String(size.width);
      stack.dataset.glissadeHeight = String(size.height);
      stack.style.width = size.width + "px";
      stack.style.height = size.height + "px";

      baseSvg.classList.add("glissade-stage-base");
      stack.appendChild(baseSvg);

      const segment = segmentForFrame(scene, frameIndex);
      if (segment) {
        const plan = await this.store.segmentPlan(
          scene.frames[segment.startFrame],
          scene.frames[segment.endFrame],
          this.sandbox,
          scene.frames,
        );
        if (token !== this.renderToken) return this.currentSize;
        if (plan.allMatches.length > 0) {
          hideMorphRoots(baseSvg, plan.allMatches);
          if (plan.geometryPlans.length > 0) {
            const geometryOverlay = makeGeometryOverlay(size, plan.geometryPlans, segment.progress);
            if (geometryOverlay) {
              const inserted = insertRootOverlayGroups(
                baseSvg,
                geometryOverlay,
                "data-glissade-generated-morph",
              );
              if (inserted < plan.geometryPlans.length) stack.appendChild(geometryOverlay);
            }
          }
          if (plan.drawPlans.length > 0) {
            const drawOverlay = makeDrawOverlay(
              size,
              plan.drawPlans,
              segment.progress,
              (drawPlan, fallback) => drawProgressForRoot(
                scene,
                drawPlan.rootId,
                frameIndex,
                fallback,
              ),
            );
            if (drawOverlay) {
              const inserted = insertRootOverlayGroups(
                baseSvg,
                drawOverlay,
                "data-glissade-generated-draw",
              );
              if (inserted < plan.drawPlans.length) stack.appendChild(drawOverlay);
            }
          }
          for (const partPlan of plan.partPlans) {
            const composite = ensureRootComposite(baseSvg, plan, partPlan.rootId);
            if (partPlan.geometryPlans.length > 0) {
              const geometryOverlay = makeGeometryOverlay(size, partPlan.geometryPlans, segment.progress);
              if (geometryOverlay) {
                if (composite) appendGeneratedLayer(composite, geometryOverlay);
                else stack.appendChild(geometryOverlay);
              }
            }
            if (partPlan.fallbacks.length > 0) {
              const startIds = new Set(partPlan.fallbacks.map(item => item.startId));
              const startOverlay = prepareElementOverlaySvg(
                await this.store.instantiate(scene.frames[segment.startFrame], scene.frames),
                startIds,
              );
              startOverlay.classList.add("glissade-stage-overlay", "glissade-stage-overlay-start", "glissade-stage-overlay-parts");
              for (const fallback of partPlan.fallbacks) {
                const targetBox = interpolateRect(fallback.startBox, fallback.endBox, segment.progress);
                const startPart = startOverlay.querySelector(elementSelector(fallback.startId));
                if (startPart) {
                  wrapMorphRoot(
                    startPart,
                    rectTranslationForElement(startPart, fallback.startBox, targetBox),
                    1,
                  );
                }
              }
              if (composite) appendSvgLayer(composite, startOverlay, size);
              else stack.append(startOverlay);
            }
          }
          if (plan.fallbackMatches.length > 0) {
            for (const match of plan.fallbackMatches) {
              const allowedRootIds = new Set([match.rootId]);
              const startOverlay = prepareOverlaySvg(
                await this.store.instantiate(scene.frames[segment.startFrame], scene.frames),
                allowedRootIds,
              );
              const endOverlay = prepareOverlaySvg(
                await this.store.instantiate(scene.frames[segment.endFrame], scene.frames),
                allowedRootIds,
              );
              startOverlay.classList.add("glissade-stage-overlay", "glissade-stage-overlay-start");
              endOverlay.classList.add("glissade-stage-overlay", "glissade-stage-overlay-end");
              hideElementsById(startOverlay, match.matchedPartIds || []);
              hideElementsById(endOverlay, match.matchedPartIds || []);
              const startRoot = startOverlay.querySelector(morphSelector(match.rootId));
              const endRoot = endOverlay.querySelector(morphSelector(match.rootId));
              const useRootTransform = !(match.matchedPartIds && match.matchedPartIds.length > 0);
              const targetBox = useRootTransform
                ? interpolateRect(match.startRoot.bbox, match.endRoot.bbox, segment.progress)
                : null;
              const fallbackOpacity = useRootTransform
                ? { start: 1 - segment.progress, end: segment.progress }
                : splitFadeOpacities(segment.progress);
              if (startRoot) {
                wrapMorphRoot(
                  startRoot,
                  useRootTransform ? rectTransform(match.startRoot.bbox, targetBox) : null,
                  fallbackOpacity.start,
                );
              }
              if (endRoot) {
                wrapMorphRoot(
                  endRoot,
                  useRootTransform ? rectTransform(match.endRoot.bbox, targetBox) : null,
                  fallbackOpacity.end,
                );
              }
              const hasMatchedParts = match.matchedPartIds && match.matchedPartIds.length > 0;
              const composite = hasMatchedParts
                ? ensureRootComposite(baseSvg, plan, match.rootId)
                : null;
              if (composite) {
                appendSvgLayer(composite, startOverlay, size);
                appendSvgLayer(composite, endOverlay, size);
              } else {
                stack.append(startOverlay, endOverlay);
              }
            }
          }
          if (plan.enteringFallbacks.length > 0) {
            const allowedRootIds = new Set(plan.enteringFallbacks.map(match => match.rootId));
            const endOverlay = prepareOverlaySvg(await this.store.instantiate(scene.frames[segment.endFrame], scene.frames), allowedRootIds);
            endOverlay.classList.add("glissade-stage-overlay", "glissade-stage-overlay-end");
            for (const match of plan.enteringFallbacks) {
              const endRoot = endOverlay.querySelector(morphSelector(match.rootId));
              if (endRoot) {
                wrapMorphRoot(endRoot, null, segment.progress);
              }
            }
            stack.append(endOverlay);
          }
          if (plan.leavingFallbacks.length > 0) {
            const allowedRootIds = new Set(plan.leavingFallbacks.map(match => match.rootId));
            const startOverlay = prepareOverlaySvg(await this.store.instantiate(scene.frames[segment.startFrame], scene.frames), allowedRootIds);
            startOverlay.classList.add("glissade-stage-overlay", "glissade-stage-overlay-start");
            for (const match of plan.leavingFallbacks) {
              const startRoot = startOverlay.querySelector(morphSelector(match.rootId));
              if (startRoot) {
                wrapMorphRoot(startRoot, null, 1 - segment.progress);
              }
            }
            stack.append(startOverlay);
          }
        }
      }

      [...this.stage.children].forEach(node => {
        if (node === this.sandbox) return;
        node.remove();
      });
      this.stage.appendChild(stack);
      if (this.onSize) this.onSize(size, stack);
      return size;
    }

    getSize() {
      return this.currentSize;
    }

    frameText(scene, frameIndex) {
      return this.store.loadText(scene.frames[frameIndex], scene.frames);
    }

    prefetch(scene, frameIndex) {
      const source = scene.frames[frameIndex];
      if (source) this.store.loadText(source, scene.frames).catch(() => {});
      const segment = segmentForFrame(scene, frameIndex);
      if (!segment) return;
      this.store.loadText(scene.frames[segment.startFrame], scene.frames).catch(() => {});
      this.store.loadText(scene.frames[segment.endFrame], scene.frames).catch(() => {});
    }
  }

  globalThis.GlissadeMorphRuntime = {
    createStageRenderer(stage, options) {
      return new StageRenderer(stage, options);
    },
    sceneKeyframes,
    advancePlaybackFrame,
    segmentForFrame,
  };
})();
