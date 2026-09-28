const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  const mode = process.argv[2] || 'full';
  const dir = __dirname;
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const page = await b.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.join(dir, 'ad.html'), { waitUntil: 'load' });
  // wait for fonts/images
  await page.waitForFunction('window.__ready === true', { timeout: 8000 }).catch(()=>{});
  await page.evaluate(async () => {
    await Promise.all(Array.from(document.images).map(im => im.complete ? 1 : im.decode().catch(()=>{})));
  });
  await page.waitForTimeout(400);

  const DURATION = await page.evaluate('window.DURATION');
  const FPS = await page.evaluate('window.FPS');

  if (mode === 'preview') {
    const pdir = path.join(dir, 'preview');
    fs.mkdirSync(pdir, { recursive: true });
    const stops = [3.0, 8.5, 14.0, 20.5, 25.5, 29.5, 33.5, 37.5, 41.5, 46.5, 53.5];
    for (const t of stops) {
      await page.evaluate((ms)=>window.seekTo(ms), t*1000);
      await page.waitForTimeout(30);
      await page.screenshot({ path: path.join(pdir, 't'+String(t).replace('.','_')+'.jpg'), type:'jpeg', quality:88, clip:{x:0,y:0,width:1920,height:1080} });
    }
    console.log('preview done');
    await b.close();
    return;
  }

  const fdir = path.join(dir, 'frames');
  fs.rmSync(fdir, { recursive: true, force: true });
  fs.mkdirSync(fdir, { recursive: true });
  const total = Math.round(DURATION * FPS);
  const t0 = Date.now();
  for (let f = 0; f < total; f++) {
    const t = f / FPS;
    await page.evaluate((ms)=>window.seekTo(ms), t*1000);
    await page.screenshot({ path: path.join(fdir, String(f).padStart(5,'0')+'.jpg'), type:'jpeg', quality:92, clip:{x:0,y:0,width:1920,height:1080} });
    if (f % 60 === 0) {
      const el = (Date.now()-t0)/1000;
      console.log(`frame ${f}/${total}  ${(100*f/total).toFixed(1)}%  ${el.toFixed(0)}s`);
    }
  }
  console.log(`rendered ${total} frames in ${((Date.now()-t0)/1000).toFixed(0)}s`);
  await b.close();
})().catch(e => { console.error(e); process.exit(1); });
