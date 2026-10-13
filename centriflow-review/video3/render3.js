const { chromium }=require('/opt/node22/lib/node_modules/playwright');
const fs=require('fs'),path=require('path');
(async()=>{const mode=process.argv[2]||'full';
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const page=await b.newPage({viewport:{width:1920,height:1080},deviceScaleFactor:1});
await page.goto('file://'+path.join(__dirname,'ad3.html'),{waitUntil:'load'});
await page.waitForFunction('window.__ready===true',{timeout:8000}).catch(()=>{});
await page.evaluate(async()=>{await Promise.all(Array.from(document.images).map(im=>im.complete?1:im.decode().catch(()=>{})))});
await page.waitForTimeout(400);
const DUR=await page.evaluate('window.DURATION'),FPS=await page.evaluate('window.FPS');
if(mode==='preview'){const pdir=path.join(__dirname,'preview');fs.mkdirSync(pdir,{recursive:true});
for(const t of [2.0,5.1,8.9,11.4,15.2,17.6,24.15,28.8]){await page.evaluate(ms=>window.seekTo(ms),t*1000);await page.waitForTimeout(30);
await page.screenshot({path:path.join(pdir,'t'+String(t).replace('.','_')+'.jpg'),type:'jpeg',quality:86,clip:{x:0,y:0,width:1920,height:1080}});}
console.log('preview done');await b.close();return;}
const fdir=path.join(__dirname,'frames');fs.rmSync(fdir,{recursive:true,force:true});fs.mkdirSync(fdir,{recursive:true});
const total=Math.round(DUR*FPS),t0=Date.now();
for(let f=0;f<total;f++){await page.evaluate(ms=>window.seekTo(ms),(f/FPS)*1000);
await page.screenshot({path:path.join(fdir,String(f).padStart(5,'0')+'.jpg'),type:'jpeg',quality:92,clip:{x:0,y:0,width:1920,height:1080}});
if(f%60===0)console.log(`frame ${f}/${total} ${(100*f/total).toFixed(0)}% ${((Date.now()-t0)/1000).toFixed(0)}s`);}
console.log(`rendered ${total} in ${((Date.now()-t0)/1000).toFixed(0)}s`);await b.close();})().catch(e=>{console.error(e);process.exit(1);});
