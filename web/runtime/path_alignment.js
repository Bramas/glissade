(() => {
  const runtime = globalThis.__glissadeMorphRuntime || (globalThis.__glissadeMorphRuntime = {});
  const { formatNumber } = runtime;

  const PARAM_COUNTS = { M: 2, L: 2, H: 1, V: 1, C: 6, S: 4, Q: 4, T: 2 };

  function point(x, y) { return { x, y }; }
  function lerpPoint(a, b, t) {
    return point(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
  }
  function samePoint(a, b) {
    return Math.abs(a.x - b.x) < 1e-7 && Math.abs(a.y - b.y) < 1e-7;
  }
  function lineSegment(from, to) {
    return {
      p0: from,
      c1: lerpPoint(from, to, 1 / 3),
      c2: lerpPoint(from, to, 2 / 3),
      p3: to,
    };
  }
  function tokens(data) {
    return data.match(/[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?/g) || [];
  }

  function parseCubicPath(data) {
    const input = tokens(data);
    const subpaths = [];
    let index = 0;
    let command = null;
    let current = point(0, 0);
    let start = point(0, 0);
    let active = null;
    let lastCubic = null;
    let lastQuadratic = null;

    function number() { return Number.parseFloat(input[index++]); }
    function coordinate(relative, x, y) {
      return relative ? point(current.x + x, current.y + y) : point(x, y);
    }
    function begin(at) {
      active = { closed: false, segments: [] };
      subpaths.push(active);
      current = at;
      start = at;
    }
    function add(segment) {
      if (!active) begin(segment.p0);
      active.segments.push(segment);
      current = segment.p3;
    }

    while (index < input.length) {
      if (/^[a-zA-Z]$/.test(input[index])) command = input[index++];
      if (!command) return null;
      const upper = command.toUpperCase();
      const relative = command !== upper;
      if (upper === "A") return null;
      if (upper === "Z") {
        if (active && !samePoint(current, start)) add(lineSegment(current, start));
        if (active) active.closed = true;
        current = start;
        lastCubic = lastQuadratic = null;
        command = null;
        continue;
      }
      const count = PARAM_COUNTS[upper];
      if (!count || index + count > input.length) return null;

      if (upper === "M") {
        const at = coordinate(relative, number(), number());
        begin(at);
        command = relative ? "l" : "L";
      } else if (upper === "L") {
        add(lineSegment(current, coordinate(relative, number(), number())));
      } else if (upper === "H") {
        const x = number();
        add(lineSegment(current, point(relative ? current.x + x : x, current.y)));
      } else if (upper === "V") {
        const y = number();
        add(lineSegment(current, point(current.x, relative ? current.y + y : y)));
      } else if (upper === "C") {
        const c1 = coordinate(relative, number(), number());
        const c2 = coordinate(relative, number(), number());
        const end = coordinate(relative, number(), number());
        add({ p0: current, c1, c2, p3: end });
        lastCubic = c2;
        lastQuadratic = null;
      } else if (upper === "S") {
        const c1 = lastCubic
          ? point(2 * current.x - lastCubic.x, 2 * current.y - lastCubic.y)
          : current;
        const c2 = coordinate(relative, number(), number());
        const end = coordinate(relative, number(), number());
        add({ p0: current, c1, c2, p3: end });
        lastCubic = c2;
        lastQuadratic = null;
      } else if (upper === "Q") {
        const control = coordinate(relative, number(), number());
        const end = coordinate(relative, number(), number());
        add({
          p0: current,
          c1: lerpPoint(current, control, 2 / 3),
          c2: lerpPoint(end, control, 2 / 3),
          p3: end,
        });
        lastQuadratic = control;
        lastCubic = null;
      } else if (upper === "T") {
        const control = lastQuadratic
          ? point(2 * current.x - lastQuadratic.x, 2 * current.y - lastQuadratic.y)
          : current;
        const end = coordinate(relative, number(), number());
        add({
          p0: current,
          c1: lerpPoint(current, control, 2 / 3),
          c2: lerpPoint(end, control, 2 / 3),
          p3: end,
        });
        lastQuadratic = control;
        lastCubic = null;
      }
      if (!(upper === "C" || upper === "S")) lastCubic = null;
      if (!(upper === "Q" || upper === "T")) lastQuadratic = null;
    }
    return subpaths.filter(path => path.segments.length > 0);
  }

  function transformPoint(matrix, value) {
    if (!matrix) return value;
    return point(
      matrix.a * value.x + matrix.c * value.y + matrix.e,
      matrix.b * value.x + matrix.d * value.y + matrix.f,
    );
  }
  function transformPath(path, matrix) {
    return {
      closed: path.closed,
      segments: path.segments.map(segment => ({
        p0: transformPoint(matrix, segment.p0),
        c1: transformPoint(matrix, segment.c1),
        c2: transformPoint(matrix, segment.c2),
        p3: transformPoint(matrix, segment.p3),
      })),
    };
  }
  function splitSegment(segment) {
    const p01 = lerpPoint(segment.p0, segment.c1, 0.5);
    const p12 = lerpPoint(segment.c1, segment.c2, 0.5);
    const p23 = lerpPoint(segment.c2, segment.p3, 0.5);
    const p012 = lerpPoint(p01, p12, 0.5);
    const p123 = lerpPoint(p12, p23, 0.5);
    const middle = lerpPoint(p012, p123, 0.5);
    return [
      { p0: segment.p0, c1: p01, c2: p012, p3: middle },
      { p0: middle, c1: p123, c2: p23, p3: segment.p3 },
    ];
  }
  function segmentLength(segment) {
    return Math.hypot(segment.c1.x - segment.p0.x, segment.c1.y - segment.p0.y)
      + Math.hypot(segment.c2.x - segment.c1.x, segment.c2.y - segment.c1.y)
      + Math.hypot(segment.p3.x - segment.c2.x, segment.p3.y - segment.c2.y);
  }
  function equalizeSegments(path, count) {
    const segments = [...path.segments];
    while (segments.length < count) {
      let longest = 0;
      for (let index = 1; index < segments.length; index += 1) {
        if (segmentLength(segments[index]) > segmentLength(segments[longest])) longest = index;
      }
      segments.splice(longest, 1, ...splitSegment(segments[longest]));
    }
    return { ...path, segments };
  }
  function signedArea(path) {
    return path.segments.reduce((area, segment) => (
      area + segment.p0.x * segment.p3.y - segment.p3.x * segment.p0.y
    ), 0) / 2;
  }
  function reversePath(path) {
    return {
      ...path,
      segments: [...path.segments].reverse().map(segment => ({
        p0: segment.p3, c1: segment.c2, c2: segment.c1, p3: segment.p0,
      })),
    };
  }
  function rotateClosedPath(path, reference) {
    if (!path.closed || path.segments.length < 2) return path;
    let bestShift = 0;
    let bestDistance = Infinity;
    for (let shift = 0; shift < path.segments.length; shift += 1) {
      let distance = 0;
      for (let index = 0; index < path.segments.length; index += 1) {
        const candidate = path.segments[(index + shift) % path.segments.length].p0;
        const target = reference.segments[index].p0;
        distance += (candidate.x - target.x) ** 2 + (candidate.y - target.y) ** 2;
      }
      if (distance < bestDistance) { bestDistance = distance; bestShift = shift; }
    }
    return {
      ...path,
      segments: path.segments.slice(bestShift).concat(path.segments.slice(0, bestShift)),
    };
  }

  function alignCubicPaths(startData, startMatrix, endData, endMatrix) {
    let startPaths = parseCubicPath(startData);
    let endPaths = parseCubicPath(endData);
    if (!startPaths || !endPaths || startPaths.length !== endPaths.length || startPaths.length === 0) return null;
    startPaths = startPaths.map(path => transformPath(path, startMatrix));
    endPaths = endPaths.map(path => transformPath(path, endMatrix));
    const pairs = [];
    for (let index = 0; index < startPaths.length; index += 1) {
      let start = startPaths[index];
      let end = endPaths[index];
      const count = Math.max(start.segments.length, end.segments.length);
      start = equalizeSegments(start, count);
      end = equalizeSegments(end, count);
      if (start.closed && end.closed && Math.sign(signedArea(start)) !== Math.sign(signedArea(end))) {
        end = reversePath(end);
      }
      end = rotateClosedPath(end, start);
      pairs.push({ start, end, closed: start.closed || end.closed });
    }
    return pairs;
  }

  function interpolateAlignedPath(pairs, progress) {
    const output = [];
    for (const pair of pairs) {
      const first = lerpPoint(pair.start.segments[0].p0, pair.end.segments[0].p0, progress);
      output.push("M", formatNumber(first.x), formatNumber(first.y));
      for (let index = 0; index < pair.start.segments.length; index += 1) {
        const start = pair.start.segments[index];
        const end = pair.end.segments[index];
        const c1 = lerpPoint(start.c1, end.c1, progress);
        const c2 = lerpPoint(start.c2, end.c2, progress);
        const p3 = lerpPoint(start.p3, end.p3, progress);
        output.push("C", formatNumber(c1.x), formatNumber(c1.y), formatNumber(c2.x), formatNumber(c2.y), formatNumber(p3.x), formatNumber(p3.y));
      }
      if (pair.closed) output.push("Z");
    }
    return output.join(" ");
  }

  Object.assign(runtime, { alignCubicPaths, interpolateAlignedPath });
})();
