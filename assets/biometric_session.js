// Installed at document start, only in the configured HTTPS top-level portal.
// FOORSA_CONFIG is supplied by the native shell, never by a frame/message.
(() => {
  const config = FOORSA_CONFIG;
  if (window !== window.top || location.origin !== config.origin) return;
  const tokenKey = 'foorsa_portal_token';
  const kindKey = 'foorsa_portal_kind';
  const protectedKey = 'foorsa_biometric_session';
  const bootKey = 'foorsa_biometric_boot';
  const rawGet = Storage.prototype.getItem;
  const rawSet = Storage.prototype.setItem;
  const rawRemove = Storage.prototype.removeItem;
  let protectedSession = config.protected || rawGet.call(localStorage, protectedKey) === '1';
  let generation = 0;
  let nonce = null;
  let pendingSession = null;
  let pendingLogout = false;
  let blocked = false;
  let announced = null;

  if (protectedSession) {
    rawRemove.call(localStorage, tokenKey);
    if (rawGet.call(sessionStorage, bootKey) !== config.boot) {
      rawRemove.call(sessionStorage, tokenKey);
      rawSet.call(sessionStorage, bootKey, config.boot);
      if (config.token) {
        rawSet.call(sessionStorage, tokenKey, config.token);
        rawSet.call(localStorage, kindKey, 'student');
      }
    }
  }

  // Keep the active web session in tab storage. The durable login lives only
  // in the native vault. Every new native launch clears this tab session before
  // React can read it, then installs only the session the user unlocked.
  Storage.prototype.getItem = function(key) {
    if (this === localStorage && key === tokenKey && protectedSession) {
      return rawGet.call(sessionStorage, key);
    }
    return rawGet.call(this, key);
  };
  Storage.prototype.setItem = function(key, value) {
    if (this === localStorage && key === tokenKey) {
      generation++;
      announced = null;
      if (protectedSession) return rawSet.call(sessionStorage, key, value);
    }
    return rawSet.call(this, key, value);
  };
  Storage.prototype.removeItem = function(key) {
    if (this === localStorage && key === tokenKey) {
      generation++;
      pendingSession = null;
      announced = null;
      rawRemove.call(sessionStorage, key);
    }
    return rawRemove.call(this, key);
  };

  const send = (operation, token) => {
    if (!nonce || !window.flutter_inappwebview?.callHandler) return;
    return window.flutter_inappwebview.callHandler('FoorsaStudentBiometrics', {
      operation, token, nonce,
    });
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
      Promise.resolve(send('session', pendingSession)).catch(() => { announced = null; });
    }
  };
  window.addEventListener('portal-logout', () => {
    generation++;
    pendingSession = null;
    pendingLogout = true;
    rawRemove.call(localStorage, tokenKey);
    rawRemove.call(sessionStorage, tokenKey);
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

  Object.defineProperty(window, '__foorsaBiometrics', {value: {
    ready(value) { nonce = value; flush(); },
    matches(token) { return token === localStorage.getItem(tokenKey) && !blocked; },
    protect(token) {
      if (token !== localStorage.getItem(tokenKey) || blocked) return false;
      rawSet.call(sessionStorage, tokenKey, token);
      rawSet.call(sessionStorage, bootKey, config.boot);
      rawSet.call(localStorage, protectedKey, '1');
      rawRemove.call(localStorage, tokenKey);
      protectedSession = true;
      return true;
    },
  }, configurable: false});
})();
