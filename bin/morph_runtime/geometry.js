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

  function toSvgSpace(path, point) {
    const matrix = path.getCTM();
    if (!matrix) {
      return { x: point.x, y: point.y };
    }
    const mapped = new DOMPoint(point.x, point.y).matrixTransform(matrix);
    return { x: mapped.x, y: mapped.y };
  }

  function samplePath(path, count) {
    const totalLength = pathLength(path);
    if (totalLength <= 0) {
      return [{ x: 0, y: 0 }];
    }
    const points = [];
    const steps = Math.max(1, count - 1);
    for (let index = 0; index < count; index += 1) {
      const point = path.getPointAtLength(totalLength * index / steps);
      points.push(toSvgSpace(path, point));
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

  function elementHasVisibleUses(root) {
    return root.querySelector("use") !== null;
  }

  function collectRenderablePaths(root) {
    return [...root.querySelectorAll("path")].filter(path => {
      const fill = path.getAttribute("fill");
      const stroke = path.getAttribute("stroke");
      return fill !== "none" || stroke !== "none";
    });
  }

  function isClosedPath(path) {
    const data = path.getAttribute("d") || "";
    return /[zZ]\s*$/.test(data.trim());
  }

  function planPathPair(startPath, endPath) {
    const count = sampleCountForPair(startPath, endPath);
    return {
      startPoints: samplePath(startPath, count),
      endPoints: samplePath(endPath, count),
      closed: isClosedPath(startPath) || isClosedPath(endPath),
      fillRule: endPath.getAttribute("fill-rule") || startPath.getAttribute("fill-rule") || "nonzero",
      lineCap: endPath.getAttribute("stroke-linecap") || startPath.getAttribute("stroke-linecap") || "butt",
      lineJoin: endPath.getAttribute("stroke-linejoin") || startPath.getAttribute("stroke-linejoin") || "miter",
      miterLimit: endPath.getAttribute("stroke-miterlimit") || startPath.getAttribute("stroke-miterlimit") || "4",
      fillStart: parseColor(startPath.getAttribute("fill")),
      fillEnd: parseColor(endPath.getAttribute("fill")),
      strokeStart: parseColor(startPath.getAttribute("stroke")),
      strokeEnd: parseColor(endPath.getAttribute("stroke")),
      strokeWidthStart: parseNumeric(startPath.getAttribute("stroke-width"), 0),
      strokeWidthEnd: parseNumeric(endPath.getAttribute("stroke-width"), 0),
      opacityStart: parseNumeric(startPath.getAttribute("opacity"), 1),
      opacityEnd: parseNumeric(endPath.getAttribute("opacity"), 1),
      fillOpacityStart: parseNumeric(startPath.getAttribute("fill-opacity"), 1),
      fillOpacityEnd: parseNumeric(endPath.getAttribute("fill-opacity"), 1),
      strokeOpacityStart: parseNumeric(startPath.getAttribute("stroke-opacity"), 1),
      strokeOpacityEnd: parseNumeric(endPath.getAttribute("stroke-opacity"), 1),
    };
  }

  function planGeometryMorph(planId, startRoot, endRoot) {
    if (!startRoot || !endRoot) return null;
    if (elementHasVisibleUses(startRoot) || elementHasVisibleUses(endRoot)) return null;
    const startPaths = collectRenderablePaths(startRoot);
    const endPaths = collectRenderablePaths(endRoot);
    if (startPaths.length === 0 || startPaths.length !== endPaths.length) return null;
    return {
      rootId: planId,
      paths: startPaths.map((path, index) => planPathPair(path, endPaths[index])),
    };
  }

  function planDrawPath(path) {
    const fillEnd = parseColor(path.getAttribute("fill"));
    const strokeEnd = parseColor(path.getAttribute("stroke"));
    const strokeWidthEnd = parseNumeric(path.getAttribute("stroke-width"), 0);
    const drawStroke = colorVisible(strokeEnd)
      ? strokeEnd
      : colorVisible(fillEnd)
        ? fillEnd
        : { r: 255, g: 255, b: 255, a: 1 };
    return {
      d: path.getAttribute("d") || "",
      transform: matrixToAttribute(path.getCTM()),
      length: Math.max(pathLength(path), 1),
      fillRule: path.getAttribute("fill-rule") || "nonzero",
      lineCap: path.getAttribute("stroke-linecap") || "round",
      lineJoin: path.getAttribute("stroke-linejoin") || "round",
      miterLimit: path.getAttribute("stroke-miterlimit") || "4",
      fillEnd,
      strokeEnd,
      drawStroke,
      strokeWidthEnd,
      drawStrokeWidth: strokeWidthEnd > 0 ? strokeWidthEnd : 1.5,
      opacityEnd: parseNumeric(path.getAttribute("opacity"), 1),
      fillOpacityEnd: parseNumeric(path.getAttribute("fill-opacity"), 1),
      strokeOpacityEnd: parseNumeric(path.getAttribute("stroke-opacity"), 1),
    };
  }

  function planDrawIn(planId, endRoot) {
    if (!endRoot) return null;
    if (elementHasVisibleUses(endRoot)) return null;
    const endPaths = collectRenderablePaths(endRoot);
    if (endPaths.length === 0) return null;
    return {
      rootId: planId,
      paths: endPaths.map(planDrawPath),
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
        path.setAttribute("d", pointsToPathData(interpolatePoints(pathPlan.startPoints, pathPlan.endPoints, progress), pathPlan.closed));
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

  function makeDrawOverlay(size, plans, progress) {
    if (plans.length === 0) return null;
    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "kino-stage-frame kino-stage-overlay kino-stage-overlay-draw");
    svg.setAttribute("viewBox", "0 0 " + size.width + " " + size.height);
    svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
    const borderProgress = smoothRate(clamp(progress / 0.65, 0, 1));
    const fillProgress = smoothRate(clamp((progress - 0.2) / 0.8, 0, 1));
    const temporaryStrokeFade = smoothRate(clamp((progress - 0.72) / 0.28, 0, 1));

    for (const plan of plans) {
      const group = document.createElementNS(SVG_NS, "g");
      group.setAttribute("data-kino-generated-draw", plan.rootId);
      for (const pathPlan of plan.paths) {
        const fill = document.createElementNS(SVG_NS, "path");
        fill.setAttribute("d", pathPlan.d);
        if (pathPlan.transform) fill.setAttribute("transform", pathPlan.transform);
        fill.setAttribute("fill", interpolateColor({ ...pathPlan.fillEnd, a: 0 }, pathPlan.fillEnd, fillProgress));
        fill.setAttribute("stroke", "none");
        fill.setAttribute("opacity", String(formatNumber(pathPlan.opacityEnd)));
        fill.setAttribute("fill-opacity", String(formatNumber(pathPlan.fillOpacityEnd * fillProgress)));
        fill.setAttribute("fill-rule", pathPlan.fillRule);
        group.appendChild(fill);

        const stroke = document.createElementNS(SVG_NS, "path");
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
