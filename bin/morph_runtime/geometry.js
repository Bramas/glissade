(() => {
  const runtime = globalThis.__kinoMorphRuntime || (globalThis.__kinoMorphRuntime = {});
  const {
    SVG_NS,
    clamp,
    lerp,
    smoothRate,
    formatNumber,
  } = runtime;

  const SAMPLE_COUNT_MIN = 24;
  const SAMPLE_COUNT_MAX = 96;

  function parseNumeric(value, fallback = 0) {
    const parsed = Number.parseFloat(value ?? "");
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function parseColor(value) {
    if (!value || value === "none") {
      return { r: 0, g: 0, b: 0, a: 0 };
    }
    const normalized = value.trim();
    if (normalized.startsWith("#")) {
      if (normalized.length === 4) {
        return {
          r: Number.parseInt(normalized[1] + normalized[1], 16),
          g: Number.parseInt(normalized[2] + normalized[2], 16),
          b: Number.parseInt(normalized[3] + normalized[3], 16),
          a: 1,
        };
      }
      if (normalized.length === 7) {
        return {
          r: Number.parseInt(normalized.slice(1, 3), 16),
          g: Number.parseInt(normalized.slice(3, 5), 16),
          b: Number.parseInt(normalized.slice(5, 7), 16),
          a: 1,
        };
      }
    }
    const rgbMatch = normalized.match(/^rgba?\(([^)]+)\)$/i);
    if (rgbMatch) {
      const parts = rgbMatch[1].split(",").map(item => item.trim());
      return {
        r: parseNumeric(parts[0], 0),
        g: parseNumeric(parts[1], 0),
        b: parseNumeric(parts[2], 0),
        a: parts[3] == null ? 1 : parseNumeric(parts[3], 1),
      };
    }
    return { r: 0, g: 0, b: 0, a: 1 };
  }

  function interpolateColor(start, end, t) {
    const a = lerp(start.a, end.a, t);
    if (a <= 0.0001) return "none";
    const r = Math.round(lerp(start.r, end.r, t));
    const g = Math.round(lerp(start.g, end.g, t));
    const b = Math.round(lerp(start.b, end.b, t));
    return "rgba(" + [r, g, b, formatNumber(a)].join(", ") + ")";
  }

  function colorVisible(color) {
    return color.a > 0.0001;
  }

  function matrixToAttribute(matrix) {
    if (!matrix) return null;
    return "matrix(" + [
      formatNumber(matrix.a),
      formatNumber(matrix.b),
      formatNumber(matrix.c),
      formatNumber(matrix.d),
      formatNumber(matrix.e),
      formatNumber(matrix.f),
    ].join(" ") + ")";
  }

  function pathLength(path) {
    try {
      return path.getTotalLength();
    } catch {
      return 0;
    }
  }

  function sampleCountForPair(startPath, endPath) {
    const length = Math.max(pathLength(startPath), pathLength(endPath));
    return clamp(Math.round(length / 6), SAMPLE_COUNT_MIN, SAMPLE_COUNT_MAX);
  }

  function toSvgSpace(matrix, point) {
    if (!matrix) {
      return { x: point.x, y: point.y };
    }
    const mapped = new DOMPoint(point.x, point.y).matrixTransform(matrix);
    return { x: mapped.x, y: mapped.y };
  }

  function samplePath(path, count, matrix) {
    const totalLength = pathLength(path);
    if (totalLength <= 0) {
      return [{ x: 0, y: 0 }];
    }
    const points = [];
    const steps = Math.max(1, count - 1);
    for (let index = 0; index < count; index += 1) {
      const point = path.getPointAtLength(totalLength * index / steps);
      points.push(toSvgSpace(matrix, point));
    }
    return points;
  }

  function pointsToPathData(points, closed) {
    if (points.length === 0) return "";
    const segments = ["M " + formatNumber(points[0].x) + " " + formatNumber(points[0].y)];
    for (let index = 1; index < points.length; index += 1) {
      segments.push("L " + formatNumber(points[index].x) + " " + formatNumber(points[index].y));
    }
    if (closed) segments.push("Z");
    return segments.join(" ");
  }

  function interpolatePoints(startPoints, endPoints, t) {
    const count = Math.min(startPoints.length, endPoints.length);
    const points = [];
    for (let index = 0; index < count; index += 1) {
      points.push({
        x: lerp(startPoints[index].x, endPoints[index].x, t),
        y: lerp(startPoints[index].y, endPoints[index].y, t),
      });
    }
    return points;
  }

  function tokenizePathData(data) {
    return data.match(/[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?/g) || [];
  }

  function planCompatiblePathData(startData, endData) {
    const startTokens = tokenizePathData(startData);
    const endTokens = tokenizePathData(endData);
    if (startTokens.length === 0 || startTokens.length !== endTokens.length) return null;
    const commands = [];
    const startNumbers = [];
    const endNumbers = [];
    for (let index = 0; index < startTokens.length; index += 1) {
      const startCommand = /^[a-zA-Z]$/.test(startTokens[index]);
      const endCommand = /^[a-zA-Z]$/.test(endTokens[index]);
      if (startCommand || endCommand) {
        if (!startCommand || !endCommand || startTokens[index] !== endTokens[index]) return null;
        commands.push({ index, value: startTokens[index] });
      } else {
        startNumbers.push(parseNumeric(startTokens[index]));
        endNumbers.push(parseNumeric(endTokens[index]));
      }
    }
    return { tokenCount: startTokens.length, commands, startNumbers, endNumbers };
  }

  function interpolatePathData(plan, progress) {
    const commandByIndex = new Map(plan.commands.map(item => [item.index, item.value]));
    const tokens = [];
    let numberIndex = 0;
    for (let index = 0; index < plan.tokenCount; index += 1) {
      const command = commandByIndex.get(index);
      if (command) {
        tokens.push(command);
      } else {
        tokens.push(String(formatNumber(lerp(
          plan.startNumbers[numberIndex],
          plan.endNumbers[numberIndex],
          progress,
        ))));
        numberIndex += 1;
      }
    }
    return tokens.join(" ");
  }

  function interpolateMatrix(start, end, progress) {
    if (!start || !end) return null;
    return {
      a: lerp(start.a, end.a, progress),
      b: lerp(start.b, end.b, progress),
      c: lerp(start.c, end.c, progress),
      d: lerp(start.d, end.d, progress),
      e: lerp(start.e, end.e, progress),
      f: lerp(start.f, end.f, progress),
    };
  }

  function boundsForPoints(points) {
    const xs = points.map(point => point.x);
    const ys = points.map(point => point.y);
    const x = Math.min(...xs);
    const y = Math.min(...ys);
    return {
      x,
      y,
      width: Math.max(...xs) - x,
      height: Math.max(...ys) - y,
    };
  }

  function transformToBounds(startTransform, startBounds, endBounds) {
    if (!startTransform || startBounds.width <= 0 || startBounds.height <= 0) return null;
    const scaleX = endBounds.width / startBounds.width;
    const scaleY = endBounds.height / startBounds.height;
    const translateX = endBounds.x - startBounds.x * scaleX;
    const translateY = endBounds.y - startBounds.y * scaleY;
    const boundsTransform = new DOMMatrix([scaleX, 0, 0, scaleY, translateX, translateY]);
    return boundsTransform.multiply(startTransform);
  }

  function collectRenderablePaths(root) {
    return [...root.querySelectorAll("path")].filter(path => {
      const fill = path.getAttribute("fill");
      const stroke = path.getAttribute("stroke");
      return fill !== "none" || (stroke !== null && stroke !== "none");
    });
  }

  function isClosedPath(path) {
    const data = path.getAttribute("d") || "";
    return /[zZ]\s*$/.test(data.trim());
  }

  function collectGeometryEntries(root) {
    const entries = collectRenderablePaths(root).map(path => ({
      element: path,
      path,
    }));
    for (const use of root.querySelectorAll("use")) {
      const path = referencedPathForUse(use, root);
      if (path) entries.push({ element: use, path });
    }
    return entries;
  }

  function planPathPair(startEntry, endEntry) {
    const startPath = startEntry.path;
    const endPath = endEntry.path;
    const startElement = startEntry.element;
    const endElement = endEntry.element;
    const count = sampleCountForPair(startPath, endPath);
    const startTransform = drawElementTransform(startElement);
    const endTransform = drawElementTransform(endElement);
    const startPoints = samplePath(startPath, count, startTransform);
    const endPoints = samplePath(endPath, count, endTransform);
    const startData = startPath.getAttribute("d") || "";
    const endData = endPath.getAttribute("d") || "";
    const directPathPlan = planCompatiblePathData(
      startData,
      endData,
    );
    const sameGlyphCandidate = startElement.localName === "use"
      && endElement.localName === "use"
      && tokenizePathData(startData).length === tokenizePathData(endData).length;
    return {
      directPathPlan,
      affinePathData: !directPathPlan && sameGlyphCandidate ? startData : null,
      startTransform,
      endTransform: !directPathPlan && sameGlyphCandidate
        ? transformToBounds(startTransform, boundsForPoints(startPoints), boundsForPoints(endPoints))
        : endTransform,
      startPoints,
      endPoints,
      closed: isClosedPath(startPath) || isClosedPath(endPath),
      fillRule: paintAttribute(endElement, endPath, "fill-rule") || paintAttribute(startElement, startPath, "fill-rule") || "nonzero",
      lineCap: paintAttribute(endElement, endPath, "stroke-linecap") || paintAttribute(startElement, startPath, "stroke-linecap") || "butt",
      lineJoin: paintAttribute(endElement, endPath, "stroke-linejoin") || paintAttribute(startElement, startPath, "stroke-linejoin") || "miter",
      miterLimit: paintAttribute(endElement, endPath, "stroke-miterlimit") || paintAttribute(startElement, startPath, "stroke-miterlimit") || "4",
      fillStart: parseColor(paintAttribute(startElement, startPath, "fill")),
      fillEnd: parseColor(paintAttribute(endElement, endPath, "fill")),
      strokeStart: parseColor(paintAttribute(startElement, startPath, "stroke")),
      strokeEnd: parseColor(paintAttribute(endElement, endPath, "stroke")),
      strokeWidthStart: parseNumeric(paintAttribute(startElement, startPath, "stroke-width"), 0),
      strokeWidthEnd: parseNumeric(paintAttribute(endElement, endPath, "stroke-width"), 0),
      opacityStart: parseNumeric(paintAttribute(startElement, startPath, "opacity"), 1),
      opacityEnd: parseNumeric(paintAttribute(endElement, endPath, "opacity"), 1),
      fillOpacityStart: parseNumeric(paintAttribute(startElement, startPath, "fill-opacity"), 1),
      fillOpacityEnd: parseNumeric(paintAttribute(endElement, endPath, "fill-opacity"), 1),
      strokeOpacityStart: parseNumeric(paintAttribute(startElement, startPath, "stroke-opacity"), 1),
      strokeOpacityEnd: parseNumeric(paintAttribute(endElement, endPath, "stroke-opacity"), 1),
    };
  }

  function planGeometryMorph(planId, startRoot, endRoot) {
    if (!startRoot || !endRoot) return null;
    const startEntries = collectGeometryEntries(startRoot);
    const endEntries = collectGeometryEntries(endRoot);
    if (startEntries.length === 0 || startEntries.length !== endEntries.length) return null;
    return {
      rootId: planId,
      paths: startEntries.map((entry, index) => planPathPair(entry, endEntries[index])),
    };
  }

  function planDrawPath(path) {
    return planDrawElement(path, path);
  }

  function paintAttribute(element, referencedPath, name) {
    return element.getAttribute(name) ?? referencedPath.getAttribute(name);
  }

  function drawElementTransform(element) {
    const matrix = element.getCTM();
    if (!matrix || element.localName !== "use") return matrix;
    const x = parseNumeric(element.getAttribute("x"), 0);
    const y = parseNumeric(element.getAttribute("y"), 0);
    return {
      a: matrix.a,
      b: matrix.b,
      c: matrix.c,
      d: matrix.d,
      e: matrix.e + matrix.a * x + matrix.c * y,
      f: matrix.f + matrix.b * x + matrix.d * y,
    };
  }

  function planDrawElement(element, referencedPath) {
    const fillEnd = parseColor(paintAttribute(element, referencedPath, "fill"));
    const strokeEnd = parseColor(paintAttribute(element, referencedPath, "stroke"));
    const strokeWidthEnd = parseNumeric(paintAttribute(element, referencedPath, "stroke-width"), 0);
    const drawStroke = colorVisible(strokeEnd)
      ? strokeEnd
      : colorVisible(fillEnd)
        ? fillEnd
        : { r: 255, g: 255, b: 255, a: 1 };
    return {
      d: referencedPath.getAttribute("d") || "",
      transform: matrixToAttribute(drawElementTransform(element)),
      length: Math.max(pathLength(referencedPath), 1),
      fillRule: paintAttribute(element, referencedPath, "fill-rule") || "nonzero",
      lineCap: paintAttribute(element, referencedPath, "stroke-linecap") || "round",
      lineJoin: paintAttribute(element, referencedPath, "stroke-linejoin") || "round",
      miterLimit: paintAttribute(element, referencedPath, "stroke-miterlimit") || "4",
      fillEnd,
      strokeEnd,
      drawStroke,
      strokeWidthEnd,
      drawStrokeWidth: strokeWidthEnd > 0 ? strokeWidthEnd : 1.5,
      opacityEnd: parseNumeric(paintAttribute(element, referencedPath, "opacity"), 1),
      fillOpacityEnd: parseNumeric(paintAttribute(element, referencedPath, "fill-opacity"), 1),
      strokeOpacityEnd: parseNumeric(paintAttribute(element, referencedPath, "stroke-opacity"), 1),
    };
  }

  function referencedPathForUse(use, root) {
    const href = use.getAttribute("href") || use.getAttribute("xlink:href") || "";
    if (!href.startsWith("#")) return null;
    const target = root.ownerDocument.querySelector("#" + CSS.escape(href.slice(1)));
    if (target?.localName === "path") return target;
    return target?.querySelector("path") || null;
  }

  function planDrawIn(planId, endRoot) {
    if (!endRoot) return null;
    const endPaths = collectRenderablePaths(endRoot);
    const usePlans = [...endRoot.querySelectorAll("use")].flatMap(use => {
      const referencedPath = referencedPathForUse(use, endRoot);
      return referencedPath ? [planDrawElement(use, referencedPath)] : [];
    });
    if (endPaths.length === 0 && usePlans.length === 0) return null;
    return {
      rootId: planId,
      paths: [...endPaths.map(planDrawPath), ...usePlans],
    };
  }

  function makeGeometryOverlay(size, plans, progress) {
    if (plans.length === 0) return null;
    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "kino-stage-frame kino-stage-overlay kino-stage-overlay-geometry");
    svg.setAttribute("viewBox", "0 0 " + size.width + " " + size.height);
    svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
    for (const plan of plans) {
      const group = document.createElementNS(SVG_NS, "g");
      group.setAttribute("data-kino-generated-morph", plan.rootId);
      for (const pathPlan of plan.paths) {
        const path = document.createElementNS(SVG_NS, "path");
        if (pathPlan.directPathPlan || pathPlan.affinePathData) {
          path.setAttribute("d", pathPlan.directPathPlan
            ? interpolatePathData(pathPlan.directPathPlan, progress)
            : pathPlan.affinePathData);
          const transform = matrixToAttribute(interpolateMatrix(
            pathPlan.startTransform,
            pathPlan.endTransform,
            progress,
          ));
          if (transform) path.setAttribute("transform", transform);
        } else {
          path.setAttribute("d", pointsToPathData(interpolatePoints(pathPlan.startPoints, pathPlan.endPoints, progress), pathPlan.closed));
        }
        path.setAttribute("fill", interpolateColor(pathPlan.fillStart, pathPlan.fillEnd, progress));
        path.setAttribute("stroke", interpolateColor(pathPlan.strokeStart, pathPlan.strokeEnd, progress));
        path.setAttribute("stroke-width", String(formatNumber(lerp(pathPlan.strokeWidthStart, pathPlan.strokeWidthEnd, progress))));
        path.setAttribute("opacity", String(formatNumber(lerp(pathPlan.opacityStart, pathPlan.opacityEnd, progress))));
        path.setAttribute("fill-opacity", String(formatNumber(lerp(pathPlan.fillOpacityStart, pathPlan.fillOpacityEnd, progress))));
        path.setAttribute("stroke-opacity", String(formatNumber(lerp(pathPlan.strokeOpacityStart, pathPlan.strokeOpacityEnd, progress))));
        path.setAttribute("fill-rule", pathPlan.fillRule);
        path.setAttribute("stroke-linecap", pathPlan.lineCap);
        path.setAttribute("stroke-linejoin", pathPlan.lineJoin);
        path.setAttribute("stroke-miterlimit", pathPlan.miterLimit);
        group.appendChild(path);
      }
      svg.appendChild(group);
    }
    return svg;
  }

  function makeDrawOverlay(size, plans, progress, progressForPlan = null) {
    if (plans.length === 0) return null;
    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "kino-stage-frame kino-stage-overlay kino-stage-overlay-draw");
    svg.setAttribute("viewBox", "0 0 " + size.width + " " + size.height);
    svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
    for (const plan of plans) {
      const planProgress = progressForPlan ? progressForPlan(plan, progress) : progress;
      const group = document.createElementNS(SVG_NS, "g");
      group.setAttribute("data-kino-generated-draw", plan.rootId);
      // Match Manim Write's default submobject timing. Its lag ratio describes
      // the delay as a fraction of one path's duration; the whole sequence is
      // then normalized back into the animation's [0, 1] interval.
      const lagRatio = plan.paths.length > 1
        ? Math.min(4 / plan.paths.length, 0.2)
        : 0;
      const fullLength = 1 + (plan.paths.length - 1) * lagRatio;
      for (const [pathIndex, pathPlan] of plan.paths.entries()) {
        const pathProgress = clamp(planProgress * fullLength - pathIndex * lagRatio, 0, 1);
        const borderProgress = smoothRate(clamp(pathProgress / 0.5, 0, 1));
        const fillProgress = smoothRate(clamp((pathProgress - 0.5) / 0.5, 0, 1));
        const temporaryStrokeFade = fillProgress;

        const fill = document.createElementNS(SVG_NS, "path");
        fill.setAttribute("data-kino-draw-path", String(pathIndex));
        fill.setAttribute("d", pathPlan.d);
        if (pathPlan.transform) fill.setAttribute("transform", pathPlan.transform);
        fill.setAttribute("fill", interpolateColor({ ...pathPlan.fillEnd, a: 0 }, pathPlan.fillEnd, fillProgress));
        fill.setAttribute("stroke", "none");
        fill.setAttribute("opacity", String(formatNumber(pathPlan.opacityEnd)));
        fill.setAttribute("fill-opacity", String(formatNumber(pathPlan.fillOpacityEnd * fillProgress)));
        fill.setAttribute("fill-rule", pathPlan.fillRule);
        group.appendChild(fill);

        const stroke = document.createElementNS(SVG_NS, "path");
        stroke.setAttribute("data-kino-draw-path", String(pathIndex));
        stroke.setAttribute("d", pathPlan.d);
        if (pathPlan.transform) stroke.setAttribute("transform", pathPlan.transform);
        stroke.setAttribute("fill", "none");
        stroke.setAttribute("stroke", interpolateColor(pathPlan.drawStroke, pathPlan.drawStroke, 1));
        stroke.setAttribute("stroke-width", String(formatNumber(pathPlan.drawStrokeWidth)));
        stroke.setAttribute("stroke-linecap", pathPlan.lineCap);
        stroke.setAttribute("stroke-linejoin", pathPlan.lineJoin);
        stroke.setAttribute("stroke-miterlimit", pathPlan.miterLimit);
        stroke.setAttribute("stroke-dasharray", String(formatNumber(pathPlan.length)));
        stroke.setAttribute("stroke-dashoffset", String(formatNumber(pathPlan.length * (1 - borderProgress))));
        const baseStrokeOpacity = colorVisible(pathPlan.strokeEnd)
          ? pathPlan.strokeOpacityEnd
          : 1 - temporaryStrokeFade;
        stroke.setAttribute("opacity", String(formatNumber(pathPlan.opacityEnd)));
        stroke.setAttribute("stroke-opacity", String(formatNumber(baseStrokeOpacity)));
        group.appendChild(stroke);
      }
      svg.appendChild(group);
    }
    return svg;
  }

  Object.assign(runtime, {
    planGeometryMorph,
    makeGeometryOverlay,
    planDrawIn,
    makeDrawOverlay,
  });
})();
