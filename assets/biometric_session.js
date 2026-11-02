// Installed at document start, only in the configured HTTPS top-level portal.
// FOORSA_CONFIG is supplied by the native shell, never by a frame/message.
(() => {
  const config = FOORSA_CONFIG;
  if (window !== window.top || location.origin !== config.origin) return;
  const tokenKey = 'foorsa_portal_token';
  const mediaKey = 'foorsa_portal_media_token';
  const credentialKeys = new Set([tokenKey, mediaKey]);
  const kindKey = 'foorsa_portal_kind';
  const protectedKey = 'foorsa_biometric_session';
  const bootKey = 'foorsa_biometric_boot';
  const rawGet = Storage.prototype.getItem;
  const rawSet = Storage.prototype.setItem;
  const rawRemove = Storage.prototype.removeItem;
  let generation = 0;
  let nonce = null;
  let readyWaiters = [];
  let pendingSession = null;
  let pendingLogout = false;
  let blocked = false;
  let announced = null;
  let renewing = null;
  // The session the portal stored on this page (a sign-in), as opposed to one
  // the app kept from an earlier launch: the shell replaces a saved quick
  // sign-in only for a new sign-in or another account.
  let startedHere = null;

  // The student stays signed in when the app closes (the owner, 1 Nov 2026: "once you log to the
  // app, even if the app closes let's make sure you stay signed in"). Until 1.2.39 the session
  // lived in this tab only while quick sign-in was on, and every launch opened on the sign-in
  // screen. Its marker, and a tab copy a reload kept, go back to ordinary lasting storage; the
  // saved login behind Face ID or the fingerprint stays, for signing back in after a sign-out.
  if (rawGet.call(localStorage, protectedKey) === '1') {
    for (const key of credentialKeys) {
      const value = rawGet.call(sessionStorage, key);
      if (value && !rawGet.call(localStorage, key)) rawSet.call(localStorage, key, value);
      rawRemove.call(sessionStorage, key);
    }
    rawRemove.call(localStorage, protectedKey);
    rawRemove.call(sessionStorage, bootKey);
  }
  // Do not retain a second copy inside the bridge's closures after bootstrap.
  config.token = null;

  Storage.prototype.setItem = function(key, value) {
    if (this === localStorage && key === tokenKey) {
      generation++;
      // A session the portal renewed (portal-session-renewed, below) is the same sign-in, not a
      // new one: there is nothing to offer for it.
      const renewal = renewing !== null && String(value) === renewing;
      announced = renewal ? renewing : null;
      startedHere = renewal ? null : String(value);
      renewing = null;
    }
    return rawSet.call(this, key, value);
  };
  Storage.prototype.removeItem = function(key) {
    if (this === localStorage && key === tokenKey) {
      generation++;
      pendingSession = null;
      announced = null;
      startedHere = null;
    }
    return rawRemove.call(this, key);
  };

  const send = (operation, token, extra) => {
    if (!nonce || !window.flutter_inappwebview?.callHandler) return;
    return window.flutter_inappwebview.callHandler('FoorsaStudentBiometrics', {
      ...extra, operation, token, nonce,
    });
  };
  // The shell hands this page its nonce on every load and whenever asked. A
  // call made before then (the sign-in screen asking whether Face ID is set
  // up) waits for it rather than being dropped.
  const whenReady = () => nonce ? Promise.resolve(true) : new Promise((resolve) => {
    const done = () => { clearTimeout(timer); resolve(true); };
    const timer = setTimeout(() => {
      readyWaiters = readyWaiters.filter((waiter) => waiter !== done);
      resolve(false);
    }, 6000);
    readyWaiters.push(done);
  });
  const call = async (operation, token) => {
    if (!(await whenReady())) return null;
    try {
      const result = await send(operation, token);
      return result && typeof result === 'object' ? result : null;
    } catch (_) {
      return null;
    }
  };
  const reasonOf = (result) => (result && typeof result.reason === 'string' ? result.reason : 'unavailable');
  const requestReady = () => {
    try { window.flutter_inappwebview?.callHandler?.('FoorsaShellScannerSession'); } catch (_) { /* the load hands it over */ }
  };
  window.addEventListener('flutterInAppWebViewPlatformReady', requestReady);

  const flush = () => {
    if (pendingLogout) {
      if (!nonce) return;
      pendingLogout = false;
      Promise.resolve(send('forget')).catch(() => {});
    }
    if (pendingSession && !blocked && pendingSession === localStorage.getItem(tokenKey)
        && localStorage.getItem(kindKey) !== 'agent' && pendingSession !== announced && nonce) {
      announced = pendingSession;
      Promise.resolve(send('session', pendingSession, {fresh: pendingSession === startedHere})).then((result) => {
        if (result?.retry) { announced = null; setTimeout(flush, 750); }
      }).catch(() => { announced = null; });
    }
  };
  // The portal says a session it is about to keep is a renewal of the open one
  // (src/portal/sessionRenewal.ts), just before it stores it.
  window.addEventListener('portal-session-renewed', (event) => {
    const token = event && event.detail && event.detail.token;
    renewing = typeof token === 'string' && token ? token : null;
  });
  window.addEventListener('portal-logout', (event) => {
    generation++;
    pendingSession = null;
    startedHere = null;
    // Signing out keeps quick sign-in: it waits on the sign-in screen for the
    // next time. An expired or rejected session, or a deleted account, takes
    // it away.
    const detail = event && event.detail;
    const keepQuickSignIn = !!detail && detail.signedOut === true && detail.forgetDevice !== true;
    for (const key of credentialKeys) {
      rawRemove.call(localStorage, key);
      rawRemove.call(sessionStorage, key);
    }
    if (!keepQuickSignIn) pendingLogout = true;
    flush();
  });

  // Observe successful authoritative session probes, not DOM text, passwords,
  // URL changes, or merely the presence of an unverified token.
  const originalFetch = window.fetch.bind(window);
  window.fetch = async (...args) => {
    const before = generation;
    const response = await originalFetch(...args);
    try {
      const request = args[0];
      const url = new URL(typeof request === 'string' || request instanceof URL ? request : request.url, location.href);
      if (url.origin !== config.origin) return response;
      if (url.pathname === '/api/portal/login' && response.ok) {
        const body = await response.clone().json();
        blocked = body.mustChangePassword === true || body.kind === 'agent';
      }
      if (url.pathname === '/api/portal/change-password' && response.ok) blocked = false;
      if (url.pathname === '/api/portal/me' && response.ok && before === generation) {
        const headers = new Headers(args[1]?.headers || (request instanceof Request ? request.headers : {}));
        const bearer = headers.get('Authorization');
        const token = localStorage.getItem(tokenKey);
        if (token && bearer === `Bearer ${token}`) { pendingSession = token; flush(); }
      }
    } catch (_) { /* The portal retains its normal fetch/error behavior. */ }
    return response;
  };

  Object.defineProperty(window, '__foorsaBiometrics', {value: Object.freeze({
    ready(value) {
      nonce = value;
      const waiters = readyWaiters;
      readyWaiters = [];
      for (const waiter of waiters) waiter();
      flush();
    },
    matches(token) { return token === localStorage.getItem(tokenKey) && !blocked; },
    // Builds before 1.2.39 moved the session into the tab here, so the next
    // launch opened on the sign-in screen. The session now stays where it is:
    // the saved login is for after a sign-out. True while the token is still
    // the page's session, which the shell checks before keeping the login.
    protect(token) { return token === localStorage.getItem(tokenKey) && !blocked; },
    // ── For the portal's sign-in screen and Profile › Settings ──────────
    // Whether this phone can do it and whether a sign-in is saved. `kind`
    // names what the phone uses: face, touch or (Android) biometric.
    async status() {
      const result = await call('status');
      if (!result) return null;
      return {
        available: result.available === true,
        enabled: result.enabled === true,
        kind: result.kind === 'face' || result.kind === 'touch' ? result.kind : 'biometric',
      };
    },
    // The OS prompt opens; on success the saved session becomes the page's
    // session, kept across launches, and the portal carries on as if the
    // password had been typed. Only from a tap on the sign-in screen's icon
    // (the owner, 30 Oct 2026: "you need to click the face id logo"): `auto`,
    // the screen opening the prompt by itself, is refused, whatever release of
    // the portal asks.
    async unlock(options) {
      if (options && options.auto) return {ok: false, reason: 'skipped'};
      const result = await call('unlock');
      if (!result || result.ok !== true || typeof result.token !== 'string' || !result.token) {
        return {ok: false, reason: reasonOf(result)};
      }
      rawRemove.call(localStorage, mediaKey);
      rawRemove.call(sessionStorage, mediaKey);
      rawSet.call(localStorage, tokenKey, result.token);
      rawSet.call(localStorage, kindKey, 'student');
      blocked = false;
      generation++;
      // Already saved: there is nothing to offer for this session.
      announced = result.token;
      startedHere = null;
      return {ok: true};
    },
    // Turned on from Profile › Settings, for the session open now.
    async enable() {
      const token = localStorage.getItem(tokenKey);
      if (!token || blocked || localStorage.getItem(kindKey) === 'agent') return {ok: false, reason: 'unavailable'};
      const result = await call('enable', token);
      return result && result.ok === true ? {ok: true} : {ok: false, reason: reasonOf(result)};
    },
    // Turned off: the saved sign-in is deleted and the student stays signed in.
    async disable() {
      const result = await call('disable');
      if (!result || result.ok !== true) return {ok: false, reason: reasonOf(result)};
      return {ok: true};
    },
  }), configurable: false});
})();
