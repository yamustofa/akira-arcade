// Tests the phone controller page (Delta/Phone Controller/controller.html) in a headless
// phone-sized Chromium against a fake iPad: an HTTP server on :18765 and a WebSocket server
// on :8766 that speaks the PhoneControllerServer protocol.
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
const wss = new WebSocketServer({ port: 8766 });
wss.on("connection", (ws) => {
  ws.on("message", (raw) => {
    const m = JSON.parse(raw); msgs.push(m);
    if (m.t === "join") {
      if (m.k === "good") ws.send(JSON.stringify({ t: "hello", slot: 0 }));
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
  let b = await box("#a");
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2); await page.mouse.down();
  await sleep(650);
  ok(masks()[0] === 16, "A press sends 16");
  ok(masks().filter((x) => x === 16).length >= 3, "held A repeats every 250 ms (" + masks().length + " msgs)");
  ok(await page.locator("#a.on").count() === 1, "A lights up");
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
    fire(document.getElementById("a"), "pointerdown", 11);
    fire(document.getElementById("b"), "pointerdown", 12);
  });
  await sleep(50);
  ok(masks().at(-1) === 48, "two thumbs: A+B = 48 (" + masks().at(-1) + ")");
  await page.evaluate(() => document.getElementById("a").dispatchEvent(new PointerEvent("pointerup", { bubbles: true, cancelable: true, pointerId: 11 })));
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

  // Server goes away → page reconnects and re-joins.
  msgs.length = 0;
  for (const c of wss.clients) c.terminate();
  await sleep(1500);
  ok(msgs.some((m) => m.t === "join"), "reconnects and re-joins after the socket drops");

  for (const [k, text] of [["full", "Already 2 players"], ["bad", "expired"], ["", "Scan the QR code"]]) {
    const p2 = await ctx.newPage();
    await p2.goto("http://localhost:18765/" + (k ? "?k=" + k : "")); await sleep(400);
    ok((await p2.textContent("#msg")).includes(text) && await p2.locator("#msg.show").count() === 1, `token "${k}" shows "${text}"`);
    if (k === "full") await p2.screenshot({ path: __dirname + "/full.png" });
    await p2.close();
  }
  const portrait = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
  await portrait.goto("http://localhost:18765/?k=good"); await sleep(300);
  ok(await portrait.locator("#rotate").isVisible(), "portrait asks to turn sideways");
  ok(errors.length === 0, "no page errors " + JSON.stringify(errors));
  await browser.close(); httpServer.close(); wss.close();
  console.log(fail ? `${fail} FAILED` : "ALL PASSED"); process.exit(fail ? 1 : 0);
})();
