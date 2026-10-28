// SPDX-License-Identifier: AGPL-3.0-or-later
// Frame cost of a built web app on this machine's GPU (T-202).
//
//   cd <scratch dir> && npm i playwright@1.56.1 && npx playwright install chromium
//   NODE_PATH=<scratch dir>/node_modules node tools/web_gpu_bench.mjs app/build/web
//
// Unlike tools/web_frame_bench.py, which forces software rasterisation and
// can only compare two builds, this runs headless Chrome on the real GPU
// (ANGLE/Metal on macOS) and reports the main-thread work of each frame
// (`FireAnimationFrame` in a DevTools trace): Flutter's build, layout and
// paint plus CanvasKit's command submission. Against a 16.7 ms budget that
// is a real number. It fills part of the sandbox the same way the Python
// bench does (1400x900 window, fixed click coordinates) and measures five
// scenarios: idle ambient animation, hover sweep, right-drag pan, wheel zoom
// and the clock at 10x. Check gpu_bench_map.png: a run only counts if it
// shows the populated map.
//
// macOS: Chrome is started with --use-mock-keychain (Playwright adds it as
// well). Never let it touch the login keychain.
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import path from 'node:path';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const DIR = path.resolve(process.argv[2] || 'app/build/web');
const PORT = 18766;
const GRID_LEFT = 331, GRID_TOP = 65, CELL = 42.5;
const range = (a, b) => Array.from({ length: b - a }, (_, i) => a + i);
const PLAN = [[[129, 283], range(2, 14).flatMap(x => [2, 3].map(y => [x, y]))],
  [[129, 531], range(2, 14).flatMap(x => [6, 7, 8].map(y => [x, y]))],
  [[129, 593], range(2, 14).flatMap(x => [10, 11].map(y => [x, y]))]];
const sleep = ms => new Promise(res => setTimeout(res, ms));
const cell = (cx, cy) => [GRID_LEFT + CELL * (cx + 0.5), GRID_TOP + CELL * (cy + 0.5)];

async function trace(cdp, seconds, during) {
  const events = [];
  cdp.on('Tracing.dataCollected', d => events.push(...d.value));
  const done = new Promise(res => cdp.once('Tracing.tracingComplete', res));
  await cdp.send('Tracing.start', { categories: 'devtools.timeline', transferMode: 'ReportEvents' });
  const stop = Date.now() + seconds * 1000;
  await during(stop);
  while (Date.now() < stop) await sleep(100);
  await cdp.send('Tracing.end');
  await done;
  cdp.removeAllListeners('Tracing.dataCollected');
  const raf = events.filter(e => e.name === 'FireAnimationFrame' && e.ph === 'X').map(e => e.dur / 1000);
  const q = p => { const s = [...raf].sort((x, y) => x - y); return s.length ? s[Math.min(s.length - 1, Math.floor(s.length * p))] : NaN; };
  return { frames: raf.length, fps: +(raf.length / seconds).toFixed(1), medianMs: +q(0.5).toFixed(2),
    p95Ms: +q(0.95).toFixed(2), over16: raf.filter(x => x > 16.7).length };
}

const server = spawn('python3', ['-m', 'http.server', String(PORT), '--bind', '127.0.0.1', '-d', DIR], { stdio: 'ignore' });
await sleep(800);
const browser = await chromium.launch({ args: ['--use-mock-keychain', '--use-angle=metal', '--enable-gpu-rasterization', '--ignore-gpu-blocklist'] });
try {
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 }, locale: 'en-US' });
  await page.addInitScript(() => localStorage.setItem('flutter.stadtbau.onboarding.v1', 'true'));
  await page.goto(`http://127.0.0.1:${PORT}/`);
  await page.waitForSelector('flutter-view, flt-glass-pane', { state: 'attached', timeout: 90000 });
  const renderer = await page.evaluate(() => {
    const gl = document.createElement('canvas').getContext('webgl2');
    const info = gl.getExtension('WEBGL_debug_renderer_info');
    return info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
  });
  await sleep(3000);
  await page.mouse.click(700, 152); await sleep(4000); // the sandbox row
  for (const [palette, cells] of PLAN) {
    await page.mouse.click(...palette); await sleep(400);
    for (const [cx, cy] of cells) await page.mouse.click(...cell(cx, cy));
  }
  await sleep(3000);
  await page.screenshot({ path: 'gpu_bench_map.png' });
  const cdp = await page.context().newCDPSession(page);
  const out = { renderer };
  out.idle = await trace(cdp, 6, async () => {});
  out.hover = await trace(cdp, 6, async stop => {
    for (let i = 0; Date.now() < stop; i++) { await page.mouse.move(...cell(i % 16, Math.floor(i / 16) % 16)); await sleep(16); }
  });
  out.pan = await trace(cdp, 6, async stop => {
    await page.mouse.move(700, 450);
    while (Date.now() < stop) {
      await page.mouse.down({ button: 'right' });
      for (let k = 0; k < 20; k++) { await page.mouse.move(700 + k * 6, 450 + k * 3); await sleep(16); }
      await page.mouse.up({ button: 'right' });
      for (let k = 20; k > 0; k--) { await page.mouse.move(700 + k * 6, 450 + k * 3); await sleep(16); }
    }
  });
  out.zoom = await trace(cdp, 6, async stop => {
    await page.mouse.move(700, 450);
    for (let i = 0; Date.now() < stop; i++) { await page.mouse.wheel(0, i % 20 < 10 ? -60 : 60); await sleep(50); }
  });
  await page.mouse.click(939, 27); await sleep(2000); // 10x speed
  out.play10x = await trace(cdp, 6, async () => {});
  console.log(out.renderer);
  for (const [k, v] of Object.entries(out)) {
    if (k !== 'renderer') console.log(`${k.padEnd(8)} median ${String(v.medianMs).padStart(6)} ms  p95 ${String(v.p95Ms).padStart(6)} ms  ${v.fps} fps  over 16.7 ms: ${v.over16}/${v.frames}`);
  }
} finally {
  await browser.close();
  server.kill();
}
