(() => {
  const escapeHtml = value => value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");

  const typstKeywords = new Set([
    "align", "animate", "circle", "context", "create", "cut", "deck",
    "formula", "grid", "import", "init", "line", "meanwhile", "part", "place",
    "rect", "set", "show", "slide", "text", "then", "v", "wait",
  ]);

  const highlightTypst = source => {
    const escaped = escapeHtml(source);
    return escaped.replace(
      /(&quot;[^&]*?&quot;|"[^"\n]*")|(\/\/.*)|(#)([a-zA-Z][\w-]*)|(\b\d+(?:\.\d+)?(?:cm|mm|pt|fr|%|s)?\b)|(\b(?:true|false|none|auto|blue|green|white|purple|center|horizon|linear|smooth|sin)\b)/g,
      (match, string, comment, hash, fn, number, literal) => {
        if (string) return `<span class="tok-string">${string}</span>`;
        if (comment) return `<span class="tok-comment">${comment}</span>`;
        if (fn) {
          const tone = typstKeywords.has(fn) ? "tok-keyword" : "tok-function";
          return `<span class="tok-hash">#</span><span class="${tone}">${fn}</span>`;
        }
        if (number) return `<span class="tok-number">${number}</span>`;
        if (literal) return `<span class="tok-literal">${literal}</span>`;
        return match;
      },
    );
  };

  const highlightShell = source => escapeHtml(source).replace(
    /(#.*)|(\bpython3\b|\bglissade\.py\b|\bdev\b|\bhtml\b)|(--[\w-]+)|("[^"\n]*")/g,
    (match, comment, command, flag, string) => {
      if (comment) return `<span class="tok-comment">${comment}</span>`;
      if (command) return `<span class="tok-keyword">${command}</span>`;
      if (flag) return `<span class="tok-function">${flag}</span>`;
      if (string) return `<span class="tok-string">${string}</span>`;
      return match;
    },
  );

  const languageFor = code => {
    if (code.classList.contains("language-bash")) return "bash";
    if (code.classList.contains("language-typst")) return "typst";
    const text = code.textContent.trim();
    if (text.startsWith("python3 ") || text.includes("\npython3 ")) return "bash";
    return "typst";
  };

  globalThis.GlissadeHighlight = {
    typst: highlightTypst,
    shell: highlightShell,
    escapeHtml,
  };

  for (const code of document.querySelectorAll("pre code")) {
    const source = code.textContent;
    code.classList.add("highlighted-code");
    code.innerHTML = languageFor(code) === "bash"
      ? highlightShell(source)
      : highlightTypst(source);
  }
})();
