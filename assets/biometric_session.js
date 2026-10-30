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
  let protectedSession = config.protected || rawGet.call(localStorage, protectedKey) === '1';
  let generation = 0;
  let nonce = null;
  let readyWaiters = [];
  let pendingSession = null;
  let pendingLogout = false;
  let blocked = false;
  let announced = null;

  if (protectedSession) {
    for (const key of credentialKeys) rawRemove.call(localStorage, key);
    if (rawGet.call(sessionStorage, bootKey) !== config.boot) {
      for (const key of credentialKeys) rawRemove.call(sessionStorage, key);
      rawSet.call(sessionStorage, bootKey, config.boot);
      if (config.token) {
        rawSet.call(sessionStorage, tokenKey, config.token);
        rawSet.call(localStorage, kindKey, 'student');
      }
    }
  }
  // Do not retain a second copy inside the bridge's closures after bootstrap.
  config.token = null;

  // Keep the active web session in tab storage. The durable login lives only
  // in the native vault. Every new native launch clears this tab session before
  // React can read it, so the portal opens on its sign-in screen, where the
  // student unlocks with Face ID or a fingerprint (or types their password).
  Storage.prototype.getItem = function(key) {
    if (this === localStorage && credentialKeys.has(key) && protectedSession) {
      return rawGet.call(sessionStorage, key);
    }
    return rawGet.call(this, key);
  };
  Storage.prototype.setItem = function(key, value) {
    if (this === localStorage && key === tokenKey) {
      generation++;
      announced = null;
    }
    if (this === localStorage && credentialKeys.has(key) && protectedSession) return rawSet.call(sessionStorage, key, value);
    return rawSet.call(this, key, value);
  };
  Storage.prototype.removeItem = function(key) {
    if (this === localStorage && key === tokenKey) {
      generation++;
      pendingSession = null;
      announced = null;
    }
    if (this === localStorage && credentialKeys.has(key)) rawRemove.call(sessionStorage, key);
    return rawRemove.call(this, key);
  };

  const send = (operation, token) => {
    if (!nonce || !window.flutter_inappwebview?.callHandler) return;
    return window.flutter_inappwebview.callHandler('FoorsaStudentBiometrics', {
      operation, token, nonce,
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

  // Quick sign-in is off: the session goes back to ordinary, lasting storage.
  const unprotect = () => {
    for (const key of credentialKeys) {
      const value = rawGet.call(sessionStorage, key);
      if (value) rawSet.call(localStorage, key, value);
    }
    rawRemove.call(localStorage, protectedKey);
    protectedSession = false;
  };

  const flush = () => {
    if (pendingLogout) {
      if (!nonce) return;
      pendingLogout = false;
      Promise.resolve(send('forget')).catch(() => {});
    }
    if (pendingSession && !blocked && pendingSession === localStorage.getItem(tokenKey)
        && localStorage.getItem(kindKey) !== 'agent' && pendingSession !== announced && nonce) {
      announced = pendingSession;
      Promise.resolve(send('session', pendingSession)).then((result) => {
        if (result?.retry) { announced = null; setTimeout(flush, 750); }
      }).catch(() => { announced = null; });
    }
  };
  window.addEventListener('portal-logout', (event) => {
    generation++;
    pendingSession = null;
    // Signing out keeps quick sign-in: it waits on the sign-in screen for the
    // next time. An expired or rejected session, or a deleted account, takes
    // it away, and the session goes back to ordinary storage.
    const detail = event && event.detail;
    const keepQuickSignIn = !!detail && detail.signedOut === true && detail.forgetDevice !== true;
    for (const key of credentialKeys) {
      rawRemove.call(localStorage, key);
      rawRemove.call(sessionStorage, key);
    }
    if (!keepQuickSignIn) {
      pendingLogout = true;
      rawRemove.call(localStorage, protectedKey);
      protectedSession = false;
    }
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
    protect(token) {
      if (token !== localStorage.getItem(tokenKey) || blocked) return false;
      rawSet.call(sessionStorage, tokenKey, token);
      const media = rawGet.call(localStorage, mediaKey);
      if (media) rawSet.call(sessionStorage, mediaKey, media);
      rawSet.call(sessionStorage, bootKey, config.boot);
      rawSet.call(localStorage, protectedKey, '1');
      for (const key of credentialKeys) rawRemove.call(localStorage, key);
      protectedSession = true;
      return true;
    },
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
    // The OS prompt opens; on success the saved session becomes this tab's
    // session and the portal carries on as if the password had been typed.
    // Only from a tap on the sign-in screen's icon (the owner, 30 Oct 2026:
    // "you need to click the face id logo"): `auto`, the screen opening the
    // prompt by itself, is refused, whatever release of the portal asks.
    async unlock(options) {
      if (options && options.auto) return {ok: false, reason: 'skipped'};
      const result = await call('unlock');
      if (!result || result.ok !== true || typeof result.token !== 'string' || !result.token) {
        return {ok: false, reason: reasonOf(result)};
      }
      for (const key of credentialKeys) rawRemove.call(localStorage, key);
      rawRemove.call(sessionStorage, mediaKey);
      rawSet.call(sessionStorage, tokenKey, result.token);
      rawSet.call(sessionStorage, bootKey, config.boot);
      rawSet.call(localStorage, kindKey, 'student');
      rawSet.call(localStorage, protectedKey, '1');
      protectedSession = true;
      blocked = false;
      generation++;
      // Already saved: there is nothing to offer for this session.
      announced = result.token;
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
      unprotect();
      return {ok: true};
    },
  }), configurable: false});
})();
