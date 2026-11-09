#!/usr/bin/env node
// Save or load browser cookies through the sandbox's DevTools port (CHROME_DEBUG=1).
//   node cookies.mjs save <file> [domain-substring]
//   node cookies.mjs load <file>
// Load also reloads any open page so the cookies take effect immediately.
import fs from 'node:fs';

const [, , cmd, file, domainFilter] = process.argv;
const base = process.env.CHROME_DEVTOOLS_URL || 'http://127.0.0.1:9222';
if (!['save', 'load'].includes(cmd) || !file) {
  console.error('usage: cookies.mjs save <file> [domain-substring] | load <file>');
  process.exit(2);
}

const { webSocketDebuggerUrl } = await (await fetch(`${base}/json/version`)).json();
const ws = new WebSocket(webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error('websocket failed')); });

let nextId = 0;
const pending = new Map();
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  const p = pending.get(m.id);
  if (!p) return;
  pending.delete(m.id);
  m.error ? p.rej(new Error(m.error.message)) : p.res(m.result);
};
const call = (method, params = {}, sessionId) => new Promise((res, rej) => {
  const id = ++nextId;
  pending.set(id, { res, rej });
  ws.send(JSON.stringify({ id, method, params, ...(sessionId && { sessionId }) }));
});

if (cmd === 'save') {
  const { cookies } = await call('Storage.getCookies');
  const selected = domainFilter ? cookies.filter((c) => c.domain.includes(domainFilter)) : cookies;
  const out = selected.map(({ name, value, domain, path, expires, httpOnly, secure, sameSite, priority }) =>
    ({ name, value, domain, path, ...(expires > 0 && { expires }), httpOnly, secure, sameSite, priority }));
  fs.writeFileSync(file, JSON.stringify(out, null, 2) + '\n');
  console.log(`saved ${out.length} cookies to ${file}`);
} else {
  const all = JSON.parse(fs.readFileSync(file, 'utf8'));
  const now = Date.now() / 1000;
  const live = all.filter((c) => !c.expires || c.expires > now);
  if (live.length) await call('Storage.setCookies', { cookies: live });
  console.log(`loaded ${live.length} cookies (${all.length - live.length} expired skipped)`);
  const { targetInfos } = await call('Target.getTargets');
  for (const t of targetInfos.filter((t) => t.type === 'page' && !t.url.startsWith('about:') && !t.url.startsWith('chrome'))) {
    const { sessionId } = await call('Target.attachToTarget', { targetId: t.targetId, flatten: true });
    await call('Page.reload', {}, sessionId);
    await call('Target.detachFromTarget', { sessionId });
  }
}
ws.close();
