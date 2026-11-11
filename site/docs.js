// Documentation page: the table of contents follows the reader, headings get
// anchor links, and each example slide only runs while it is on screen.
(() => {
  const toc = document.querySelector("[data-toc]");
  const sections = [...document.querySelectorAll(".doc-section[id]")];
  if (!toc || sections.length === 0) return;

  const list = toc.querySelector(".toc-list");
  const marker = toc.querySelector("[data-toc-marker]");
  const toggle = toc.querySelector(".toc-toggle");
  const currentLabel = toc.querySelector("[data-toc-current]");
  const links = new Map([...list.querySelectorAll('a[href^="#"]')]
    .map(link => [link.getAttribute("href").slice(1), link]));
  let current = null;

  // ---------- table of contents ----------

  function placeMarker(link) {
    marker.style.height = link.offsetHeight - 8 + "px";
    marker.style.transform = `translateY(${link.offsetTop + 4}px)`;
    marker.style.opacity = "1";
  }

  function setCurrent(section) {
    if (section === current) return;
    current = section;
    for (const [id, link] of links) {
      if (id === section.id) link.setAttribute("aria-current", "location");
      else link.removeAttribute("aria-current");
    }
    const link = links.get(section.id);
    if (!link) return;
    currentLabel.textContent = link.textContent;
    placeMarker(link);
    // Keep the current entry visible when the list itself scrolls.
    if (toc.scrollHeight > toc.clientHeight) {
      const top = link.offsetTop - toc.clientHeight / 2;
      toc.scrollTo({ top: Math.max(0, top) });
    }
  }

  // The current section is the last one whose heading passed the top third.
  function track() {
    const line = Math.min(innerHeight * 0.33, 260);
    let active = sections[0];
    for (const section of sections) {
      if (section.getBoundingClientRect().top <= line) active = section;
      else break;
    }
    const atEnd = innerHeight + scrollY >= document.documentElement.scrollHeight - 4;
    setCurrent(atEnd ? sections[sections.length - 1] : active);
  }

  let queued = false;
  const schedule = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      track();
    });
  };
  addEventListener("scroll", schedule, { passive: true });
  addEventListener("resize", () => {
    current = null;
    schedule();
  });
  if (document.fonts) document.fonts.ready.then(() => { current = null; track(); });
  track();

  function setOpen(open) {
    toc.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
  }
  toggle.addEventListener("click", () => setOpen(!toc.classList.contains("is-open")));
  list.addEventListener("click", event => {
    if (event.target instanceof Element && event.target.closest("a")) setOpen(false);
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && toc.classList.contains("is-open")) {
      setOpen(false);
      toggle.focus();
    }
  });
  document.addEventListener("click", event => {
    if (event.target instanceof Node && !toc.contains(event.target)) setOpen(false);
  });

  // ---------- headings ----------

  for (const section of sections) {
    const heading = section.querySelector("h2");
    if (!heading) continue;
    const anchor = document.createElement("a");
    anchor.className = "anchor";
    anchor.href = "#" + section.id;
    anchor.textContent = "#";
    anchor.setAttribute("aria-label", `Link to “${heading.textContent}”`);
    heading.append(anchor);
  }

  // ---------- examples ----------

  for (const card of document.querySelectorAll(".example-card")) {
    const pane = card.querySelector(".live-code");
    const pre = pane && pane.querySelector("pre");
    if (!pre) continue;
    pane.dataset.copyHost = "";
    pre.dataset.copy = "";
  }
  if (globalThis.GlissadeHighlight) globalThis.GlissadeHighlight.addCopyButtons();

  // A looping export keeps rendering for as long as it is loaded, so each one
  // is loaded when its card approaches the viewport and unloaded when it leaves.
  const frames = [...document.querySelectorAll(".example-card iframe[data-src]")];
  if ("IntersectionObserver" in globalThis) {
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) {
        const frame = entry.target;
        if (entry.isIntersecting) {
          if (!frame.getAttribute("src")) frame.src = frame.dataset.src;
        } else if (frame.getAttribute("src")) {
          frame.removeAttribute("src");
        }
      }
    }, { rootMargin: "120px 0px" });
    for (const frame of frames) observer.observe(frame);
  } else {
    for (const frame of frames) frame.src = frame.dataset.src;
  }
})();
