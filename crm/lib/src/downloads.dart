/// Files the CRM hands the person: exports, receipts, PDFs, documents.
///
/// A web view has no download bar. Two kinds of download reach the app:
///
/// - A link to a file (a signed document link, a server export): the app
///   fetches it with the web view's cookies ([fetchDownload]).
/// - A file the page made itself (an Excel export, a PDF drawn in the page):
///   a `blob:` or `data:` link only the page can read. The script below reads
///   it in the page and passes it over the bridge ([saveDataUrl]).
///
/// Either way it is saved in the app's Downloads folder (visible in the Files
/// app on iPhone and iPad) and opened, from where it can be shared or saved
/// elsewhere.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Read in the page before the CRM's own code: it keeps each blob the page
/// makes for a minute (pages often revoke a blob link the moment they have
/// clicked it), and sends blob and data links to the app instead of letting
/// the web view try to open them. `print()` is sent to the app's printer.
const String downloadBridgeScript = r'''
(function () {
  if (window.__foorsaCrmDownloads) return;
  window.__foorsaCrmDownloads = true;
  function bridge(payload) {
    try { return window.flutter_inappwebview.callHandler('FoorsaBridge', payload); }
    catch (e) { return Promise.reject(e); }
  }
  var blobs = new Map();
  var create = URL.createObjectURL, revoke = URL.revokeObjectURL;
  URL.createObjectURL = function (obj) {
    var url = create.call(URL, obj);
    try { if (obj instanceof Blob) blobs.set(url, obj); } catch (e) {}
    return url;
  };
  URL.revokeObjectURL = function (url) {
    setTimeout(function () { blobs.delete(url); try { revoke.call(URL, url); } catch (e) {} }, 60000);
  };
  function blobFor(url) {
    var kept = blobs.get(url);
    if (kept) return Promise.resolve(kept);
    return fetch(url).then(function (r) { return r.blob(); });
  }
  function asDataUrl(blob) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () { resolve(reader.result); };
      reader.onerror = function () { reject(reader.error); };
      reader.readAsDataURL(blob);
    });
  }
  function save(url, name) {
    blobFor(url).then(function (blob) {
      return asDataUrl(blob).then(function (data) {
        return bridge({ action: 'saveFile', name: name || '', mime: blob.type || '', data: data });
      });
    }).catch(function () {});
  }
  function handled(a) {
    if (!a || !a.href || !/^(blob|data):/i.test(a.href)) return false;
    save(a.href, a.getAttribute('download') || '');
    return true;
  }
  var click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (handled(this)) return;
    return click.apply(this, arguments);
  };
  var dispatch = EventTarget.prototype.dispatchEvent;
  EventTarget.prototype.dispatchEvent = function (event) {
    if (event && event.type === 'click' && this instanceof HTMLAnchorElement && handled(this)) return false;
    return dispatch.apply(this, arguments);
  };
  document.addEventListener('click', function (event) {
    var target = event.target;
    var a = target && target.closest ? target.closest('a[href]') : null;
    if (a && handled(a)) { event.preventDefault(); event.stopPropagation(); }
  }, true);
  var open = window.open;
  window.open = function (url) {
    if (typeof url === 'string' && /^(blob|data):/i.test(url)) { save(url, ''); return null; }
    return open.apply(window, arguments);
  };
  window.print = function () { bridge({ action: 'print' }); };
})();
''';

/// The app's Downloads folder, made if needed.
Future<Directory> downloadsFolder() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/Downloads');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// A file name that is safe on the phone, with an extension for [mime] when
/// the page gave none.
String safeFileName(String? name, {String mime = '', String fallback = 'Foorsa file'}) {
  var cleaned = (name ?? '').replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') cleaned = fallback;
  if (cleaned.length > 120) cleaned = cleaned.substring(cleaned.length - 120);
  if (!cleaned.contains('.')) {
    final ext = _extensions[mime.split(';').first.trim().toLowerCase()];
    if (ext != null) cleaned = '$cleaned.$ext';
  }
  return cleaned;
}

const Map<String, String> _extensions = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'text/csv': 'csv',
  'text/plain': 'txt',
  'application/zip': 'zip',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.ms-excel': 'xls',
  'application/msword': 'doc',
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a',
  'video/mp4': 'mp4',
};

/// A path in [dir] for [name] that does not overwrite an earlier file.
Future<File> freshFile(Directory dir, String name) async {
  var file = File('${dir.path}/$name');
  if (!await file.exists()) return file;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var i = 2; i < 1000; i++) {
    file = File('${dir.path}/$stem ($i)$ext');
    if (!await file.exists()) return file;
  }
  return File('${dir.path}/$stem ${DateTime.now().millisecondsSinceEpoch}$ext');
}

/// Saves a `data:` URL the page read from a blob, and opens it.
Future<File?> saveDataUrl(String dataUrl, String? name, String mime) async {
  final comma = dataUrl.indexOf(',');
  if (!dataUrl.startsWith('data:') || comma < 0) return null;
  final header = dataUrl.substring(5, comma);
  final type = mime.isNotEmpty ? mime : header.split(';').first;
  final payload = dataUrl.substring(comma + 1);
  final bytes = header.contains(';base64')
      ? base64.decode(payload)
      : utf8.encode(Uri.decodeComponent(payload));
  final file = await freshFile(await downloadsFolder(), safeFileName(name, mime: type));
  await file.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(file.path);
  return file;
}

/// Fetches a file the web view was asked to download, with its cookies, and
/// opens it.
Future<File?> fetchDownload(DownloadStartRequest request, String userAgent) async {
  final uri = request.url;
  final cookies = await CookieManager.instance().getCookies(url: uri);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    if (cookies.isNotEmpty) {
      req.headers.set(HttpHeaders.cookieHeader, cookies.map((c) => '${c.name}=${c.value}').join('; '));
    }
    final res = await req.close().timeout(const Duration(minutes: 2));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final segs = uri.pathSegments;
    final name = safeFileName(
      request.suggestedFilename ?? (segs.isEmpty ? null : Uri.decodeComponent(segs.last)),
      mime: request.mimeType ?? res.headers.contentType?.mimeType ?? '',
    );
    final file = await freshFile(await downloadsFolder(), name);
    final sink = file.openWrite();
    try {
      await res.timeout(const Duration(minutes: 2)).pipe(sink);
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      return null;
    }
    await OpenFilex.open(file.path);
    return file;
  } finally {
    client.close(force: true);
  }
}
