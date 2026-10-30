const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('assets/biometric_session.js', 'utf8');
const TOKEN = 'foorsa_portal_token';
const KIND = 'foorsa_portal_kind';
const MARKER = 'foorsa_biometric_session';
// Results come from the page's own realm; compare their values, not their prototypes.
const plain = (value) => JSON.parse(JSON.stringify(value));

function portal({local = new Map(), tab = new Map(), config = {}, origin = 'https://student.foorsa.ma', iframe = false} = {}) {
  class Storage {
    constructor(values) { this.values = values; }
    getItem(key) { return this.values.get(key) ?? null; }
    setItem(key, value) { this.values.set(key, String(value)); }
    removeItem(key) { this.values.delete(key); }
  }
  const listeners = new Map();
  const calls = [];
  const other = [];
  let reply = async () => new Response('{}', {status: 200});
  let native = async () => null;
  const window = {
    fetch: (...args) => reply(...args),
    addEventListener: (name, handler) => listeners.set(name, handler),
    flutter_inappwebview: {callHandler: (...args) => {
      if (args[0] !== 'FoorsaStudentBiometrics') { other.push(args); return Promise.resolve(null); }
      calls.push(args);
      return Promise.resolve(native(args[1]));
    }},
  };
  window.top = iframe ? {} : window;
  const context = {window, Storage, localStorage: new Storage(local), sessionStorage: new Storage(tab),
    location: {origin, href: origin + '/'}, URL, Request, Response, Headers, Promise, setTimeout, clearTimeout};
  vm.runInNewContext(source.replace('const config = FOORSA_CONFIG;',
    `const config = ${JSON.stringify({origin: 'https://student.foorsa.ma', boot: 'boot-1', protected: false, token: null, ...config})};`), context);
  return {window, calls, other, local, tab, storage: context.localStorage, listeners,
    reply: (fn) => { reply = fn; },
    native: (fn) => { native = fn; },
    logout: () => { context.localStorage.removeItem(TOKEN); listeners.get('portal-logout')?.({}); },
    signOut: (detail = {signedOut: true}) => { context.localStorage.removeItem(TOKEN); listeners.get('portal-logout')?.({detail}); },
    ready: () => window.__foorsaBiometrics.ready('main-frame-nonce'),
    me: (token) => window.fetch('/api/portal/me', {headers: {Authorization: `Bearer ${token}`}}),
  };
}

test('existing password login is unchanged until the student opts in', () => {
  const p = portal({local: new Map([[TOKEN, 'session']])});
  assert.equal(p.storage.getItem(TOKEN), 'session');
  assert.equal(p.local.get(TOKEN), 'session');
  assert.equal(p.window.__foorsaBiometrics.protect('session'), true);
  assert.equal(p.storage.getItem(TOKEN), 'session');
  assert.equal(p.local.has(TOKEN), false);
  assert.equal(p.local.get(MARKER), '1');
  p.storage.setItem(TOKEN, 'renewed');
  assert.equal(p.storage.getItem(TOKEN), 'renewed');
  assert.equal(p.local.has(TOKEN), false);
});

test('a cold launch clears old browser credentials before the portal reads them', () => {
  const local = new Map([[TOKEN, 'old-disk-token'], [MARKER, '1']]);
  const tab = new Map([[TOKEN, 'old-tab-token'], ['foorsa_biometric_boot', 'old-boot']]);
  const p = portal({local, tab});
  assert.equal(p.storage.getItem(TOKEN), null);
  assert.equal(local.has(TOKEN), false);
});

test('only the natively unlocked token is restored; reloading after logout cannot replay it', () => {
  const local = new Map(); const tab = new Map();
  const config = {protected: true, token: 'unlocked'};
  const p = portal({local, tab, config});
  assert.equal(p.storage.getItem(TOKEN), 'unlocked');
  assert.equal(p.local.has(TOKEN), false);
  p.logout();
  const reload = portal({local, tab, config});
  assert.equal(reload.storage.getItem(TOKEN), null);
});

test('a successful authenticated probe waits for the main-frame bridge nonce', async () => {
  const p = portal({local: new Map([[TOKEN, 'student'], [KIND, 'student']])});
  await p.me('student');
  assert.equal(p.calls.length, 0);
  p.ready();
  assert.equal(p.calls.length, 1);
  assert.equal(p.calls[0][1].token, 'student');
  assert.equal(p.calls[0][1].nonce, 'main-frame-nonce');
  await p.me('student');
  assert.equal(p.calls.length, 1);
});

