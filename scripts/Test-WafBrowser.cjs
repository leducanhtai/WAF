// Node 22+, Microsoft Edge; isolated browser contexts, no raw HAR or session logs.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const delay = ms => new Promise(r => setTimeout(r, ms));
const out = path.resolve(__dirname, '../evidence/lab2/browser');
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'waf-lab2-browser-'));
const edge = path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe');
const browser = spawn(edge, ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'], { windowsHide: true, stdio: 'ignore' });
let ws;
const results = [];
async function main() {
  fs.mkdirSync(out, { recursive: true });
  const portFile = path.join(profile, 'DevToolsActivePort');
  for (let i = 0; !fs.existsSync(portFile) && i < 100; i++) await delay(100);
  const [port, endpoint] = fs.readFileSync(portFile, 'utf8').trim().split(/\r?\n/);
  ws = new WebSocket(`ws://127.0.0.1:${port}${endpoint}`);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  let next = 0;
  const pending = new Map();
  let events = [];
  ws.onmessage = ({data}) => {
    const m = JSON.parse(data);
    if (m.id && pending.has(m.id)) {
      const p = pending.get(m.id); pending.delete(m.id); clearTimeout(p.timer);
      m.error ? p.reject(new Error(m.error.message)) : p.resolve(m.result);
    } else if (m.method === 'Network.responseReceived' && m.params.response.url.endsWith('/rest/user/login')) {
      // Never retain response/request headers or token-bearing response bodies.
      events.push({url: m.params.response.url, status: m.params.response.status});
    }
  };
  function call(method, params = {}, sessionId) {
    return new Promise((resolve, reject) => {
      const id = ++next;
      const timer = setTimeout(() => { pending.delete(id); reject(new Error(`Timeout: ${method}`)); }, 15000);
      pending.set(id, {resolve, reject, timer});
      ws.send(JSON.stringify({id, method, params, ...(sessionId ? {sessionId} : {})}));
    });
  }
  for (const [test, port, email, password] of [
    ['TC01',3000,"' OR 1=1--",'lab-password'],
    ['TC02',8080,"' OR 1=1--",'lab-password'],
    ['TC03',8080,'admin@juice-sh.op','admin123']
  ]) {
    const {browserContextId} = await call('Target.createBrowserContext');
    try {
      const {targetId} = await call('Target.createTarget', {url:'about:blank', browserContextId});
      const {sessionId} = await call('Target.attachToTarget', {targetId, flatten:true});
      const c = (method, params) => call(method, params, sessionId);
      const evaluate = async expression => {
        const v = await c('Runtime.evaluate', {expression, returnByValue:true, awaitPromise:true});
        if (v.exceptionDetails) throw new Error('Browser evaluation failed');
        return v.result.value;
      };
      await c('Network.enable'); await c('Page.enable');
      await c('Page.bringToFront');
      await c('Emulation.setDeviceMetricsOverride', {width:1280,height:900,deviceScaleFactor:1,mobile:false});
      await c('Page.navigate', {url:`http://localhost:${port}/#/login`});
      for (let i=0;i<100;i++) {
        if (await evaluate(`Boolean(document.querySelector('#email') && document.querySelector('#password'))`)) break;
        await delay(100);
      }
      await delay(1000);
      await evaluate(`(() => { for (const e of document.querySelectorAll('button,a')) { if (/(Dismiss|Me want it!)$/.test(e.innerText.trim())) e.click(); } return true; })()`);
      await delay(500);
      const clean = await evaluate(`!localStorage.getItem('token') && !document.cookie.split(';').some(x => x.trim().startsWith('token='))`);
      events = [];
      await evaluate(`(() => { const set = (id,v) => {const e=document.querySelector(id); e.value=v; e.dispatchEvent(new Event('input',{bubbles:true})); e.dispatchEvent(new Event('change',{bubbles:true}));}; set('#email',${JSON.stringify(email)}); set('#password',${JSON.stringify(password)}); return true; })()`);
      await delay(300);
      const enabled = await evaluate(`!document.querySelector('#loginButton').disabled`);
      if (!enabled) throw new Error(`${test}: login button disabled`);
      const point = await evaluate(`(() => {const r=document.querySelector('#loginButton').getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2};})()`);
      await c('Input.dispatchMouseEvent', {type:'mousePressed', ...point, button:'left',clickCount:1});
      await c('Input.dispatchMouseEvent', {type:'mouseReleased', ...point, button:'left',clickCount:1});
      for(let i=0;i<100 && !events.length;i++) await delay(100);
      await delay(1000);
      const identity = await evaluate(`(async () => { const token=localStorage.getItem('token'); if(!token) return {hasToken:false}; const claims=JSON.parse(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))); const r=await fetch('/api/Users/'+Number(claims.data.id),{headers:{Authorization:'Bearer '+token}}); const j=await r.json(); return {hasToken:true,status:r.status,id:j.data?.id,email:j.data?.email,role:j.data?.role,claimMatches:claims.data.id===j.data?.id && claims.data.email===j.data?.email && claims.data.role===j.data?.role}; })()`);
      // Account menu reveals identity on the real page, when supported by the UI.
      if(identity.hasToken) await evaluate(`document.querySelector('#navbarAccount')?.click(); true`);
      await delay(300);
      console.log(`${test}: capture screenshot after HTTP ${events[0]?.status}`);
      const screenshot = await c('Page.captureScreenshot', {format:'png'});
      fs.writeFileSync(path.join(out, `${test}.png`), Buffer.from(screenshot.data,'base64'));
      const pass = clean && (test==='TC02' ? events[0]?.status===403 && !identity.hasToken : events[0]?.status===200 && identity.status===200 && identity.email==='admin@juice-sh.op' && identity.role==='admin' && identity.claimMatches);
      results.push({test,time:new Date().toISOString(),timezone:'UTC; Asia/Bangkok = UTC+07:00',url:`http://localhost:${port}/#/login`,input:{email,password},cleanContext:clean,loginNetwork:events,identity,result:pass?'PASS':'FAIL',screenshot:`${test}.png`});
      console.log(`${test} browser: ${pass?'PASS':'FAIL'} HTTP ${events[0]?.status}`);
    } finally { await call('Target.disposeBrowserContext', {browserContextId}); }
  }
  await call('Browser.close');
}
main().catch(e => { console.error(e.message); results.push({result:'FAIL',error:e.message}); process.exitCode=1; }).finally(async () => {
  fs.writeFileSync(path.join(out,'results.json'),JSON.stringify({method:'Edge headless + CDP; real form input/click; Network.responseReceived; real screenshots; DevTools panel not captured',results},null,2));
  ws?.close(); browser.kill();
  if(results.some(x=>x.result!=='PASS')) process.exitCode=1;
  // The temporary profile is outside the repository and contains session data.
  // Remove only the exact mkdtemp directory created above, after Edge exits.
  await delay(1000);
  if (path.dirname(profile) === os.tmpdir() && path.basename(profile).startsWith('waf-lab2-browser-')) {
    fs.rmSync(profile,{recursive:true,force:true,maxRetries:5,retryDelay:300});
  }
});
