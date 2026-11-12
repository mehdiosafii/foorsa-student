// The two scripts Android's back button runs in the page (lib/src/web_back.dart),
// against a page with layers as the portal makes them: a layer is an element
// that answers the Escape key on the document, the topmost first.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

const dart = fs.readFileSync('lib/src/web_back.dart', 'utf8');
const script = (name) => {
  const match = dart.match(new RegExp(`const ${name} = r"""([\\s\\S]*?)""";`));
  assert.ok(match, `${name} is in web_back.dart`);
  return match[1];
};
const ASK = script('webLayerAsk');
const ANSWERED = script('webLayerAnswered');

/** A page: `layers` are on screen from first (under) to last (on top). */
function page() {
  const listeners = [];
  const layers = [];
  const pressed = [];
  const document = {
    activeElement: null,
    addEventListener: (name, handler) => { if (name === 'keydown') listeners.push(handler); },
    querySelectorAll: () => layers.filter((l) => l.isConnected),
  };
  class KeyboardEvent {
    constructor(type, init) { Object.assign(this, {type, defaultPrevented: false}, init); }
    preventDefault() { this.defaultPrevented = true; }
  }
  const element = ({shown = true, inert = false} = {}) => ({
    isConnected: true, shown, inert, children: [],
    getBoundingClientRect() { return this.shown ? {width: 390, height: 600} : {width: 0, height: 0}; },
    closest(selector) { return selector === '[inert]' && this.inert ? this : null; },
    contains(other) { return other === this || this.children.includes(other); },
    dispatchEvent(event) { pressed.push(this); for (const handler of [...listeners]) handler(event); return !event.defaultPrevented; },
  });
  class Event {
    constructor(type, init) { Object.assign(this, {type, defaultPrevented: false}, init); }
    preventDefault() { if (this.cancelable) this.defaultPrevented = true; }
  }
  /** A native dialog: deaf to a scripted key, told by `cancel`, closed by `close()`. */
  const dialog = ({onCancel = null} = {}) => {
    const el = element();
    Object.assign(el, {tagName: 'DIALOG', open: true, cancels: 0,
      close() { this.open = false; this.shown = false; },
      dispatchEvent(event) {
        pressed.push(this);
        if (event.type === 'cancel') { this.cancels += 1; if (onCancel) onCancel(event, this); return !event.defaultPrevented; }
        for (const handler of [...listeners]) handler(event);
        return !event.defaultPrevented;
      }});
    layers.push(el);
    return el;
  };
  const context = vm.createContext({document, KeyboardEvent, Event, window: {}});
  context.window = context;
  const run = (source) => vm.runInContext(source, context);
  /** Opens a layer as the portal's SheetLayer does: only the topmost answers Escape, by closing. */
  const open = ({locked = false, asks = false, ...rest} = {}) => {
    const layer = element(rest);
    layers.push(layer);
    listeners.push((event) => {
      const top = layers.filter((l) => l.isConnected).slice(-1)[0];
      if (event.key !== 'Escape' || top !== layer) return;
      event.preventDefault();
      if (locked) return;
      if (asks) { open(); return; } // "Leave without sending?" over it
      layer.isConnected = false;
    });
    return layer;
  };
  return {run, open, dialog, element, document, layers, pressed, context};
}

test('nothing open: the page is not asked anything', () => {
  const p = page();
  assert.equal(p.run(ASK), 'none');
  assert.equal(p.pressed.length, 0);
  assert.equal(p.run(ANSWERED), true, 'nothing is kept, so nothing is waited for');
});

test('one sheet: Escape goes to it and it is gone at the next look', () => {
  const p = page();
  const sheet = p.open();
  assert.equal(p.run(ASK), 'asked');
  assert.deepEqual(p.pressed, [sheet]);
  assert.equal(sheet.isConnected, false);
  assert.equal(p.run(ANSWERED), true);
  assert.equal(p.run(ASK), 'none', 'the next back is the history\'s');
});

test('two layers: only the one on top closes', () => {
  const p = page();
  const under = p.open();
  const top = p.open();
  assert.equal(p.run(ASK), 'asked');
  assert.equal(top.isConnected, false);
  assert.equal(under.isConnected, true);
  assert.equal(p.run(ANSWERED), true);
  assert.equal(p.run(ASK), 'asked', 'a second back closes the one under it');
  assert.equal(under.isConnected, false);
});

test('the key is pressed where the focus is, inside the layer', () => {
  const p = page();
  const sheet = p.open();
  const field = p.element();
  sheet.children.push(field);
  p.document.activeElement = field;
  assert.equal(p.run(ASK), 'asked');
  assert.deepEqual(p.pressed, [field]);
  // Focus left on the page under the sheet is not where the key goes.
  const q = page();
  const other = q.open();
  q.document.activeElement = q.element();
  q.run(ASK);
  assert.deepEqual(q.pressed, [other]);
});

test('a locked layer does not answer: back stays the shell\'s', () => {
  const p = page();
  const gate = p.open({locked: true});
  assert.equal(p.run(ASK), 'asked');
  assert.equal(gate.isConnected, true);
  assert.equal(p.run(ANSWERED), false);
  assert.equal(p.run(ANSWERED), false, 'it is asked again, and still has not');
});

test('a layer that answers with a question of its own has answered', () => {
  const p = page();
  const recorder = p.open({asks: true});
  assert.equal(p.run(ASK), 'asked');
  assert.equal(recorder.isConnected, true);
  assert.equal(p.layers.length, 2);
  assert.equal(p.run(ANSWERED), true, 'another layer is over it now');
});

test('what is not on screen is not a layer', () => {
  const p = page();
  p.open({shown: false});
  p.open({inert: true}); // the copy a closing sheet leaves, or a layer under another
  assert.equal(p.run(ASK), 'none');
});

test('a page that breaks under the scripts reads as nothing open', () => {
  const p = page();
  p.document.querySelectorAll = () => { throw new Error('no document'); };
  assert.equal(p.run(ASK), 'none');
  assert.equal(p.run(ANSWERED), true);
});

test('a native dialog is told by cancel, and one that takes it has taken the press', () => {
  // The portal's dialogs answer cancel themselves (preventDefault, then they close when ready).
  const p = page();
  const reveal = p.dialog({onCancel: (event) => event.preventDefault()});
  assert.equal(p.run(ASK), 'taken');
  assert.equal(reveal.cancels, 1);
  assert.equal(reveal.open, true, 'it closes itself, in its own time');
  assert.equal(p.run(ANSWERED), true);
});

test('a native dialog that does not answer cancel is closed as the browser would', () => {
  const p = page();
  const plain = p.dialog();
  assert.equal(p.run(ASK), 'asked');
  assert.equal(plain.open, false);
  assert.equal(p.run(ANSWERED), true, 'a closed dialog is not on screen');
});

test('a sheet over a dialog closes first, and the dialog is left alone', () => {
  const p = page();
  const dialog = p.dialog({onCancel: (event) => event.preventDefault()});
  const sheet = p.open();
  assert.equal(p.run(ASK), 'asked');
  assert.equal(sheet.isConnected, false);
  assert.equal(dialog.cancels, 0);
  assert.equal(dialog.open, true);
});
