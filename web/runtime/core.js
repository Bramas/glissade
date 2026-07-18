(() => {
  const runtime = globalThis.__glissadeMorphRuntime || (globalThis.__glissadeMorphRuntime = {});
  const SVG_NS = "http://www.w3.org/2000/svg";

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(value, maximum));
  }

  function lerp(start, end, t) {
    return start + (end - start) * t;
  }

  function sigmoid(value) {
    return 1 / (1 + Math.exp(-value));
  }

  function smoothRate(t, inflection = 10) {
    const start = sigmoid(-inflection / 2);
    const end = sigmoid(inflection / 2);
    const value = sigmoid(inflection * (clamp(t, 0, 1) - 0.5));
    return clamp((value - start) / (end - start), 0, 1);
  }

  function formatNumber(value) {
    return Number(value.toFixed(4));
  }

  function matrixToAttribute(matrix) {
    if (!matrix) return null;
    return "matrix(" + [
      matrix.a,
      matrix.b,
      matrix.c,
      matrix.d,
      matrix.e,
      matrix.f,
    ].map(formatNumber).join(" ") + ")";
  }

  function inverseParentTransform(element) {
    try {
      return matrixToAttribute(element?.parentElement?.getCTM?.()?.inverse());
    } catch {
      return null;
    }
  }

  function parseSvgMarkup(text) {
    const document = new DOMParser().parseFromString(text, "image/svg+xml");
    const svg = document.documentElement;
    if (!svg || svg.localName !== "svg") {
      throw new Error("Failed to parse SVG frame");
    }
    svg.classList.add("glissade-stage-frame");
    svg.setAttribute("preserveAspectRatio", svg.getAttribute("preserveAspectRatio") || "xMidYMid meet");
    return svg;
  }

  function base64Bytes(encoded) {
    const binary = atob(encoded);
    return Uint8Array.from(binary, character => character.charCodeAt(0));
  }

  async function decompressGzip(bytes) {
    if (typeof DecompressionStream === "undefined") {
      throw new Error("Compressed Glissade frames require browser support for DecompressionStream");
    }
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
    return new Response(stream).text();
  }

  async function decodeDataUri(source) {
    const svgPrefix = "data:image/svg+xml;base64,";
    if (source.startsWith(svgPrefix)) return atob(source.slice(svgPrefix.length));
    const gzipPrefix = "data:application/gzip;base64,";
    if (source.startsWith(gzipPrefix)) {
      return decompressGzip(base64Bytes(source.slice(gzipPrefix.length)));
    }
    return null;
  }

  function intrinsicSize(svg) {
    const viewBox = svg.viewBox && svg.viewBox.baseVal;
    if (viewBox && viewBox.width > 0 && viewBox.height > 0) {
      return { width: viewBox.width, height: viewBox.height };
    }
    const width = Number.parseFloat(svg.getAttribute("width") || "0");
    const height = Number.parseFloat(svg.getAttribute("height") || "0");
    if (width > 0 && height > 0) {
      return { width, height };
    }
    return { width: 1024, height: 768 };
  }

  function transformPoint(matrix, x, y) {
    return {
      x: matrix.a * x + matrix.c * y + matrix.e,
      y: matrix.b * x + matrix.d * y + matrix.f,
    };
  }

  function boundsFromPoints(points) {
    const xs = points.map(point => point.x);
    const ys = points.map(point => point.y);
    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);
    return {
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
    };
  }

  function safeBBox(element) {
    try {
      const box = element.getBBox();
      const elementMatrix = element.getCTM?.();
      const parentMatrix = element.parentElement?.getCTM?.();
      if (elementMatrix && parentMatrix?.inverse) {
        const relativeMatrix = parentMatrix.inverse().multiply(elementMatrix);
        return boundsFromPoints([
          transformPoint(relativeMatrix, box.x, box.y),
          transformPoint(relativeMatrix, box.x + box.width, box.y),
          transformPoint(relativeMatrix, box.x, box.y + box.height),
          transformPoint(relativeMatrix, box.x + box.width, box.y + box.height),
        ]);
      }
      return { x: box.x, y: box.y, width: box.width, height: box.height };
    } catch {
      return { x: 0, y: 0, width: 0, height: 0 };
    }
  }

  function safeGlobalBBox(element) {
    try {
      const box = element.getBBox();
      const matrix = element.getCTM?.();
      if (!matrix) return { x: box.x, y: box.y, width: box.width, height: box.height };
      return boundsFromPoints([
        transformPoint(matrix, box.x, box.y),
        transformPoint(matrix, box.x + box.width, box.y),
        transformPoint(matrix, box.x, box.y + box.height),
        transformPoint(matrix, box.x + box.width, box.y + box.height),
      ]);
    } catch {
      return { x: 0, y: 0, width: 0, height: 0 };
    }
  }

  function interpolateRect(start, end, t) {
    return {
      x: lerp(start.x, end.x, t),
      y: lerp(start.y, end.y, t),
      width: lerp(start.width, end.width, t),
      height: lerp(start.height, end.height, t),
    };
  }

  function rectTransform(fromRect, toRect) {
    const scaleX = fromRect.width > 0 && toRect.width > 0 ? toRect.width / fromRect.width : 1;
    const scaleY = fromRect.height > 0 && toRect.height > 0 ? toRect.height / fromRect.height : 1;
    const translateX = toRect.x - fromRect.x * scaleX;
    const translateY = toRect.y - fromRect.y * scaleY;
    return "matrix(" + [scaleX, 0, 0, scaleY, translateX, translateY].join(" ") + ")";
  }

  function rectTranslationForElement(element, fromRect, toRect) {
    const globalX = toRect.x + toRect.width / 2 - (fromRect.x + fromRect.width / 2);
    const globalY = toRect.y + toRect.height / 2 - (fromRect.y + fromRect.height / 2);
    const parentMatrix = element.parentElement?.getCTM?.();
    if (!parentMatrix?.inverse) return "translate(" + globalX + " " + globalY + ")";
    const inverse = parentMatrix.inverse();
    const localX = inverse.a * globalX + inverse.c * globalY;
    const localY = inverse.b * globalX + inverse.d * globalY;
    return "translate(" + formatNumber(localX) + " " + formatNumber(localY) + ")";
  }

  function morphSelector(id) {
    return '[data-glissade-morph="true"][data-glissade-morph-id="' + CSS.escape(id) + '"]';
  }

  function sceneKeyframes(scene) {
    const raw = Array.isArray(scene.keyframes) && scene.keyframes.length > 0
      ? scene.keyframes
      : [0, Math.max(0, scene.frameCount - 1)];
    const ordered = [...new Set(raw.map(value => clamp(Number(value) || 0, 0, Math.max(0, scene.frameCount - 1))))].sort((left, right) => left - right);
    if (ordered.length === 0) return [0];
    return ordered;
  }

  function advancePlaybackFrame(scene, startFrame, steps) {
    let frame = startFrame;
    let remaining = Math.max(0, steps);
    while (remaining > 0) {
      const cut = scene.cuts.find(item => item.frame > frame);
      const boundary = cut ? cut.frame : scene.frameCount - 1;
      const distance = boundary - frame;
      if (remaining < distance) return { frame: frame + remaining };
      frame = boundary;
      remaining -= distance;
      if (!cut) return { frame, ended: true };
      if (!cut.loop) return { frame, cut };
      const previousCut = [...scene.cuts].reverse().find(item => item.frame < cut.frame);
      const loopStart = previousCut ? previousCut.frame : 0;
      const loopLength = cut.frame - loopStart;
      if (loopLength <= 0) return { frame, cut };
      frame = loopStart;
      remaining %= loopLength;
    }
    return { frame };
  }

  function segmentForFrame(scene, frameIndex) {
    const keyframes = sceneKeyframes(scene);
    for (let index = 0; index < keyframes.length - 1; index += 1) {
      const startFrame = keyframes[index];
      const endFrame = keyframes[index + 1];
      if (frameIndex <= startFrame || frameIndex >= endFrame) continue;
      const span = endFrame - startFrame;
      const linearProgress = span > 0 ? (frameIndex - startFrame) / span : 0;
      return {
        startFrame,
        endFrame,
        linearProgress,
        progress: smoothRate(linearProgress),
      };
    }
    return null;
  }

  Object.assign(runtime, {
    SVG_NS,
    clamp,
    lerp,
    smoothRate,
    formatNumber,
    matrixToAttribute,
    inverseParentTransform,
    parseSvgMarkup,
    decodeDataUri,
    decompressGzip,
    intrinsicSize,
    safeBBox,
    safeGlobalBBox,
    interpolateRect,
    rectTransform,
    rectTranslationForElement,
    morphSelector,
    sceneKeyframes,
    advancePlaybackFrame,
    segmentForFrame,
  });
})();
