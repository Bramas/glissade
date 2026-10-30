import { describe, expect, test } from "bun:test";
import "../web/runtime/index.js";

const { BoundedCache, memoizeAsync, advancePlaybackFrame, decodeDataUri } = globalThis.__glissadeMorphRuntime;
const { SvgFrameStore, validateManifest } = globalThis.GlissadeMorphRuntime;

describe("playback boundaries", () => {
  const scene = { frameCount: 11, cuts: [{ frame: 5, loop: false }, { frame: 10, loop: false }] };
  test("pauses at cuts even when several frames are skipped", () => {
    expect(advancePlaybackFrame(scene, 0, 100)).toEqual({ frame: 5, cut: scene.cuts[0] });
    expect(advancePlaybackFrame(scene, 5, 100)).toEqual({ frame: 10, cut: scene.cuts[1] });
  });
  test("loops at the previous cut", () => {
    const looping = { ...scene, cuts: [{ frame: 5, loop: true }, scene.cuts[1]] };
    expect(advancePlaybackFrame(looping, 0, 12)).toEqual({ frame: 2 });
    expect(advancePlaybackFrame(looping, 5, 10).frame).toBe(10);
  });
  test("static slides terminate", () => {
    expect(advancePlaybackFrame({ frameCount: 1, cuts: [] }, 0, 10)).toEqual({ frame: 0, ended: true });
  });
});

describe("bounded caches", () => {
  test("evicts least recently used entries and respects a byte budget", () => {
    const cache = new BoundedCache(2, 10);
    cache.set("a", 1, 4).set("b", 2, 4);
    cache.get("a");
    cache.set("c", 3, 4);
    expect(cache.has("b")).toBe(false);
    expect(cache.bytes).toBe(8);
    cache.set("large", 4, 11);
    expect(cache.size).toBe(0);
    expect(cache.bytes).toBe(0);
  });
  test("deduplicates requests, retries failures and does not resurrect cleared entries", async () => {
    const cache = new BoundedCache();
    let calls = 0;
    const factory = () => { calls++; return "hello"; };
    await Promise.all([memoizeAsync(cache, "a", factory), memoizeAsync(cache, "a", factory)]);
    expect(calls).toBe(1);
    await expect(memoizeAsync(cache, "failed", () => { throw new Error("offline"); })).rejects.toThrow("offline");
    expect(await memoizeAsync(cache, "failed", factory)).toBe("hello");
    const pending = memoizeAsync(cache, "pending", factory);
    cache.clear();
    await pending;
    expect(cache.size).toBe(0);
  });
  test("frame text remains bounded after long playback", async () => {
    const store = new SvgFrameStore();
    for (let index = 0; index < 500; index++) {
      await store.loadText("data:image/svg+xml;base64," + btoa(`<svg id="${index}"/>`));
    }
    expect(store.stats().textEntries).toBeLessThanOrEqual(120);
    store.clear();
    expect(store.stats().textBytes).toBe(0);
  });
});

test("manifest validation rejects incompatible versions and broken frame counts", () => {
  expect(() => validateManifest({ schemaVersion: 999, scenes: [] })).toThrow("schema");
  expect(() => validateManifest({ scenes: [{ id: "a", fps: 2, frameCount: 2, frames: [], cuts: [], keyframes: [] }] })).toThrow("frames");
});

test("uncompressed SVG data URIs preserve Unicode", async () => {
  const svg = '<svg><text>été ∑ 日本語</text></svg>';
  expect(await decodeDataUri("data:image/svg+xml;base64," + Buffer.from(svg).toString("base64"))).toBe(svg);
});

test("manifest rejects cyclic SVG deltas before they can hang playback", () => {
  expect(() => validateManifest({ scenes: [{ id: "a", duration: 1, fps: 2,
    frameCount: 1, frames: [{ kind: "svg-delta-v1", base: 0, patches: [] }], cuts: [], keyframes: [0] }] })).toThrow("delta base");
});
