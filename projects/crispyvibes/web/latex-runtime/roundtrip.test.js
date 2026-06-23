// DOM round-trip validation for latex-bridge.js (single editable canvas).
// Loads the real bridge in jsdom, drives it like the WKWebView, and captures
// what serializes back via latexChanged. Covers preservation of the preamble/
// unknown envs/comments, display-vs-inline math, environment math, the title
// block, and — for the canvas model — starting from a blank doc and ADDING
// new content (headings, paragraphs).
const fs = require("fs");
const path = require("path");
const { JSDOM } = require("jsdom");

const BRIDGE = fs.readFileSync(
  path.join(__dirname, "../../crispyvibes/Resources/LaTeXRuntime/latex-bridge.js"),
  "utf8"
);

function installKatexStub(window) {
  const doc = window.document;
  function makeKatex(tex, display) {
    const k = doc.createElement("span");
    k.className = "katex";
    const ann = doc.createElement("annotation");
    ann.setAttribute("encoding", "application/x-tex");
    ann.textContent = tex;
    k.appendChild(ann);
    if (!display) return k;
    const wrap = doc.createElement("span");
    wrap.className = "katex-display";
    wrap.appendChild(k);
    return wrap;
  }
  function replaceInTextNodes(root, re, display) {
    const walker = doc.createTreeWalker(root, window.NodeFilter.SHOW_TEXT);
    const texts = [];
    let n;
    while ((n = walker.nextNode())) {
      if (n.parentElement && n.parentElement.closest(".blk-dmath, .tex-esc")) continue;
      texts.push(n);
    }
    texts.forEach((t) => {
      const v = t.nodeValue;
      re.lastIndex = 0;
      if (!re.test(v)) return;
      re.lastIndex = 0;
      const frag = doc.createDocumentFragment();
      let last = 0, m;
      while ((m = re.exec(v))) {
        if (m.index > last) frag.appendChild(doc.createTextNode(v.slice(last, m.index)));
        frag.appendChild(makeKatex(m[1].trim(), display));
        last = re.lastIndex;
      }
      if (last < v.length) frag.appendChild(doc.createTextNode(v.slice(last)));
      t.parentNode.replaceChild(frag, t);
    });
  }
  window.katex = { render(tex, el) { el.innerHTML = ""; el.appendChild(makeKatex(tex, true)); } };
  window.renderMathInElement = function (el) {
    replaceInTextNodes(el, /\\\[([\s\S]*?)\\\]/g, true);
    replaceInTextNodes(el, /\$([^$]+)\$/g, false);
  };
}

function makeEnv() {
  const dom = new JSDOM('<!doctype html><body><div id="content"></div></body>', { runScripts: "outside-only" });
  const { window } = dom;
  const state = { changed: null, logs: [] };
  window.webkit = {
    messageHandlers: {
      latexReady: { postMessage() {} },
      latexChanged: { postMessage(s) { state.changed = s; } },
      latexLog: { postMessage(m) { state.logs.push(String(m)); } }
    }
  };
  installKatexStub(window);
  window.eval(BRIDGE);
  window.document.dispatchEvent(new window.Event("DOMContentLoaded"));
  return { window, state };
}

function fireInputAndCapture(window, state) {
  state.changed = null;
  const content = window.document.getElementById("content");
  content.dispatchEvent(new window.Event("input"));
  return new Promise((res) => setTimeout(() => res(state.changed), 280));
}

const DOC = `\\documentclass{article}
\\usepackage{amsmath}
\\title{Round Trip}
\\author{Tester}
\\begin{document}
\\maketitle

\\section{Intro}
Hello \\textbf{world} and $x^2$ inline, then display:
\\[
E = mc^2
\\]

\\begin{itemize}
\\item one
\\item two
\\end{itemize}

\\begin{align}
a &= b \\\\
c &= d
\\end{align}

% inline note
Body after comment.

\\begin{tikzpicture}
\\draw (0,0) -- (1,1);
\\end{tikzpicture}
\\end{document}
% trailing comment
`;

let failures = 0;
function check(name, cond, detail) {
  if (cond) console.log("  PASS", name);
  else { console.log("  FAIL", name, detail ? "\n     " + JSON.stringify(detail) : ""); failures++; }
}

