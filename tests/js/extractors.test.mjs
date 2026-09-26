import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";

const source = readFileSync(new URL("../../Extensions/SafariExtension/Resources/extractors.js", import.meta.url), "utf8");

function load(html, url) {
  const dom = new JSDOM(html, { url, runScripts: "outside-only" });
  dom.window.eval(source);
  return { window: dom.window, X: dom.window.NotchmanExtractors, document: dom.window.document };
}

const LONG = "This is a long assistant answer that goes on for a while. ".repeat(6);

test("ChatGPT: extracts only assistant messages, skipping chrome", () => {
  const { X, document } = load(`
    <nav>Sidebar chat history</nav>
    <main>
      <div data-message-author-role="user"><div>User question here</div></div>
      <div data-message-author-role="assistant">
        <div class="markdown">
          <h2>Architecture</h2>
          <p>${LONG}</p>
          <ul><li>First <strong>point</strong></li><li>Second point</li></ul>
          <pre><div>python<button>Copy code</button></div><code class="language-python">print("hi")\nprint("bye")</code></pre>
          <p>See <a href="https://example.com/docs">the docs</a>.</p>
        </div>
        <div class="actions"><button>Copy</button><button>Good response</button></div>
      </div>
      <form><textarea>composer draft</textarea></form>
    </main>`, "https://chatgpt.com/c/123");

  const blocks = X.listenableBlocks(document, "chatgpt.com");
  assert.equal(blocks.length, 1);
  const text = blocks[0].text;
  assert.match(text, /^# Architecture/);
  assert.match(text, /- First point/);
  assert.match(text, /```python\nprint\("hi"\)\nprint\("bye"\)\n```/);
  assert.match(text, /\[the docs\]\(https:\/\/example\.com\/docs\)/);
  for (const junk of ["Sidebar", "User question", "Copy code", "Good response", "composer"]) {
    assert.ok(!text.includes(junk), `should not include ${junk}`);
  }
});

test("ChatGPT: short messages and streaming messages get no Listen button", () => {
  const { X, document } = load(`
    <div data-message-author-role="assistant"><div class="markdown"><p>Short.</p></div></div>
    <div data-message-author-role="assistant"><div class="markdown result-streaming"><p>${LONG}</p></div></div>
  `, "https://chatgpt.com/c/1");
  assert.equal(X.listenableBlocks(document, "chatgpt.com").length, 0);
});

test("Claude: finds assistant responses, ignores user messages and streaming", () => {
  const { X, document } = load(`
    <div data-testid="user-message"><p>${LONG}</p></div>
    <div data-is-streaming="false"><div class="font-claude-response"><p>${LONG}</p><div class="font-claude-response">nested</div></div></div>
    <div data-is-streaming="true"><div class="font-claude-response"><p>${LONG}</p></div></div>
  `, "https://claude.ai/chat/1");
  const blocks = X.listenableBlocks(document, "claude.ai");
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].site, "claude");
});

test("Reddit: post body with title, and comments, but not UI", () => {
  const { X, document } = load(`
    <shreddit-post post-title="I built an app">
      <h1 slot="title">I built an app</h1>
      <div slot="text-body"><p>${LONG}</p></div>
      <button>Upvote</button>
    </shreddit-post>
    <shreddit-comment author="sam">
      <div slot="comment"><p>${LONG}</p></div>
      <shreddit-comment author="alex"><div slot="comment"><p>Short reply</p></div></shreddit-comment>
    </shreddit-comment>
  `, "https://www.reddit.com/r/apps/comments/abc/i_built_an_app/");
  const blocks = X.listenableBlocks(document, "www.reddit.com");
  assert.equal(blocks.length, 2);
  assert.match(blocks[0].text, /^# I built an app/);
  assert.ok(!blocks[0].text.includes("Upvote"));
  assert.match(blocks[1].text, /^Comment by sam\./);
  assert.ok(!blocks[1].text.includes("Short reply"), "nested comment belongs to its own block");
});

test("Unsupported sites get no inline buttons", () => {
  const { X, document } = load(`<article><p>${LONG}</p></article>`, "https://example.com/post");
  assert.equal(X.listenableBlocks(document, "example.com").length, 0);
});

test("extractPage: generic article, selection and site payloads", () => {
  const generic = load(`
    <header>Top nav</header>
    <article><h1>Title</h1><p>${LONG}</p><p>${LONG}</p></article>
    <footer>Footer links</footer>`, "https://news.example.com/story");
  const page = generic.X.extractPage(generic.document, generic.window.location, { selection: "  picked text  " });
  assert.equal(page.site, "generic");
  assert.equal(page.selection, "picked text");
  assert.match(page.content, /# Title/);
  assert.ok(!page.content.includes("Footer links"));

  const chat = load(`
    <div data-message-author-role="assistant"><div class="markdown"><p>First answer</p></div></div>
    <div data-message-author-role="assistant"><div class="markdown"><p>Second answer</p></div></div>`,
    "https://chatgpt.com/c/9");
  const chatPage = chat.X.extractPage(chat.document, chat.window.location, { window: chat.window });
  assert.equal(chatPage.site, "chatgpt");
  assert.deepEqual(Array.from(chatPage.messages), ["First answer", "Second answer"]);
  assert.equal(chatPage.focusIndex, 1);
});

test("elementToMarkdown: tables, ordered lists, hidden text", () => {
  const { X, document } = load(`
    <div id="root">
      <span class="sr-only">ChatGPT said:</span>
      <ol><li>One</li><li>Two</li></ol>
      <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>
      <span aria-hidden="true">decorative</span>
    </div>`, "https://chatgpt.com/");
  const md = X.elementToMarkdown(document.getElementById("root"));
  assert.match(md, /1\. One\n+1\. Two/);
  assert.match(md, /\| A \| B \|\n+\| 1 \| 2 \|/);
  assert.ok(!md.includes("ChatGPT said"));
  assert.ok(!md.includes("decorative"));
});

test("Share preprocessing file returns a payload through completionFunction", () => {
  const pre = readFileSync(new URL("../../Extensions/ShareExtension/Preprocessing.js", import.meta.url), "utf8");
  const dom = new JSDOM(`<article><p>${LONG}</p></article>`, { url: "https://blog.example.com/a", runScripts: "outside-only" });
  dom.window.eval(pre);
  let result = null;
  dom.window.ExtensionPreprocessingJS.run({ completionFunction: (payload) => { result = payload; } });
  assert.equal(result.url, "https://blog.example.com/a");
  assert.equal(result.site, "generic");
  assert.ok(result.content.length > 250);
});