test('failed, cross-origin, or mismatched probes cannot suggest enrollment', async () => {
  const p = portal({local: new Map([[TOKEN, 'student']])}); p.ready();
  await p.me('someone-else');
  await p.window.fetch('https://other.foorsa.ma/api/portal/me', {headers: {Authorization: 'Bearer student'}});
  p.reply(async () => new Response('{}', {status: 401}));
  await p.me('student');
  assert.equal(p.calls.length, 0);
});

test('frames and other origins do not install the credential bridge', () => {
  assert.equal(portal({iframe: true}).window.__foorsaBiometrics, undefined);
  assert.equal(portal({origin: 'https://other.foorsa.ma'}).window.__foorsaBiometrics, undefined);
  assert.equal(portal({origin: 'http://student.foorsa.ma'}).window.__foorsaBiometrics, undefined);
});

test('mandatory password change and ambassador accounts are excluded', async () => {
  const p = portal(); p.ready();
  p.reply(async () => new Response(JSON.stringify({mustChangePassword: true}), {status: 200}));
  await p.window.fetch('/api/portal/login');
  p.storage.setItem(TOKEN, 'student');
  await p.me('student');
  assert.equal(p.calls.length, 0);
  assert.equal(p.window.__foorsaBiometrics.protect('student'), false);
  await p.window.fetch('/api/portal/change-password');
  await p.me('student');
  assert.equal(p.calls.length, 1);
  const agent = portal({local: new Map([[TOKEN, 'agent'], [KIND, 'agent']])}); agent.ready();
  await agent.me('agent');
  assert.equal(agent.calls.length, 0);
});

test('late responses from a signed-out account cannot enroll the next student', async () => {
  const p = portal({local: new Map([[TOKEN, 'first']])}); p.ready();
  let finish;
  p.reply(() => new Promise(resolve => { finish = resolve; }));
  const pending = p.me('first');
  p.logout();
  p.storage.setItem(TOKEN, 'second');
  finish(new Response('{}', {status: 200}));
  await pending;
  assert.equal(p.calls.length, 1);
  assert.equal(p.calls[0][1].operation, 'forget');
  assert.equal(p.window.__foorsaBiometrics.protect('first'), false);
});

test('media bearer tokens are session-only after opt-in and cleared on a new launch', () => {
  const MEDIA = 'foorsa_portal_media_token';
  const local = new Map([[TOKEN, 'student'], [MEDIA, 'media-credential']]);
  const tab = new Map();
  const p = portal({local, tab});
  p.window.__foorsaBiometrics.protect('student');
  assert.equal(local.has(MEDIA), false);
  assert.equal(p.storage.getItem(MEDIA), 'media-credential');
  p.storage.setItem(MEDIA, 'renewed-media');
  assert.equal(local.has(MEDIA), false);
  const next = portal({local, tab, config: {boot: 'boot-2'}});
  assert.equal(next.storage.getItem(MEDIA), null);
});

// ── 1.2.21: the sign-in screen and Profile › Settings drive quick sign-in ──

test('the bridge asks the shell for its nonce once the platform is ready', () => {
  const p = portal();
  p.listeners.get('flutterInAppWebViewPlatformReady')();
  assert.deepEqual(plain(p.other.map((call) => call[0])), ['FoorsaShellScannerSession']);
});

test('status waits for the main-frame nonce, then names what the phone uses', async () => {
  const p = portal({config: {protected: true}});
  p.native(async (data) => data.operation === 'status' ? {available: true, enabled: true, kind: 'face'} : null);
  const pending = p.window.__foorsaBiometrics.status();
  await Promise.resolve();
  assert.equal(p.calls.length, 0);
  p.ready();
  const status = await pending;
  assert.equal(status.available, true);
  assert.equal(status.enabled, true);
  assert.equal(status.kind, 'face');
  assert.equal(p.calls[0][1].nonce, 'main-frame-nonce');
});

test('unlocking installs the saved session for this launch only, with nothing more to offer', async () => {
  const local = new Map([[MARKER, '1']]); const tab = new Map();
  const p = portal({local, tab, config: {protected: true}}); p.ready();
  p.native(async (data) => data.operation === 'unlock' ? {ok: true, token: 'saved'} : null);
  assert.equal(p.storage.getItem(TOKEN), null);
  const result = await p.window.__foorsaBiometrics.unlock();
  assert.equal(result.ok, true);
  assert.equal(result.token, undefined);
  assert.equal(p.storage.getItem(TOKEN), 'saved');
  assert.equal(local.has(TOKEN), false);
  assert.equal(p.storage.getItem(KIND), 'student');
  await p.me('saved');
  assert.deepEqual(plain(p.calls.map((call) => call[1].operation)), ['unlock']);
  const nextLaunch = portal({local, tab, config: {protected: true, boot: 'boot-2'}});
  assert.equal(nextLaunch.storage.getItem(TOKEN), null);
});