async function run() {
  // ---- Test 1: unedited round-trip ------------------------------------
  console.log("Test 1: unedited round-trip preserves structure + unknowns");
  let env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  let out = await fireInputAndCapture(env.window, env.state);
  check("logs empty", env.state.logs.length === 0, env.state.logs);
  check("preamble preserved",
    out.includes("\\documentclass{article}") && out.includes("\\title{Round Trip}") &&
    out.includes("\\author{Tester}") && out.includes("\\begin{document}"), out);
  check("maketitle preserved with line break", /\\begin\{document\}\n\\maketitle/.test(out), out);
  check("postamble preserved", out.includes("\\end{document}\n% trailing comment"), out);
  check("tikzpicture preserved verbatim", out.includes("\\begin{tikzpicture}\n\\draw (0,0) -- (1,1);\n\\end{tikzpicture}"), out);
  check("heading present, not double-wrapped", /\\section\{Intro\}/.test(out) && !/\\section\{[^}]*\\section/.test(out), out);
  check("itemize preserved", /\\begin\{itemize\}[\s\S]*\\item one[\s\S]*\\item two[\s\S]*\\end\{itemize\}/.test(out), out);
  check("inline math stays inline", out.includes("$x^2$"), out);
  check("display math stays display (not demoted)", /\\\[\s*E = mc\^2\s*\\\]/.test(out) && !/\$E = mc\^2\$/.test(out), out);
  check("align preserved as environment, not wrapped", /\\begin\{align\}[\s\S]*a &= b[\s\S]*\\end\{align\}/.test(out) && !/\\\[\s*\\begin\{align\}/.test(out), out);
  check("comment preserved", out.includes("% inline note"), out);

  // ---- Test 2: blank document is editable -----------------------------
  console.log("Test 2: a blank document gives an editable canvas");
  env = makeEnv();
  env.window.crispyvibesSetLatex("");
  const content = env.window.document.getElementById("content");
  check("canvas is contenteditable", content.getAttribute("contenteditable") === "true");
  check("blank doc has an editable paragraph", !!content.querySelector("p"));
  // Type into it.
  content.querySelector("p").textContent = "Hello world";
  out = await fireInputAndCapture(env.window, env.state);
  check("typed text serializes", out === "Hello world", out);

  // ---- Test 3: ADD a section + paragraph to a doc ---------------------
  console.log("Test 3: adding a heading + paragraph");
  env = makeEnv();
  env.window.crispyvibesSetLatex("\\begin{document}\n\\end{document}\n");
  const c3 = env.window.document.getElementById("content");
  c3.innerHTML = "<h2>New Section</h2><p>Body text here.</p>";
  out = await fireInputAndCapture(env.window, env.state);
  check("new heading serializes", /\\section\{New Section\}/.test(out), out);
  check("new paragraph serializes", out.includes("Body text here."), out);
  check("wrapped in document body", /\\begin\{document\}\n[\s\S]*\\end\{document\}/.test(out), out);

  // ---- Test 4: edit prose, preserve the rest --------------------------
  console.log("Test 4: editing prose preserves preamble + unknowns");
  env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  const para = [...env.window.document.querySelectorAll("#content > p")].find((p) => /Hello/.test(p.textContent));
  check("found paragraph", !!para);
  if (para) {
    const tn = [...para.childNodes].find((n) => n.nodeType === 3 && /Hello/.test(n.nodeValue));
    tn.nodeValue = tn.nodeValue.replace("Hello", "Hello EDITED");
  }
  out = await fireInputAndCapture(env.window, env.state);
  check("edit reflected", out.includes("Hello EDITED"), out);
  check("display math still display", /\\\[E = mc\^2\\\]/.test(out), out);
  check("tikzpicture intact", out.includes("\\begin{tikzpicture}\n\\draw (0,0) -- (1,1);\n\\end{tikzpicture}"), out);
  check("preamble intact", out.includes("\\documentclass{article}"), out);

  // ---- Test 5: click-edit the align environment (no-op) ---------------
  console.log("Test 5: click-editing align keeps it an environment");
  env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  const dmath = env.window.document.querySelector(".blk-dmath");
  check("found display-math atom", !!dmath);
  if (dmath) {
    dmath.dispatchEvent(new env.window.Event("click"));
    const box = env.window.document.querySelector(".math-panel-field");
    check("editor opened with env body", !!box && /\\begin\{align\}/.test(box.value), box && box.value);
    if (box) box.dispatchEvent(new env.window.KeyboardEvent("keydown", { key: "Enter", metaKey: true, bubbles: true }));
  }
  out = await fireInputAndCapture(env.window, env.state);
  check("align still environment, not \\[ \\]", /\\begin\{align\}[\s\S]*\\end\{align\}/.test(out) && !/\\\[\s*\\begin\{align\}/.test(out), out);

  // ---- Test 6: display math inside prose is click-editable ------------
  console.log("Test 6: display math inside prose is click-editable");
  env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  const md = env.window.document.querySelector("#content .math-display");
  check("display math in prose is bound", !!md);
  if (md) {
    md.dispatchEvent(new env.window.Event("click"));
    const box = env.window.document.querySelector(".math-panel-field");
    check("editor opened with display tex", !!box && /E = mc\^2/.test(box.value), box && box.value);
    if (box) { box.value = "E = mc^2 + 1"; box.dispatchEvent(new env.window.KeyboardEvent("keydown", { key: "Enter", metaKey: true, bubbles: true })); }
  }
  out = await fireInputAndCapture(env.window, env.state);
  check("edited display serialized as \\[…\\]", out.includes("\\[E = mc^2 + 1\\]"), out);

  // ---- Test 7: comments are hidden, not prose -------------------------
  console.log("Test 7: comments hidden, not rendered as prose");
  env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  check("comment is a (hidden) atom", !!env.window.document.querySelector(".blk-comment"));
  check("comment not in any paragraph",
    ![...env.window.document.querySelectorAll("#content > p")].some((p) => /inline note/.test(p.textContent)));
  check("text after comment is its own paragraph",
    [...env.window.document.querySelectorAll("#content > p")].some((p) => /Body after comment/.test(p.textContent)));

  // ---- Test 8: \maketitle renders a title block -----------------------
  console.log("Test 8: \\maketitle renders the title block, keeps source");
  env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  const titleBlk = env.window.document.querySelector(".blk-title");
  check("title block rendered", !!titleBlk);
  check("title text shown", !!titleBlk && /Round Trip/.test(titleBlk.querySelector(".doc-title").textContent));
  check("author shown", !!titleBlk && /Tester/.test(titleBlk.querySelector(".doc-author").textContent));
  out = await fireInputAndCapture(env.window, env.state);
  check("\\maketitle preserved in source", /\\begin\{document\}\n\\maketitle/.test(out), out);

  // ---- Test 9: math palette inserts RENDER (not raw LaTeX) ------------
  console.log("Test 9: inserted math is rendered, not shown as raw LaTeX");
  env = makeEnv();
  env.window.crispyvibesSetLatex("");
  env.window.crispyvibesInsertMath("\\alpha");
  let content9 = env.window.document.getElementById("content");
  check("inline math rendered to .katex", !!content9.querySelector(".katex"),
    content9.innerHTML.slice(0, 120));
  out = await fireInputAndCapture(env.window, env.state);
  check("inline math serializes as $…$", out.includes("$\\alpha$"), out);

  env = makeEnv();
  env.window.crispyvibesSetLatex("");
  env.window.crispyvibesInsertMath("\\begin{bmatrix} 1 & 2 \\\\ 3 & 4 \\end{bmatrix}");
  content9 = env.window.document.getElementById("content");
  check("environment math rendered to display", !!content9.querySelector(".katex-display"),
    content9.innerHTML.slice(0, 140));
  out = await fireInputAndCapture(env.window, env.state);
  check("environment math serializes as display \\[…\\]",
    /\\\[\\begin\{bmatrix\} 1 & 2/.test(out), out);

  // ---- Test 10: blur without editing must NOT post a change ----------
  console.log("Test 10: clicking away (blur) without editing posts nothing");
  env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  await new Promise((r) => setTimeout(r, 30));
  env.state.changed = null;
  const c10 = env.window.document.getElementById("content");
  c10.dispatchEvent(new env.window.Event("blur"));
  await new Promise((r) => setTimeout(r, 60));
  check("no spurious post on blur", env.state.changed === null, env.state.changed);

  // ---- Test 11: itemize opens as an EDITABLE list --------------------
  console.log("Test 11: itemize opens as an editable list (not frozen)");
  env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  const ul = env.window.document.querySelector("#content ul");
  check("itemize rendered as <ul>", !!ul);
  check("list has two items", !!ul && ul.querySelectorAll("li").length === 2, ul && ul.innerHTML);
  check("list is NOT a frozen raw atom",
    ![...env.window.document.querySelectorAll(".blk-raw")].some((r) => /itemize/.test(r.dataset.src || "")));

  // ---- Test 12: editing one block leaves others byte-verbatim --------
  console.log("Test 12: incremental serialization (untouched blocks verbatim)");
  env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  const pEdit = [...env.window.document.querySelectorAll("#content > p")].find((p) => /Hello/.test(p.textContent));
  if (pEdit) {
    const tn = [...pEdit.childNodes].find((n) => n.nodeType === 3 && /Hello/.test(n.nodeValue));
    tn.nodeValue = tn.nodeValue.replace("Hello", "Hello EDITED");
  }
  out = await fireInputAndCapture(env.window, env.state);
  check("edited block changed", out.includes("Hello EDITED"), out);
  check("untouched list preserved verbatim (no re-indent)",
    out.includes("\\begin{itemize}\n\\item one\n\\item two\n\\end{itemize}"), out);

  // ---- Test 13: typed math renders on blur ---------------------------
  console.log("Test 13: typed math (not from palette) renders on blur");
  env = makeEnv();
  env.window.crispyvibesSetLatex("\\begin{document}\n\\end{document}\n");
  const cT = env.window.document.getElementById("content");
  cT.querySelector("p").textContent = "energy $y^2$ done";
  cT.dispatchEvent(new env.window.Event("input"));
  cT.dispatchEvent(new env.window.Event("blur", { bubbles: false }));
  await new Promise((r) => setTimeout(r, 20));
  check("typed math typeset to .katex", !!cT.querySelector(".katex"), cT.innerHTML.slice(0, 120));
  check("typed math serialized as $…$", !!env.state.changed && env.state.changed.includes("$y^2$"), env.state.changed);

  // ---- Test 14: visual math panel builds math without typing LaTeX ---
  console.log("Test 14: math panel inserts templates/symbols by clicking");
  env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  const dm14 = env.window.document.querySelector(".blk-dmath");
  dm14.dispatchEvent(new env.window.Event("click"));
  const panel = env.window.document.querySelector(".math-panel");
  check("math panel opens (preview + keys)", !!panel && !!panel.querySelector(".math-panel-preview") && panel.querySelectorAll(".math-panel-key").length > 0);
  const field14 = env.window.document.querySelector(".math-panel-field");
  field14.value = "";
  const fracKey = [...env.window.document.querySelectorAll(".math-panel-key")].find((b) => b.title === "\\frac{}{}");
  check("template key present", !!fracKey);
  if (fracKey) fracKey.dispatchEvent(new env.window.MouseEvent("mousedown", { bubbles: true, cancelable: true }));
  check("clicking template inserts LaTeX for the user", field14.value.includes("\\frac{}{}"), field14.value);

  // ---- Test 15: escaped \$ in prose is preserved, not eaten as math ---
  console.log("Test 15: escaped \\$ in prose is preserved (not parsed as math)");
  env = makeEnv();
  env.window.crispyvibesSetLatex("\\begin{document}\nPrice is \\$5 and \\$10 today.\n\\end{document}\n");
  const p15 = env.window.document.querySelector("#content p");
  check("escaped-dollar prose did not become math", !!p15 && p15.querySelectorAll(".katex").length === 0, p15 && p15.innerHTML);
  check("escaped-dollar prose text intact", !!p15 && /5 and/.test(p15.textContent) && /10 today/.test(p15.textContent), p15 && p15.textContent);
  if (p15) {
    const tn = [...p15.childNodes].find((n) => n.nodeType === 3 && /today/.test(n.nodeValue));
    if (tn) tn.nodeValue = tn.nodeValue.replace("today", "tomorrow");
  }
  out = await fireInputAndCapture(env.window, env.state);
  check("escaped dollars survive an edit round-trip", out.includes("\\$5") && out.includes("\\$10"), out);

  // ---- Test 16: editing a starred heading keeps the star ---------------
  console.log("Test 16: editing a starred heading keeps the \\section* star");
  env = makeEnv();
  env.window.crispyvibesSetLatex("\\begin{document}\n\\section*{Introduction}\nBody.\n\\end{document}\n");
  const h16 = env.window.document.querySelector("#content h2");
  check("starred heading rendered", !!h16 && /Introduction/.test(h16.textContent));
  if (h16) h16.innerHTML = "Introduction Revised";
  out = await fireInputAndCapture(env.window, env.state);
  check("edited heading keeps the star", /\\section\*\{/.test(out), out);
  check("edited heading text updated", out.includes("Introduction Revised"), out);
  check("edited heading not demoted to plain \\section{", !/\\section\{Introduction Revised\}/.test(out), out);

  // ---- Test 17: a nested list is preserved verbatim -------------------
  console.log("Test 17: a nested list is preserved verbatim (not flattened)");
  env = makeEnv();
  env.window.crispyvibesSetLatex(
    "\\begin{document}\n\\begin{itemize}\n\\item one\n\\begin{itemize}\n\\item nested a\n\\item nested b\n\\end{itemize}\n\\item two\n\\end{itemize}\n\\end{document}\n"
  );
  check("nested list is a frozen raw atom", !!env.window.document.querySelector("#content .blk-raw"));
  check("nested list is NOT an editable <ul>", !env.window.document.querySelector("#content ul"));
  out = await fireInputAndCapture(env.window, env.state);
  check("nested list preserved verbatim (both levels + all items)",
    (out.match(/\\begin\{itemize\}/g) || []).length === 2 &&
    out.includes("nested a") && out.includes("nested b") &&
    out.includes("\\item one") && out.includes("\\item two"), out);

  // ---- Test 18: comment source-line annotation matches serialization --
  console.log("Test 18: comment source-line annotation matches serialized lines");
  env = makeEnv();
  env.window.crispyvibesSetLatex(DOC);
  out = await fireInputAndCapture(env.window, env.state);
  const outLines18 = (out || "").split("\n");
  const introEl = [...env.window.document.querySelectorAll("#content [data-comment-source-line]")]
    .find((el) => el.tagName === "H2" && /Intro/.test(el.textContent));
  check("heading block carries a source line", !!introEl, introEl && introEl.outerHTML.slice(0, 80));
  if (introEl) {
    const annotated = parseInt(introEl.getAttribute("data-comment-source-line"), 10);
    const actual = outLines18.findIndex((l) => l.indexOf("\\section{Intro}") >= 0) + 1;
    check("annotated line == serialized line", annotated === actual, { annotated, actual });
  }
  // The element lookup used by setComments/scrollToAnchor resolves the block.
  check("comments API is exposed", typeof env.window.crispyvibesComments === "object" &&
    typeof env.window.crispyvibesComments.setComments === "function" &&
    typeof env.window.crispyvibesComments.scrollToAnchor === "function", typeof env.window.crispyvibesComments);

  // ---- Test 19: editing a block re-escapes LaTeX specials (BL-4) ------
  console.log("Test 19: edited block re-escapes specials (& % # _) and typography");
  env = makeEnv();
  env.window.crispyvibesSetLatex(
    "\\begin{document}\nWe kept 99.4\\% and A \\& B and x\\_y \\#1.\n\\end{document}\n"
  );
  const p19 = [...env.window.document.querySelectorAll("#content > p")].find((p) => /99\.4/.test(p.textContent));
  check("specials render as plain glyphs", !!p19 && /99\.4% and A & B and x_y #1/.test(p19.textContent), p19 && p19.textContent);
  if (p19) {
    const tn = [...p19.childNodes].find((n) => n.nodeType === 3 && /99\.4/.test(n.nodeValue));
    if (tn) tn.nodeValue = tn.nodeValue.replace("kept", "keep");
  }
  out = await fireInputAndCapture(env.window, env.state);
  check("edited block re-escapes & % # _ (no corruption)",
    out.includes("99.4\\% and A \\& B and x\\_y \\#1"), out);

  console.log(failures === 0 ? "\nALL PASSED" : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

run();
