// Tests the phone controller page (Delta/Phone Controller/controller.html) in a headless
// phone-sized Chromium against a fake iPad: an HTTP server on :18765 that serves the page at /
// and speaks the PhoneControllerServer WebSocket protocol at /ws.
//
//   npm i --no-save ws playwright && npx playwright install chromium   (once)
//   node Scripts/test-phone-controller-page.js
//
// Writes pad.png and full.png next to this script for a visual check.
const http = require("http"), fs = require("fs"), path = require("path");
const { WebSocketServer } = require("ws");
const { chromium } = require("playwright");
const PAGE = fs.readFileSync(process.argv[2] || path.join(__dirname, "..", "Delta", "Phone Controller", "controller.html"));
const msgs = [];
let fail = 0;
const ok = (cond, name) => { console.log((cond ? "PASS " : "FAIL ") + name); if (!cond) fail++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const httpServer = http.createServer((req, res) => { res.writeHead(200, { "Content-Type": "text/html" }); res.end(PAGE); }).listen(18765);
const wss = new WebSocketServer({ server: httpServer, path: "/ws" });
wss.on("connection", (ws) => {
  ws.on("message", (raw) => {
    const m = JSON.parse(raw); msgs.push(m);
    if (m.t === "join") {
      if (m.k === "good") ws.send(JSON.stringify({ t: "hello", slot: 0, system: "nes" }));
      else if (m.k === "full") { ws.send(JSON.stringify({ t: "full" })); ws.close(); }
      else { ws.send(JSON.stringify({ t: "denied" })); ws.close(); }
    }
  });
});

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 });
  const page = await ctx.newPage();
  const errors = []; page.on("pageerror", (e) => errors.push(e.message));
  await page.goto("http://localhost:18765/?k=good");
  await sleep(500);
  ok(msgs[0] && msgs[0].t === "join" && msgs[0].k === "good", "sends join with token");
  ok((await page.textContent("#slot")) === "P1", "hello shows P1");
  ok((await page.textContent("#status")) === "Connected", "status Connected");
  await page.screenshot({ path: __dirname + "/pad.png" });

  const masks = () => msgs.filter((m) => "m" in m).map((m) => m.m);
  const box = async (sel) => page.locator(sel).boundingBox();

  msgs.length = 0;
  let b = await box("[data-bit=a]");
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2); await page.mouse.down();
  await sleep(650);
  ok(masks()[0] === 16, "A press sends 16");
  ok(masks().filter((x) => x === 16).length >= 3, "held A repeats every 250 ms (" + masks().length + " msgs)");
  ok(await page.locator("[data-bit=a].on").count() === 1, "A lights up");
  await page.mouse.up(); await sleep(100);
  ok(masks().at(-1) === 0, "release sends 0");

  msgs.length = 0;
  b = await box("#dpad");
  const cx = b.x + b.width / 2, cy = b.y + b.height / 2, r = b.width / 2;
  await page.mouse.move(cx + r * 0.8, cy); await page.mouse.down(); await sleep(50);
  await page.mouse.move(cx + r * 0.6, cy + r * 0.6, { steps: 3 }); await sleep(50);
  await page.mouse.move(cx, cy + r * 0.8, { steps: 3 }); await sleep(50);
  await page.mouse.move(cx, cy, { steps: 2 }); await sleep(50);
  await page.mouse.up(); await sleep(50);
  const seq = [...new Set(masks())];
  ok(seq[0] === 8 && seq.includes(10) && seq.includes(2) && masks().at(-1) === 0, "D-pad right → down-right → down → centre → 0: " + JSON.stringify(seq));

  msgs.length = 0;
  await page.evaluate(() => {
    const fire = (el, type, id) => el.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: id, clientX: el.getBoundingClientRect().x + 5, clientY: el.getBoundingClientRect().y + 5 }));
    fire(document.querySelector("[data-bit=a]"), "pointerdown", 11);
    fire(document.querySelector("[data-bit=b]"), "pointerdown", 12);
  });
  await sleep(50);
  ok(masks().at(-1) === 48, "two thumbs: A+B = 48 (" + masks().at(-1) + ")");
  await page.evaluate(() => document.querySelector("[data-bit=a]").dispatchEvent(new PointerEvent("pointerup", { bubbles: true, cancelable: true, pointerId: 11 })));
  await sleep(50);
  ok(masks().at(-1) === 32, "lift A keeps B = 32");
  await page.evaluate(() => window.dispatchEvent(new Event("blur")));
  await sleep(50);
  ok(masks().at(-1) === 0, "leaving the page releases all");

  msgs.length = 0;
  for (const [btn, want] of [["[data-bit=start]", 1024], ["[data-bit=select]", 2048], ["#menu", 16384]]) {
    b = await box(btn); await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2); await page.mouse.down(); await sleep(30); await page.mouse.up(); await sleep(30);
    ok(masks().includes(want), btn + " sends " + want);
  }

  // Forgiving touch: off-centre and between buttons, and sliding from one to the next (NES pad).
  msgs.length = 0;
  let ba = await box("[data-bit=a]"), bb = await box("[data-bit=b]");
  await page.mouse.move(ba.x + ba.width * 1.15, ba.y + ba.height * 1.1); await page.mouse.down(); await sleep(40);
  ok(masks().at(-1) === 16, "a touch just outside A still presses A (" + masks().at(-1) + ")");
  await page.mouse.up(); await sleep(40);
  msgs.length = 0;
  const midX = (ba.x + ba.width / 2 + bb.x + bb.width / 2) / 2, midY = ba.y + ba.height / 2;
  await page.mouse.move(midX, midY); await page.mouse.down(); await sleep(40);
  ok(masks().at(-1) === 48, "a thumb between B and A presses both (" + masks().at(-1) + ")");
  await page.mouse.up(); await sleep(40);
  msgs.length = 0;
  await page.mouse.move(bb.x + bb.width / 2, bb.y + bb.height / 2); await page.mouse.down(); await sleep(40);
  await page.mouse.move(ba.x + ba.width / 2, ba.y + ba.height / 2, { steps: 8 }); await sleep(40);
  const slide = [...new Set(masks())];
  ok(slide[0] === 32 && slide.at(-1) === 16, "sliding from B to A moves the press: " + JSON.stringify(slide));
  await page.mouse.up(); await sleep(40);
  msgs.length = 0;
  const dpBox = await box("#dpad");
  await page.mouse.move(dpBox.x + dpBox.width * 1.1, dpBox.y + dpBox.height / 2); await page.mouse.down(); await sleep(40);
  ok(masks().at(-1) === 8, "a touch right of the D-pad still presses right (" + masks().at(-1) + ")");
  await page.mouse.up(); await sleep(40);
  ok(await page.evaluate(() => getComputedStyle(document.querySelector("#status")).webkitUserSelect || getComputedStyle(document.querySelector("#status")).userSelect) === "none", "text can't be selected");

  // Server goes away → page reconnects and re-joins.
  msgs.length = 0;
  for (const c of wss.clients) c.terminate();
  await sleep(1500);
  ok(msgs.some((m) => m.t === "join"), "reconnects and re-joins after the socket drops");

  for (const [k, text] of [["full", "All 4 places are taken"], ["bad", "expired"], ["", "Scan the QR code"]]) {
    const p2 = await ctx.newPage();
    await p2.goto("http://localhost:18765/" + (k ? "?k=" + k : "")); await sleep(400);
    ok((await p2.textContent("#msg")).includes(text) && await p2.locator("#msg.show").count() === 1, `token "${k}" shows "${text}"`);
    if (k === "full") await p2.screenshot({ path: __dirname + "/full.png" });
    await p2.close();
  }
  // Console pads: hello carried "nes"; the iPad then switches games.
  const faceLabels = () => page.$$eval("#face [data-bit]", (els) => els.map((e) => e.getAttribute("aria-label") + ":" + e.dataset.bit).join(" "));
  const shoulderLabels = () => page.$$eval("#shoulders [data-bit]", (els) => els.map((e) => e.textContent + ":" + e.dataset.bit).join(" "));
  ok((await page.evaluate(() => document.body.dataset.system)) === "nes", "hello system nes styles the page");
  ok((await faceLabels()) === "B:b A:a", "NES pad: B A (" + (await faceLabels()) + ")");
  const push = (system) => { for (const c of wss.clients) c.send(JSON.stringify({ t: "system", system })); };
  push("snes"); await sleep(150);
  ok((await faceLabels()) === "X:x A:a B:b Y:y" && (await shoulderLabels()) === "L:l1 R:r1", "SNES pad: X A B Y + L R");
  await page.screenshot({ path: __dirname + "/pad-snes.png" });
  push("genesis"); await sleep(150);
  ok((await faceLabels()) === "A:x B:a C:b", "Mega Drive pad maps A/B/C to x/a/b (" + (await faceLabels()) + ")");
  ok((await page.$$eval("#smalls [data-bit]", (els) => els.map((e) => e.dataset.bit).join(" "))) === "start", "Mega Drive has only Start");
  msgs.length = 0;
  b = await box("[aria-label=C]"); await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2); await page.mouse.down(); await sleep(40); await page.mouse.up(); await sleep(40);
  ok(masks().includes(32), "Mega Drive C sends standard b (32)");
  await page.screenshot({ path: __dirname + "/pad-genesis.png" });
  push("n64"); await sleep(150);
  ok((await shoulderLabels()) === "Z:l2 L:l1 R:r1", "N64 pad: Z L R (" + (await shoulderLabels()) + ")");
  ok(await page.locator("#stick").isVisible() && !(await page.locator("#dpad").isVisible()), "N64 shows the thumb stick instead of the D-pad");
  await page.screenshot({ path: __dirname + "/pad-n64.png" });
  msgs.length = 0;
  b = await box("#stick");
  const sx = b.x + b.width / 2, sy = b.y + b.height / 2, sr = b.width * 0.36;
  await page.mouse.move(sx + sr * 0.5, sy); await page.mouse.down(); await sleep(40);
  await page.mouse.move(sx + sr * 2, sy, { steps: 3 }); await sleep(40);
  let last = msgs.filter((m) => "x" in m).at(-1);
  ok(last && last.x === 1 && last.y === 0, "stick pushed past the ring right: x 1, y 0 (" + JSON.stringify(last) + ")");
  await page.mouse.move(sx, sy - sr * 0.5, { steps: 4 }); await sleep(40);
  last = msgs.filter((m) => "x" in m).at(-1);
  ok(last && last.x === 0 && last.y === 0.5, "stick half up: x 0, y 0.5 (" + JSON.stringify(last) + ")");
  await sleep(600);
  ok(msgs.filter((m) => m.y === 0.5).length >= 3, "held stick repeats");
  await page.mouse.up(); await sleep(60);
  last = msgs.filter((m) => "x" in m).at(-1);
  ok(last && last.x === 0 && last.y === 0 && last.m === 0, "letting go centres the stick");
  msgs.length = 0;
  for (const [bit, want] of [["cUp", 1 << 15], ["cDown", 1 << 16], ["cLeft", 1 << 17], ["cRight", 1 << 18], ["l2", 1 << 12]]) {
    b = await box(`[data-bit=${bit}]`); await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2); await page.mouse.down(); await sleep(30); await page.mouse.up(); await sleep(30);
    ok(masks().includes(want), `N64 ${bit} sends ${want}`);
  }
  // Stick and a C button with two thumbs at once.
  msgs.length = 0;
  await page.evaluate(() => {
    const at = (el, dx) => { const r = el.getBoundingClientRect(); return { x: r.x + r.width / 2 + dx, y: r.y + r.height / 2 }; };
    const fire = (el, type, id, dx) => { const p = at(el, dx); el.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: id, clientX: p.x, clientY: p.y })); };
    fire(document.querySelector("#stick"), "pointerdown", 21, -1000);
    fire(document.querySelector("[data-bit=a]"), "pointerdown", 22, 0);
  });
  await sleep(50);
  last = msgs.at(-1);
  ok(last && last.m === 16 && last.x === -1, "stick left + A together (" + JSON.stringify(last) + ")");
  await page.evaluate(() => window.dispatchEvent(new Event("blur"))); await sleep(50);
  push("gba"); await sleep(150);
  ok((await faceLabels()) === "B:b A:a" && (await shoulderLabels()) === "L:l1 R:r1", "GBA pad: B A + L R");
  msgs.length = 0;
  b = await box("[data-bit=a]"); await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2); await page.mouse.down(); await sleep(30); await page.mouse.up(); await sleep(30);
  ok(masks().includes(16) && !msgs.some((m) => "x" in m), "pads without a stick send no axes");
  // Shoulders are big and don't cover the D-pad or face buttons.
  const overlap = (a, c) => !(a.x + a.width <= c.x || c.x + c.width <= a.x || a.y + a.height <= c.y || c.y + c.height <= a.y);
  const lb = await box("[data-bit=l1]"), dp = await box("#dpad"), fb = await box("#face");
  ok(lb.width >= 150 && lb.height >= 44, "GBA L is big (" + Math.round(lb.width) + "×" + Math.round(lb.height) + ")");
  ok(!overlap(lb, dp) && !overlap(await box("[data-bit=r1]"), fb), "shoulders don't cover the D-pad or face buttons");
  await page.screenshot({ path: __dirname + "/pad-gba.png" });
  push("gbc"); await sleep(150);
  await page.screenshot({ path: __dirname + "/pad-gbc.png" });
  // A pad switch while a button is held releases it.
  b = await box("[data-bit=a]"); await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2); await page.mouse.down(); await sleep(40);
  push("ds"); await sleep(150);
  ok((await page.evaluate(() => window.__akira.mask)) === 0, "switching pads releases held buttons");
  await page.mouse.up();
  push(null); await sleep(150);
  ok((await page.evaluate(() => document.body.dataset.system)) === "", "no game: default pad");

  // iPhone Safari (no Fullscreen API, not from the Home Screen) shows the Add to Home Screen hint once.
  const iphone = await browser.newContext({ viewport: { width: 844, height: 390 }, hasTouch: true, isMobile: true,
    userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1" });
  const ip = await iphone.newPage();
  await ip.addInitScript(() => { Object.defineProperty(Document.prototype, "fullscreenEnabled", { get: () => false }); });
  await ip.goto("http://localhost:18765/?k=good"); await sleep(300);
  ok(await ip.locator("#hint.show").count() === 1, "iPhone Safari shows the Home Screen hint");
  await ip.screenshot({ path: __dirname + "/pad-iphone-hint.png" });
  const close = await ip.locator("#hintClose").boundingBox(); await ip.mouse.move(close.x + 10, close.y + 10); await ip.mouse.down(); await ip.mouse.up(); await sleep(100);
  ok(await ip.locator("#hint.show").count() === 0, "hint closes");
  await ip.reload(); await sleep(300);
  ok(await ip.locator("#hint.show").count() === 0, "hint stays closed after reload");
  await iphone.close();

  const portrait = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
  await portrait.goto("http://localhost:18765/?k=good"); await sleep(300);
  ok(await portrait.locator("#rotate").isVisible(), "portrait asks to turn sideways");
  ok(errors.length === 0, "no page errors " + JSON.stringify(errors));
  await browser.close(); httpServer.close(); wss.close();
  console.log(fail ? `${fail} FAILED` : "ALL PASSED"); process.exit(fail ? 1 : 0);
})();