test('a refused unlock leaves the sign-in screen as it was and says why', async () => {
  const p = portal({config: {protected: true}}); p.ready();
  p.native(async () => ({ok: false, reason: 'cancelled'}));
  assert.deepEqual(plain(await p.window.__foorsaBiometrics.unlock()), {ok: false, reason: 'cancelled'});
  assert.equal(p.storage.getItem(TOKEN), null);
  p.native(async () => null);
  assert.deepEqual(plain(await p.window.__foorsaBiometrics.unlock()), {ok: false, reason: 'unavailable'});
});

test('the prompt opens only from a tap, never by itself', async () => {
  // The owner, 30 Oct 2026: "you need to click the face id logo".
  const tab = new Map();
  const p = portal({tab, config: {protected: true}}); p.ready();
  p.native(async () => ({ok: false, reason: 'cancelled'}));
  assert.equal((await p.window.__foorsaBiometrics.unlock({auto: true})).reason, 'skipped');
  assert.equal(p.calls.length, 0);
  assert.equal((await p.window.__foorsaBiometrics.unlock()).reason, 'cancelled');
  assert.equal((await p.window.__foorsaBiometrics.unlock()).reason, 'cancelled');
  assert.equal(p.calls.length, 2);
  const relaunch = portal({tab, config: {protected: true, boot: 'boot-2'}}); relaunch.ready();
  relaunch.native(async () => ({ok: false, reason: 'cancelled'}));
  assert.equal((await relaunch.window.__foorsaBiometrics.unlock({auto: true})).reason, 'skipped');
  assert.equal(relaunch.calls.length, 0);
});

test('Settings turns it on for the open session and off without signing the student out', async () => {
  const local = new Map([[TOKEN, 'student'], [KIND, 'student']]); const tab = new Map();
  const p = portal({local, tab}); p.ready();
  p.native(async (data) => {
    if (data.operation === 'enable') { p.window.__foorsaBiometrics.protect(data.token); return {ok: true}; }
    if (data.operation === 'disable') return {ok: true};
    return null;
  });
  assert.deepEqual(plain(await p.window.__foorsaBiometrics.enable()), {ok: true});
  assert.equal(p.calls[0][1].token, 'student');
  assert.equal(local.has(TOKEN), false);
  assert.equal(local.get(MARKER), '1');
  assert.deepEqual(plain(await p.window.__foorsaBiometrics.disable()), {ok: true});
  assert.equal(local.get(TOKEN), 'student');
  assert.equal(local.has(MARKER), false);
  const relaunch = portal({local, tab, config: {boot: 'boot-2'}});
  assert.equal(relaunch.storage.getItem(TOKEN), 'student');
});

test('Settings cannot turn it on for an ambassador or without a session', async () => {
  const agent = portal({local: new Map([[TOKEN, 'agent'], [KIND, 'agent']])}); agent.ready();
  assert.equal((await agent.window.__foorsaBiometrics.enable()).ok, false);
  const nobody = portal(); nobody.ready();
  assert.equal((await nobody.window.__foorsaBiometrics.enable()).ok, false);
  assert.equal(agent.calls.length + nobody.calls.length, 0);
});

test('signing out keeps quick sign-in for the sign-in screen; an expired session or a deletion forgets it', () => {
  const local = new Map([[MARKER, '1']]);
  const p = portal({local, tab: new Map(), config: {protected: true, token: 'unlocked'}}); p.ready();
  p.signOut();
  assert.equal(p.calls.length, 0);
  assert.equal(p.storage.getItem(TOKEN), null);
  assert.equal(local.get(MARKER), '1');
  p.signOut({signedOut: true, forgetDevice: true});
  assert.deepEqual(plain(p.calls.map((call) => call[1].operation)), ['forget']);
  assert.equal(local.has(MARKER), false);
  const expired = portal({local: new Map([[MARKER, '1']]), config: {protected: true}}); expired.ready();
  expired.logout();
  assert.deepEqual(plain(expired.calls.map((call) => call[1].operation)), ['forget']);
});
