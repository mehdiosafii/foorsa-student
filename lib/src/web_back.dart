/// Android's back button, when something is open over the portal's screen.
///
/// Through 1.2.40 (71) back was always the web view's own history: with a
/// sheet open (the upload chooser, a paper's help, "Share with parents", a
/// city list, a document being reviewed) it left the *screen* under the sheet
/// and took the sheet with it, and on a screen with nothing behind it the
/// sheet stayed while the app said "Press back again to exit" (the stress
/// test, 11 Nov 2026: every one of the 20 sheets tried in the portal).
///
/// The portal's layers already close on the Escape key, the topmost first
/// (`SheetLayer`), so back is offered to the page as that key. A layer that
/// answers is what back was for. One that does not (the contract to sign is
/// locked on purpose) leaves back as it was: history, then the exit prompt.
library;

import 'dart:async';

/// Finds the topmost layer on screen and presses Escape in it. Answers
/// `'none'` with nothing open, `'asked'` once the key was sent, and `'taken'`
/// when the layer said at once that the press was its own.
///
/// A native `<dialog>` (the calendar's event, a recipe's video, the journey's
/// player, the admission letter) never hears a key a script sends: the browser
/// tells it by a `cancel` event, so that is sent too. Each of the portal's
/// answers it by closing itself, some over a second or two (the letter goes
/// back into its envelope first), so a dialog that takes the `cancel` has
/// taken the press.
///
/// Kept in the page until [webLayerAnswered] reads it: the layer, and how
/// many layers there were, so a layer that closes and one that answers with
/// a question of its own ("Leave without sending?") both count as an answer.
const webLayerAsk = r"""(function () {
  try {
    var all = document.querySelectorAll('[data-sheet-layer], dialog[open], [role="dialog"], [role="alertdialog"]');
    var shown = [];
    for (var i = 0; i < all.length; i++) {
      var box = all[i].getBoundingClientRect();
      if (box.width > 0 && box.height > 0 && !all[i].closest('[inert]')) shown.push(all[i]);
    }
    if (!shown.length) { window.__foorsaBackLayer = null; return 'none'; }
    var top = shown[shown.length - 1];
    window.__foorsaBackLayer = { layer: top, count: shown.length };
    var from = document.activeElement && top.contains(document.activeElement) ? document.activeElement : top;
    var unanswered = from.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true, cancelable: true }));
    if (unanswered && top.tagName === 'DIALOG' && top.open) {
      if (!top.dispatchEvent(new Event('cancel', { cancelable: true }))) { window.__foorsaBackLayer = null; return 'taken'; }
      if (top.open && typeof top.close === 'function') top.close();
    }
    return 'asked';
  } catch (e) { return 'none'; }
})()""";

/// Whether the layer [webLayerAsk] pressed Escape in has answered: it is
/// gone, or the layers on screen are no longer the ones there were.
const webLayerAnswered = r"""(function () {
  try {
    var kept = window.__foorsaBackLayer;
    if (!kept) return true;
    var gone = !kept.layer.isConnected || kept.layer.closest('[inert]') !== null || kept.layer.getBoundingClientRect().width === 0;
    var all = document.querySelectorAll('[data-sheet-layer], dialog[open], [role="dialog"], [role="alertdialog"]');
    var count = 0;
    for (var i = 0; i < all.length; i++) {
      var box = all[i].getBoundingClientRect();
      if (box.width > 0 && box.height > 0 && !all[i].closest('[inert]')) count++;
    }
    if (gone || count !== kept.count) { window.__foorsaBackLayer = null; return true; }
    return false;
  } catch (e) { return true; }
})()""";

/// How long the page has to answer the key: three looks, 120 ms apart. A
/// phone slower than that falls back to what back did before.
const webLayerLook = Duration(milliseconds: 120);
const webLayerLooks = 3;

/// Offers the back press to the page. True when a layer took it (closed, or
/// answered with a question): back is then done. False with nothing open, a
/// layer that does not answer, or a page that cannot be asked.
Future<bool> closeTopWebLayer(
  Future<Object?> Function(String source) evaluate, {
  Duration look = webLayerLook,
  int looks = webLayerLooks,
  Duration patience = const Duration(seconds: 1),
}) async {
  try {
    final asked = await evaluate(webLayerAsk).timeout(patience);
    if (asked == 'taken') return true;
    if (asked != 'asked') return false;
    for (var i = 0; i < looks; i++) {
      await Future<void>.delayed(look);
      if (await evaluate(webLayerAnswered).timeout(patience) == true) return true;
    }
  } catch (_) {
    // A page that cannot be asked (still loading, gone): back as before.
  }
  return false;
}
