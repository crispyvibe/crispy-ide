// Editable LaTeX (WYSIWYG) bridge — a single editable canvas, like the markdown
// rich editor. Swift pushes source via window.crispyvibesSetLatex(src); the body
// (between \begin{document}…\end{document}, or the whole file if absent) is
// rendered into ONE contenteditable surface. Prose, headings and lists are typed
// directly; pressing Enter creates new paragraphs; the toolbar applies headings/
// lists/formatting; the math palette inserts equations. Math, comments, the
// title block, and environments we don't model are read-only "atoms" embedded in
// the canvas. The preamble and postamble are preserved verbatim around the body.
//
// Serialization walks the canvas DOM in document order, so newly added content
// is captured and unmodeled source (preamble, unknown environments, comments) is
// never rewritten.
//
// Bridge surface (called from Swift):
//   window.crispyvibesSetLatex(src), window.crispyvibesSetTheme(theme),
//   window.crispyvibesApplyCommand(name), window.crispyvibesInsertText(text)
// Messages posted to Swift: latexReady, latexChanged(source), latexLog.
(function () {
  "use strict";

  var DELIMITERS = [
    { left: "$$", right: "$$", display: true },
    { left: "\\[", right: "\\]", display: true },
    { left: "$", right: "$", display: false },
    { left: "\\(", right: "\\)", display: false }
  ];

  var DOC_BEGIN = "\\begin{document}";
  var DOC_END = "\\end{document}";

  var model = { pre: "", post: "" }; // preserved verbatim; body lives in the DOM
  var suppressSync = false;
  var pendingTimer = null;
  var activeEditor = null;

  // ---- utilities --------------------------------------------------------

  function escapeHtml(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
  function log(msg) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.latexLog) {
      window.webkit.messageHandlers.latexLog.postMessage(String(msg));
    }
  }
  function postChanged(source) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.latexChanged) {
      window.webkit.messageHandlers.latexChanged.postMessage(source);
    }
  }

  // ---- parsing (used to build the initial canvas) -----------------------

  function splitDocument(src) {
    var begin = src.indexOf(DOC_BEGIN);
    if (begin === -1) return { pre: "", body: src, post: "" };
    var bodyStart = begin + DOC_BEGIN.length;
    var end = src.indexOf(DOC_END, bodyStart);
    if (end === -1) end = src.length;
    return { pre: src.slice(0, bodyStart), body: src.slice(bodyStart, end), post: src.slice(end) };
  }

  function envBalance(text) {
    return (text.match(/\\begin\{/g) || []).length - (text.match(/\\end\{/g) || []).length;
  }

  // Body → blocks on blank lines, not splitting inside environments.
  function splitBlocks(body) {
    var parts = body.split(/(\n[ \t]*\n)/);
    var blocks = [];
    var i = 0;
    while (i < parts.length) {
      var text = parts[i];
      i += 2;
      while (envBalance(text) > 0 && i - 1 < parts.length) {
        text += (parts[i - 1] || "") + (parts[i] || "");
        i += 2;
      }
      peelBlocks(text).forEach(function (b) { blocks.push(b); });
    }
    return blocks;
  }

  function matchingBrace(s, openIdx) {
    var depth = 0;
    for (var i = openIdx; i < s.length; i++) {
      if (s[i] === "{") depth++;
      else if (s[i] === "}") { depth--; if (depth === 0) return i; }
    }
    return -1;
  }

  function preambleField(name) {
    var m = model.pre.match(new RegExp("\\\\" + name + "\\s*\\{"));
    if (!m) return "";
    var open = m.index + m[0].length - 1;
    var close = matchingBrace(model.pre, open);
    return close < 0 ? "" : model.pre.slice(open + 1, close).trim();
  }

  // Peel leading comments and sectioning commands into their own blocks.
  function peelBlocks(text) {
    var blocks = [];
    var rest = text;
    while (true) {
      var cm = rest.match(/^([ \t]*%[^\n]*(?:\n[ \t]*%[^\n]*)*)\n?/);
      if (cm && cm[1].length) {
        blocks.push({ kind: "comment", src: cm[1] });
        var afterC = rest.slice(cm[0].length);
        if (afterC.trim() === "") return blocks;
        rest = afterC;
        continue;
      }
      var hm = rest.match(/^(\s*)(\\(?:sub)*section\*?|\\paragraph\*?)\s*\{/);
      if (hm) {
        var close = matchingBrace(rest, hm[0].length - 1);
        if (close >= 0) {
          blocks.push({ kind: "heading", src: rest.slice(0, close + 1) });
          var afterH = rest.slice(close + 1).replace(/^\n/, "");
          if (afterH.trim() === "") return blocks;
          rest = afterH;
          continue;
        }
      }
      break;
    }
    blocks.push({ kind: classify(rest), src: rest });
    return blocks;
  }

  function classify(text) {
    var t = text.trim();
    if (!t) return "blank";
    if (t[0] === "%") return "comment";
    if (/^\\maketitle\s*$/.test(t)) return "maketitle";
    if (/^\\(?:tableofcontents|listoffigures|listoftables|newpage|clearpage|cleardoublepage|noindent|centering|bigskip|medskip|smallskip|hrule|hline)\s*$/.test(t)) return "raw";
    if (/^\\(?:sub)*section\*?\s*\{/.test(t)) return "heading";
    if (/^\\paragraph\*?\s*\{/.test(t)) return "heading";
    if (/^\\\[[\s\S]*\\\]$/.test(t)) return "dmath";
    if (/^\$\$[\s\S]*\$\$$/.test(t)) return "dmath";
    if (/^\\begin\{(?:equation|align|alignat|gather|multline|displaymath)\*?\}/.test(t)) return "dmath";
    if (/^\\begin\{(?:itemize|enumerate)\}/.test(t)) {
      // Only model FLAT lists as editable <ul>/<ol>. A list that contains a
      // nested list is preserved verbatim as a read-only atom — the flat
      // parser/serializer can't round-trip nesting, so editing it would lose
      // structure.
      var listInner = t.replace(/^\\begin\{(?:itemize|enumerate)\}/, "")
                       .replace(/\\end\{(?:itemize|enumerate)\}\s*$/, "");
      return /\\begin\{(?:itemize|enumerate)\}/.test(listInner) ? "raw" : "list";
    }
    if (/^\\begin\{/.test(t)) return "raw";
    return "para";
  }

  // ---- inline rendering (LaTeX subset → HTML) ---------------------------

  function renderInline(src) {
    var s = escapeHtml(src);
    var math = [];
    // Protect an escaped dollar (\$ — a literal "$" in LaTeX) so it is not
    // mistaken for an inline-math delimiter and swallowed along with the text
    // up to the next "$".
    s = s.replace(/\\\$/g, "\u0000D\u0000");
    s = s.replace(/\$[^$]*\$|\\\([\s\S]*?\\\)/g, function (m) {
      math.push(m);
      return "\u0000M" + (math.length - 1) + "\u0000";
    });
    s = s
      .replace(/\\textbf\{([^{}]*)\}/g, "<strong>$1</strong>")
      .replace(/\\(?:emph|textit)\{([^{}]*)\}/g, "<em>$1</em>")
      .replace(/\\underline\{([^{}]*)\}/g, "<u>$1</u>")
      .replace(/\\texttt\{([^{}]*)\}/g, "<code>$1</code>");
    s = s.replace(/\u0000M(\d+)\u0000/g, function (_, i) { return math[+i]; });
    // Restore as a literal "$" inside an auto-render-ignored span, so KaTeX
    // (which has no concept of an escaped dollar) won't typeset it; it
    // round-trips back to "\$" on serialize.
    s = s.replace(/\u0000D\u0000/g, '<span class="tex-esc">$</span>');
    return s;
  }

  function headingLevel(src) {
    if (/^\s*\\subsubsection/.test(src)) return 4;
    if (/^\s*\\subsection/.test(src)) return 3;
    if (/^\s*\\section/.test(src)) return 2;
    if (/^\s*\\paragraph/.test(src)) return 5;
    return 2;
  }
  function headingTitle(src) {
    var m = src.match(/\{([\s\S]*)\}\s*$/);
    return m ? m[1] : src.trim();
  }
  function headingCmd(level) {
    return level >= 5 ? "paragraph" : level >= 4 ? "subsubsection" : level >= 3 ? "subsection" : "section";
  }
  function listEnv(src) { return /\\begin\{enumerate\}/.test(src) ? "enumerate" : "itemize"; }
  function listItems(src) {
    var inner = src.replace(/^[\s\S]*?\\begin\{(?:itemize|enumerate)\}/, "")
                   .replace(/\\end\{(?:itemize|enumerate)\}[\s\S]*$/, "");
    var items = inner.split(/\\item\b/).map(function (x) { return x.trim(); });
    if (items.length && items[0] === "") items.shift();
    return items;
  }
  function dmathParts(src) {
    var t = src.trim();
    if (t.slice(0, 2) === "\\[") return { open: "\\[", close: "\\]", inner: t.slice(2).replace(/\\\]$/, "").trim(), wrap: true };
    if (t.slice(0, 2) === "$$") return { open: "$$", close: "$$", inner: t.slice(2).replace(/\$\$$/, "").trim(), wrap: true };
    return { open: "", close: "", inner: t, wrap: false };
  }

  // ---- building the canvas ----------------------------------------------

  function atom(className) {
    var el = document.createElement("div");
    el.className = "atom " + className;
    el.setAttribute("contenteditable", "false");
    return el;
  }

  function renderBlockEl(block) {
    switch (block.kind) {
      case "blank":
        return null;
      case "heading": {
        var hlevel = Math.min(headingLevel(block.src), 6);
        var h = document.createElement("h" + hlevel);
        h.innerHTML = renderInline(headingTitle(block.src)) || "<br>";
        h.dataset.srcOriginal = block.src;
        // Preserve the exact command — the \section* star and any [short]
        // optional argument — so an edited heading keeps them when its level is
        // unchanged. headingCmd() only knows the base command name.
        var hcmd = block.src.match(/\\((?:sub)*section|paragraph)(\*?)\s*(\[[^\]]*\])?/);
        if (hcmd) {
          h.dataset.headingCmd = hcmd[1] + hcmd[2];
          h.dataset.headingOpt = hcmd[3] || "";
          h.dataset.headingLevel = String(hlevel);
        }
        return h;
      }
      case "list": {
        var env = listEnv(block.src);
        var list = document.createElement(env === "enumerate" ? "ol" : "ul");
        listItems(block.src).forEach(function (item) {
          var li = document.createElement("li");
          li.innerHTML = renderInline(item) || "<br>";
          list.appendChild(li);
        });
        list.dataset.srcOriginal = block.src;
        return list;
      }
      case "para": {
        var p = document.createElement("p");
        p.innerHTML = renderInline(block.src.trim()) || "<br>";
        p.dataset.srcOriginal = block.src;
        return p;
      }
      case "dmath": {
        var dm = atom("blk-dmath");
        dm.dataset.src = block.src.trim();
        dm.title = "Click to edit equation";
        return dm;
      }
      case "comment": {
        var c = atom("blk-comment");
        c.dataset.src = block.src;
        c.textContent = block.src;
        return c;
      }
      case "maketitle": {
        var mt = atom("blk-title");
        mt.dataset.src = block.src.trim();
        renderTitleInto(mt);
        return mt;
      }
      default: { // raw / unknown — preserved verbatim, shown read-only
        var r = atom("blk-raw");
        r.dataset.src = block.src;
        var pre = document.createElement("pre");
        pre.textContent = block.src.trim();
        r.appendChild(pre);
        return r;
      }
    }
  }

  function renderTitleInto(el) {
    var title = preambleField("title");
    var author = preambleField("author");
    var hasDate = /\\date\s*\{/.test(model.pre);
    var date = (hasDate ? preambleField("date") : "\\today").replace(/\\today/g, new Date().toLocaleDateString());
    if (title) { var h = document.createElement("h1"); h.className = "doc-title"; h.innerHTML = renderInline(title); el.appendChild(h); }
    if (author) { var a = document.createElement("div"); a.className = "doc-author"; a.innerHTML = renderInline(author); el.appendChild(a); }
    if (date) { var d = document.createElement("div"); d.className = "doc-date"; d.innerHTML = renderInline(date); el.appendChild(d); }
  }

  function emptyParagraph() {
    var p = document.createElement("p");
    p.appendChild(document.createElement("br"));
    return p;
  }

  function render(src) {
    closeActiveEditor();
    var split = splitDocument(typeof src === "string" ? src : "");
    model = { pre: split.pre, post: split.post };
    var content = document.getElementById("content");
    if (!content) return;
    suppressSync = true;
    content.setAttribute("contenteditable", "true");
    content.innerHTML = "";
    splitBlocks(split.body).forEach(function (block) {
      var el = renderBlockEl(block);
      if (el) content.appendChild(el);
    });
    if (!content.childNodes.length) content.appendChild(emptyParagraph());
    typesetMath(content);
    snapshotPristine(content);
    suppressSync = false;
  }

  // Record each editable block's rendered HTML so serialization can tell which
  // blocks the user actually touched and leave the rest byte-for-byte intact.
  function snapshotPristine(content) {
    content.childNodes.forEach(function (node) {
      if (node.nodeType === 1 && node.dataset && node.dataset.srcOriginal !== undefined) {
        node.dataset.pristine = node.innerHTML;
      }
    });
  }

  // ---- math rendering + editing -----------------------------------------

  function katexTex(node) {
    var ann = node.querySelector('annotation[encoding="application/x-tex"]');
    return ann ? ann.textContent : "";
  }

  function closeActiveEditor() {
    if (activeEditor) { activeEditor.remove(); activeEditor = null; }
  }

  // Clickable templates/symbols so users build math without knowing LaTeX.
  // `{}` marks where the caret should land after inserting.
  var MATH_PALETTE = [
    { label: "a\u2044b", insert: "\\frac{}{}" },
    { label: "x\u00B2", insert: "^{}" },
    { label: "x\u2099", insert: "_{}" },
    { label: "\u221A", insert: "\\sqrt{}" },
    { label: "\u2211", insert: "\\sum_{}^{}" },
    { label: "\u222B", insert: "\\int_{}^{}" },
    { label: "\u239B\u239E", insert: "\\begin{bmatrix} {} & \\\\ & \\end{bmatrix}" },
    { label: "\u03C0", insert: "\\pi" },
    { label: "\u03B1", insert: "\\alpha" },
    { label: "\u03B2", insert: "\\beta" },
    { label: "\u03B8", insert: "\\theta" },
    { label: "\u2264", insert: "\\leq" },
    { label: "\u2265", insert: "\\geq" },
    { label: "\u2192", insert: "\\to" },
    { label: "\u00D7", insert: "\\times" },
    { label: "\u221E", insert: "\\infty" }
  ];

  function insertIntoField(field, snippet) {
    var start = field.selectionStart != null ? field.selectionStart : field.value.length;
    var end = field.selectionEnd != null ? field.selectionEnd : field.value.length;
    field.value = field.value.slice(0, start) + snippet + field.value.slice(end);
    var braceRel = snippet.indexOf("{}");
    var caret = braceRel >= 0 ? start + braceRel + 1 : start + snippet.length;
    field.selectionStart = field.selectionEnd = caret;
    field.focus();
  }

  // Visual equation editor: a live KaTeX preview + a grid of symbol/template
  // buttons. The text field is optional for power users; the preview is what
  // a non-LaTeX user watches while clicking. `onCommit(tex)` receives the TeX.
  function openMathEditor(anchorEl, tex, onCommit) {
    closeActiveEditor();
    var rect = anchorEl.getBoundingClientRect();
    var panel = document.createElement("div");
    panel.className = "math-panel";
    panel.style.position = "fixed";
    panel.style.left = Math.max(8, Math.min(rect.left, window.innerWidth - 360)) + "px";
    panel.style.top = (rect.bottom + 6) + "px";

    var preview = document.createElement("div");
    preview.className = "math-panel-preview";

    var grid = document.createElement("div");
    grid.className = "math-panel-grid";

    var field = document.createElement("textarea");
    field.className = "math-panel-field";
    field.value = tex || "";
    field.spellcheck = false;

    function updatePreview() {
      if (!window.katex) { preview.textContent = field.value; return; }
      try { window.katex.render(field.value || "\\;", preview, { displayMode: true, throwOnError: false, errorColor: "#cc0000" }); }
      catch (e) { preview.textContent = field.value; }
    }

    MATH_PALETTE.forEach(function (item) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "math-panel-key";
      b.textContent = item.label;
      b.title = item.insert;
      b.addEventListener("mousedown", function (e) {
        e.preventDefault(); // keep focus/selection in the field
        insertIntoField(field, item.insert);
        updatePreview();
      });
      grid.appendChild(b);
    });

    var actions = document.createElement("div");
    actions.className = "math-panel-actions";
    var doneBtn = document.createElement("button");
    doneBtn.type = "button"; doneBtn.className = "math-panel-done"; doneBtn.textContent = "Done";
    var cancelBtn = document.createElement("button");
    cancelBtn.type = "button"; cancelBtn.className = "math-panel-cancel"; cancelBtn.textContent = "Cancel";
    actions.appendChild(cancelBtn); actions.appendChild(doneBtn);

    panel.appendChild(preview);
    panel.appendChild(grid);
    panel.appendChild(field);
    panel.appendChild(actions);
    document.body.appendChild(panel);
    activeEditor = panel;

    // Keep the panel fully on-screen. Placing it just below the equation can
    // overflow the bottom of the editor (clipping the keypad + Done/Cancel
    // buttons), so flip it above the equation when there isn't room below;
    // otherwise clamp it within an 8px viewport margin.
    (function positionPanel() {
      var margin = 8;
      var height = panel.offsetHeight;
      var top = rect.bottom + 6;
      if (top + height > window.innerHeight - margin) {
        var above = rect.top - 6 - height;
        top = above >= margin ? above : Math.max(margin, window.innerHeight - margin - height);
      }
      panel.style.top = top + "px";
    })();

    var done = false;
    function finish(save) {
      if (done) return; done = true;
      document.removeEventListener("mousedown", onDocDown, true);
      var v = field.value;
      closeActiveEditor();
      if (save) onCommit(v);
    }
    function onDocDown(e) {
      if (!panel.contains(e.target)) finish(true); // click-away commits
    }

    field.addEventListener("input", updatePreview);
    field.addEventListener("keydown", function (e) {
      if (e.key === "Escape") { e.preventDefault(); finish(false); }
      else if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); finish(true); }
    });
    doneBtn.addEventListener("mousedown", function (e) { e.preventDefault(); finish(true); });
    cancelBtn.addEventListener("mousedown", function (e) { e.preventDefault(); finish(false); });
    setTimeout(function () { document.addEventListener("mousedown", onDocDown, true); }, 0);

    field.focus();
    updatePreview();
  }

  function renderDmathAtom(el) {
    var inner = dmathParts(el.dataset.src).inner;
    el.textContent = "";
    if (window.katex) {
      try { window.katex.render(inner, el, { displayMode: true, throwOnError: false, errorColor: "#cc0000" }); return; }
      catch (e) { log("katex display: " + e); }
    }
    el.textContent = el.dataset.src;
  }

  function bindDmathAtom(el) {
    el.addEventListener("click", function (e) {
      e.preventDefault();
      var parts = dmathParts(el.dataset.src);
      openMathEditor(el, parts.inner, function (newTex) {
        el.dataset.src = parts.wrap ? (parts.open + "\n" + newTex + "\n" + parts.close) : newTex;
        renderDmathAtom(el);
        scheduleSync();
      });
    });
  }

  // Inline / in-prose math: clicking opens the TeX editor.
  function bindProseMath(root) {
    root.querySelectorAll(".katex").forEach(function (node) {
      if (node.closest(".blk-dmath")) return; // standalone atoms handled separately
      var displayWrap = node.closest(".katex-display");
      var host = displayWrap || node;
      if (host.dataset.mathBound) return;
      host.dataset.mathBound = "1";
      host.setAttribute("contenteditable", "false");
      host.classList.add(displayWrap ? "math-display" : "math-inline");
      host.addEventListener("click", function (e) {
        e.preventDefault();
        e.stopPropagation();
        openMathEditor(host, katexTex(node), function (newTex) {
          var span = document.createElement("span");
          span.textContent = displayWrap ? ("\\[" + newTex + "\\]") : ("$" + newTex + "$");
          host.replaceWith(span);
          typesetMath(span.parentNode || root);
          scheduleSync();
        });
      });
    });
  }

  function typesetMath(root) {
    root.querySelectorAll(".blk-dmath").forEach(function (el) {
      if (!el.dataset.rendered) { renderDmathAtom(el); bindDmathAtom(el); el.dataset.rendered = "1"; }
    });
    if (window.renderMathInElement) {
      try { window.renderMathInElement(root, { delimiters: DELIMITERS, throwOnError: false, errorColor: "#cc0000", ignoredClasses: ["blk-dmath", "tex-esc"] }); }
      catch (e) { log("auto-render: " + e); }
    }
    var content = document.getElementById("content");
    bindProseMath(content || root);
  }

  // ---- serialization (canvas DOM → LaTeX) -------------------------------

  // Inline content within a block element back to LaTeX.
  function serializeInline(node) {
    var out = "";
    node.childNodes.forEach(function (child) {
      if (child.nodeType === 3) { out += child.nodeValue; return; }
      if (child.nodeType !== 1) return;
      var el = child;
      if (el.classList && (el.classList.contains("katex") || el.classList.contains("katex-display"))) {
        var tex = katexTex(el);
        if (!tex) return;
        var isDisplay = el.classList.contains("katex-display") || (el.closest && el.closest(".katex-display"));
        out += isDisplay ? ("\\[" + tex + "\\]") : ("$" + tex + "$");
        return;
      }
      if (el.classList && el.classList.contains("tex-esc")) { out += "\\$"; return; }
      var tag = el.tagName.toLowerCase();
      if (tag === "br") { out += "\n"; return; }
      if (tag === "strong" || tag === "b") { out += "\\textbf{" + serializeInline(el) + "}"; return; }
      if (tag === "em" || tag === "i") { out += "\\emph{" + serializeInline(el) + "}"; return; }
      if (tag === "u") { out += "\\underline{" + serializeInline(el) + "}"; return; }
      if (tag === "code") { out += "\\texttt{" + serializeInline(el) + "}"; return; }
      if (tag === "ul") { out += "\n\\begin{itemize}\n" + serializeInline(el) + "\\end{itemize}\n"; return; }
      if (tag === "ol") { out += "\n\\begin{enumerate}\n" + serializeInline(el) + "\\end{enumerate}\n"; return; }
      if (tag === "li") { out += "  \\item " + serializeInline(el).trim() + "\n"; return; }
      if (/^h[1-6]$/.test(tag)) {
        out += "\n\\" + headingCmd(parseInt(tag.slice(1), 10)) + "{" + serializeInline(el).trim() + "}\n";
        return;
      }
      if (tag === "div" || tag === "p") {
        var inner = serializeInline(el);
        out += (out && !/\n$/.test(out) ? "\n" : "") + inner;
        return;
      }
      out += serializeInline(el);
    });
    return out;
  }

  function listItemsLatex(listEl) {
    var s = "";
    listEl.querySelectorAll(":scope > li").forEach(function (li) {
      s += "  \\item " + serializeInline(li).trim() + "\n";
    });
    return s;
  }

  // A top-level canvas child → a LaTeX block (or null to skip).
  function blockToLatex(node) {
    if (node.nodeType === 3) { var t = node.nodeValue.trim(); return t || null; }
    if (node.nodeType !== 1) return null;
    var el = node;
    if (el.classList.contains("atom")) {
      return el.dataset.src !== undefined ? el.dataset.src : null; // preserved verbatim
    }
    // Math that ended up as a top-level node (e.g. inserted at the canvas root).
    if (el.classList.contains("katex") || el.classList.contains("katex-display")) {
      var ktex = katexTex(el);
      if (!ktex) return null;
      var disp = el.classList.contains("katex-display") || (el.closest && el.closest(".katex-display"));
      return disp ? ("\\[" + ktex + "\\]") : ("$" + ktex + "$");
    }
    var tag = el.tagName.toLowerCase();
    if (/^h[1-6]$/.test(tag)) {
      var hlvl = parseInt(tag.slice(1), 10);
      var htitle = serializeInline(el).trim();
      // Reuse the original command (incl. star + optional arg) when the level
      // is unchanged; otherwise the user re-leveled it, so emit a fresh command.
      if (el.dataset.headingCmd && el.dataset.headingLevel === String(hlvl)) {
        return "\\" + el.dataset.headingCmd + (el.dataset.headingOpt || "") + "{" + htitle + "}";
      }
      return "\\" + headingCmd(hlvl) + "{" + htitle + "}";
    }
    if (tag === "ul") return "\\begin{itemize}\n" + listItemsLatex(el) + "\\end{itemize}";
    if (tag === "ol") return "\\begin{enumerate}\n" + listItemsLatex(el) + "\\end{enumerate}";
    if (tag === "blockquote") return "\\begin{quote}\n" + serializeInline(el).trim() + "\n\\end{quote}";
    if (tag === "br") return null;
    var s = serializeInline(el).replace(/\n{3,}/g, "\n\n").trim();
    return s || null;
  }

  function serializeCanvas() {
    var content = document.getElementById("content");
    var parts = [];
    content.childNodes.forEach(function (node) {
      var s;
      // Untouched editable block → re-emit its original source verbatim, so a
      // single edit never reflows/normalizes the rest of the document.
      if (node.nodeType === 1 && node.dataset &&
          node.dataset.srcOriginal !== undefined &&
          node.dataset.pristine !== undefined &&
          node.innerHTML === node.dataset.pristine) {
        s = node.dataset.srcOriginal;
      } else {
        s = blockToLatex(node);
      }
      if (s !== null && s !== "") parts.push(s);
    });
    var body = parts.join("\n\n");
    var out = model.pre ? (model.pre + "\n" + body) : body;
    if (model.post) out += "\n" + model.post;
    return out;
  }

  function scheduleSync() {
    if (suppressSync) return;
    if (pendingTimer) clearTimeout(pendingTimer);
    pendingTimer = setTimeout(function () {
      try { postChanged(serializeCanvas()); } catch (e) { log("serialize: " + e); }
    }, 220);
  }

  // ---- bridge surface ---------------------------------------------------

  window.crispyvibesSetLatex = function (src) {
    try { render(src); } catch (e) { log("render: " + e); }
  };
  window.crispyvibesSetTheme = function (theme) {
    document.body.classList.toggle("dark", theme === "dark");
  };
  window.crispyvibesApplyCommand = function (name) {
    var map = {
      bold: ["bold"], italic: ["italic"], underline: ["underline"],
      codeBlock: ["formatBlock", "pre"],
      heading1: ["formatBlock", "h2"], heading2: ["formatBlock", "h3"],
      unorderedList: ["insertUnorderedList"], orderedList: ["insertOrderedList"]
    };
    var cmd = map[name];
    if (!cmd) return;
    focusCanvas();
    try { document.execCommand(cmd[0], false, cmd[1]); scheduleSync(); }
    catch (e) { log("command " + name + ": " + e); }
  };
  window.crispyvibesInsertText = function (text) {
    focusCanvas();
    try { insertAtCaret(document.createTextNode(String(text))); scheduleSync(); }
    catch (e) { log("insertText: " + e); }
  };

  // Insert a math snippet and render it immediately (so the palette shows
  // typeset math, not raw LaTeX). Bare fragments are wrapped in $…$; anything
  // containing an environment goes into display \[ … \].
  window.crispyvibesInsertMath = function (snippet) {
    focusCanvas();
    try {
      var s = String(snippet).trim();
      var text;
      if (/^\\\[|^\$\$/.test(s)) text = s;
      else if (/\\begin\{/.test(s)) text = "\\[" + s + "\\]";
      else if (s[0] === "$") text = s;
      else text = "$" + s + "$";
      insertAtCaret(document.createTextNode(text));
      typesetMath(document.getElementById("content"));
      scheduleSync();
    } catch (e) { log("insertMath: " + e); }
  };

  // Insert a node at the caret (or append to the last editable block when there
  // is no selection in the canvas).
  function insertAtCaret(node) {
    var content = document.getElementById("content");
    var sel = window.getSelection ? window.getSelection() : null;
    if (sel && sel.rangeCount && content.contains(sel.anchorNode)) {
      var range = sel.getRangeAt(0);
      range.deleteContents();
      range.insertNode(node);
      range.setStartAfter(node);
      range.collapse(true);
      sel.removeAllRanges();
      sel.addRange(range);
      return;
    }
    var last = content.lastElementChild;
    if (!last || last.classList.contains("atom")) {
      last = document.createElement("p");
      content.appendChild(last);
    }
    last.appendChild(node);
  }

  function focusCanvas() {
    var content = document.getElementById("content");
    if (content && document.activeElement !== content && !content.contains(document.activeElement)) {
      content.focus();
    }
  }

  // ---- lifecycle --------------------------------------------------------

  function ready() {
    var content = document.getElementById("content");
    if (content) {
      content.addEventListener("input", function () { scheduleSync(); });
      content.addEventListener("blur", function () {
        // Only flush a genuinely pending edit. On blur the caret is gone, so it
        // is safe to typeset any math the user typed (e.g. "$x^2$") before
        // serializing — this is how typed equations become rendered.
        if (!pendingTimer) return;
        clearTimeout(pendingTimer);
        pendingTimer = null;
        try { typesetMath(content); postChanged(serializeCanvas()); } catch (e) { log("serialize: " + e); }
      }, true);
    }
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.latexReady) {
      window.webkit.messageHandlers.latexReady.postMessage({});
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ready);
  } else {
    ready();
  }
})();
