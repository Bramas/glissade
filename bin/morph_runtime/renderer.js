(() => {
  const runtime = globalThis.__kinoMorphRuntime || (globalThis.__kinoMorphRuntime = {});
  const {
    SVG_NS,
    parseSvgMarkup,
    decodeDataUri,
    intrinsicSize,
    safeBBox,
    interpolateRect,
    rectTransform,
    morphSelector,
    sceneKeyframes,
    segmentForFrame,
    planGeometryMorph,
    makeGeometryOverlay,
    planDrawIn,
    makeDrawOverlay,
  } = runtime;

  function elementSelector(id) {
    return "#" + CSS.escape(id);
  }

  function partSelector(key) {
    return '[data-kino-part="true"][data-kino-part-key="' + CSS.escape(key) + '"]';
  }

  function analyzeSvg(svg) {
    const roots = new Map();
    svg.querySelectorAll('[data-kino-morph="true"]').forEach(root => {
      const rootId = root.getAttribute("data-kino-morph-id") || root.id;
      const parts = new Map();
      root.querySelectorAll('[data-kino-part="true"]').forEach(part => {
        const key = part.getAttribute("data-kino-part-key");
        if (!key) return;
        parts.set(key, {
          key,
          elementId: part.id,
          bbox: safeBBox(part),
        });
      });
      roots.set(rootId, {
        id: rootId,
        elementId: root.id,
        bbox: safeBBox(root),
        effect: root.getAttribute("data-kino-morph-effect") || null,
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
    if (element.matches('[data-kino-morph="true"]')) {
      return allowedRootIds.has(element.getAttribute("data-kino-morph-id") || element.id);
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

    async loadText(source) {
      if (!this.textCache.has(source)) {
        this.textCache.set(source, (async () => {
          const inline = decodeDataUri(source);
          if (inline !== null) return inline;
          const response = await fetch(source);
          if (!response.ok) {
            throw new Error("Failed to load frame " + source + ": " + response.status);
          }
          return response.text();
        })());
      }
      return this.textCache.get(source);
    }

    async instantiate(source) {
      return parseSvgMarkup(await this.loadText(source));
    }

    async analyzed(source, sandbox) {
      if (!this.analysisCache.has(source)) {
        this.analysisCache.set(source, (async () => {
          const svg = await this.instantiate(source);
          sandbox.replaceChildren(svg);
          const analysis = analyzeSvg(svg);
          const size = intrinsicSize(svg);
          sandbox.replaceChildren();
          return { analysis, size };
        })());
      }
      return this.analysisCache.get(source);
    }

    async segmentPlan(startSource, endSource, sandbox) {
      const cacheKey = startSource + "::" + endSource;
      if (!this.planCache.has(cacheKey)) {
        this.planCache.set(cacheKey, (async () => {
          const [startData, endData] = await Promise.all([
            this.analyzed(startSource, sandbox),
            this.analyzed(endSource, sandbox),
          ]);
          const morphEvents = collectMorphMatches(startData.analysis, endData.analysis);
          const matches = morphEvents.matches;
          const startSvg = await this.instantiate(startSource);
          const endSvg = await this.instantiate(endSource);
          sandbox.replaceChildren(startSvg, endSvg);
          const geometryPlans = [];
          const drawPlans = [];
          const fallbackMatches = [];
          const partPlans = [];
          for (const match of matches) {
            const plan = rootPlanForMatch(
              match,
              startSvg.querySelector(morphSelector(match.rootId)),
              endSvg.querySelector(morphSelector(match.rootId)),
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
      this.sandbox.className = "kino-measure-sandbox";
      this.stage.appendChild(this.sandbox);
      this.renderToken = 0;
      this.currentSize = { width: 1024, height: 768 };
      this.onSize = options.onSize || null;
    }

    async render(scene, frameIndex) {
      const token = ++this.renderToken;
      const source = scene.frames[frameIndex];
      const baseSvg = await this.store.instantiate(source);
      if (token !== this.renderToken) return this.currentSize;

      const size = intrinsicSize(baseSvg);
      this.currentSize = size;
      const stack = document.createElement("div");
      stack.className = "kino-stage-stack";
      stack.dataset.kinoWidth = String(size.width);
      stack.dataset.kinoHeight = String(size.height);
      stack.style.width = size.width + "px";
      stack.style.height = size.height + "px";

      baseSvg.classList.add("kino-stage-base");
      stack.appendChild(baseSvg);

      const segment = segmentForFrame(scene, frameIndex);
      if (segment) {
        const plan = await this.store.segmentPlan(
          scene.frames[segment.startFrame],
          scene.frames[segment.endFrame],
          this.sandbox,
        );
        if (token !== this.renderToken) return this.currentSize;
        if (plan.allMatches.length > 0) {
          hideMorphRoots(baseSvg, plan.allMatches);
          for (const partPlan of plan.partPlans) {
            const rootMatch = plan.allMatches.find(match => match.rootId === partPlan.rootId);
            if (!rootMatch) continue;
            const hiddenIds = [];
            for (const fallback of partPlan.fallbacks) {
              hiddenIds.push(fallback.startId);
            }
            for (const geometryPlan of partPlan.geometryPlans) {
              const partKey = geometryPlan.rootId.split("::").at(-1);
              const partInfo = rootMatch.startRoot.parts.get(partKey);
              if (partInfo) hiddenIds.push(partInfo.elementId);
            }
            hideElementsById(baseSvg, hiddenIds);
          }
          if (plan.geometryPlans.length > 0) {
            const geometryOverlay = makeGeometryOverlay(size, plan.geometryPlans, segment.progress);
            if (geometryOverlay) {
              stack.appendChild(geometryOverlay);
            }
          }
          if (plan.drawPlans.length > 0) {
            const drawOverlay = makeDrawOverlay(size, plan.drawPlans, segment.progress);
            if (drawOverlay) {
              stack.appendChild(drawOverlay);
            }
          }
          for (const partPlan of plan.partPlans) {
            if (partPlan.geometryPlans.length > 0) {
              const geometryOverlay = makeGeometryOverlay(size, partPlan.geometryPlans, segment.progress);
              if (geometryOverlay) {
                stack.appendChild(geometryOverlay);
              }
            }
            if (partPlan.fallbacks.length > 0) {
              const startIds = new Set(partPlan.fallbacks.map(item => item.startId));
              const startOverlay = prepareElementOverlaySvg(
                await this.store.instantiate(scene.frames[segment.startFrame]),
                startIds,
              );
              startOverlay.classList.add("kino-stage-overlay", "kino-stage-overlay-start", "kino-stage-overlay-parts");
              for (const fallback of partPlan.fallbacks) {
                const targetBox = interpolateRect(fallback.startBox, fallback.endBox, segment.progress);
                const startPart = startOverlay.querySelector(elementSelector(fallback.startId));
                if (startPart) {
                  wrapMorphRoot(startPart, rectTransform(fallback.startBox, targetBox), 1);
                }
              }
              stack.append(startOverlay);
            }
          }
          if (plan.fallbackMatches.length > 0) {
            const allowedRootIds = new Set(plan.fallbackMatches.map(match => match.rootId));
            const startOverlay = prepareOverlaySvg(await this.store.instantiate(scene.frames[segment.startFrame]), allowedRootIds);
            const endOverlay = prepareOverlaySvg(await this.store.instantiate(scene.frames[segment.endFrame]), allowedRootIds);
            startOverlay.classList.add("kino-stage-overlay", "kino-stage-overlay-start");
            endOverlay.classList.add("kino-stage-overlay", "kino-stage-overlay-end");

            for (const match of plan.fallbackMatches) {
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
            }

            stack.append(startOverlay, endOverlay);
          }
          if (plan.enteringFallbacks.length > 0) {
            const allowedRootIds = new Set(plan.enteringFallbacks.map(match => match.rootId));
            const endOverlay = prepareOverlaySvg(await this.store.instantiate(scene.frames[segment.endFrame]), allowedRootIds);
            endOverlay.classList.add("kino-stage-overlay", "kino-stage-overlay-end");
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
            const startOverlay = prepareOverlaySvg(await this.store.instantiate(scene.frames[segment.startFrame]), allowedRootIds);
            startOverlay.classList.add("kino-stage-overlay", "kino-stage-overlay-start");
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

    prefetch(scene, frameIndex) {
      const source = scene.frames[frameIndex];
      if (source) this.store.loadText(source).catch(() => {});
      const segment = segmentForFrame(scene, frameIndex);
      if (!segment) return;
      this.store.loadText(scene.frames[segment.startFrame]).catch(() => {});
      this.store.loadText(scene.frames[segment.endFrame]).catch(() => {});
    }
  }

  globalThis.KinoMorphRuntime = {
    createStageRenderer(stage, options) {
      return new StageRenderer(stage, options);
    },
    sceneKeyframes,
    segmentForFrame,
  };
})();
