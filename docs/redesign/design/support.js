// Minimal local stand-in for the design-canvas runtime, used only to film the pages.
(function () {
  class DCLogic {
    constructor(props) { this.props = props || {}; this.state = {}; }
    setState(p) { Object.assign(this.state, typeof p === 'function' ? p(this.state) : p); schedule(); }
    renderVals() { return {}; }
  }
  window.DCLogic = DCLogic;
  const defs = {};
  const insts = {};
  let root, rootDef, pending = false; const pendingMount = [];

  function compile(doc, name) {
    const x = doc.querySelector('x-dc');
    const helmet = x.querySelector('helmet');
    if (helmet) { [...helmet.children].forEach((c) => document.head.appendChild(document.importNode(c, true))); helmet.remove(); }
    const sc = doc.querySelector('script[data-dc-script]');
    const Comp = new Function('DCLogic', sc.textContent + '\n;return Component;')(DCLogic);
    if (x.parentNode) x.remove();
    return { tpl: x, Comp, name };
  }
  function load(name) {
    if (defs[name]) return defs[name];
    const r = new XMLHttpRequest(); r.open('GET', './' + name + '.dc.html', false); r.send();
    const doc = new DOMParser().parseFromString(r.responseText, 'text/html');
    return (defs[name] = compile(doc, name));
  }
  function look(scope, expr) {
    expr = expr.trim();
    if (expr === 'true') return true; if (expr === 'false') return false;
    let v = scope;
    for (const k of expr.split('.')) { if (v == null) return undefined; v = v[k]; }
    return v;
  }
  const HOLE = /\{\{\s*([^}]+?)\s*\}\}/g;
  const single = (s) => { const m = s.match(/^\s*\{\{\s*([^}]+?)\s*\}\}\s*$/); return m && m[1]; };
  const interp = (s, scope) => s.replace(HOLE, (_, e) => { const v = look(scope, e); return v == null ? '' : String(v); });

  function renderInto(def, inst, out, key) {
    const vals = inst.renderVals();
    for (const c of def.tpl.childNodes) node(c, vals, out, key);
  }
  function node(n, scope, out, key) {
    if (n.nodeType === 3) { out.appendChild(document.createTextNode(interp(n.nodeValue, scope))); return; }
    if (n.nodeType !== 1) return;
    const tag = n.localName;
    if (tag === 'sc-for') {
      const list = look(scope, single(n.getAttribute('list')) || '') || [];
      const as = n.getAttribute('as');
      list.forEach((item, i) => { const s2 = Object.create(scope); s2[as] = item; for (const c of n.childNodes) node(c, s2, out, key + '.' + i); });
      return;
    }
    if (tag === 'sc-if') {
      const e = single(n.getAttribute('value') || '');
      if (look(scope, e || 'false')) for (const c of n.childNodes) node(c, scope, out, key);
      return;
    }
    if (tag === 'dc-import') {
      const name = n.getAttribute('name');
      const props = {};
      for (const a of n.attributes) if (a.name !== 'name' && !a.name.startsWith('hint-')) props[a.name] = interp(a.value, scope);
      const def = load(name);
      const k = key + '>' + name + ':' + out.childNodes.length;
      let inst = insts[k];
      if (!inst) { inst = insts[k] = new def.Comp(props); pendingMount.push(inst); }
      inst.props = props;
      const wrap = document.createElement('div'); wrap.style.cssText = 'width:100%;height:100%';
      renderInto(def, inst, wrap, k);
      out.appendChild(wrap);
      return;
    }
    const el = document.createElementNS(n.namespaceURI, n.localName);
    for (const a of n.attributes) {
      if (/^on[a-z]+$/i.test(a.name)) {
        const e = single(a.value); const fn = e && look(scope, e);
        if (typeof fn === 'function') { el.__h = el.__h || {}; el.__h[a.name.slice(2).toLowerCase()] = fn; }
        continue;
      }
      try { el.setAttribute(a.name, interp(a.value, scope)); } catch (_) {}
    }
    for (const c of n.childNodes) node(c, scope, el, key);
    out.appendChild(el);
  }
  function morph(a, b) {
    if (a.nodeType === 1) {
      for (const at of [...a.attributes]) if (!b.hasAttribute(at.name)) a.removeAttribute(at.name);
      for (const at of b.attributes) if (a.getAttribute(at.name) !== at.value) a.setAttribute(at.name, at.value);
      a.__h = b.__h;
    }
    const ac = [...a.childNodes], bc = [...b.childNodes];
    for (let i = 0; i < bc.length; i++) {
      const x = ac[i], y = bc[i];
      if (!x) { a.appendChild(y); continue; }
      if (x.nodeType !== y.nodeType || (x.nodeType === 1 && x.tagName !== y.tagName)) { a.replaceChild(y, x); continue; }
      if (x.nodeType === 3) { if (x.nodeValue !== y.nodeValue) x.nodeValue = y.nodeValue; continue; }
      morph(x, y);
    }
    for (let i = bc.length; i < ac.length; i++) ac[i].remove();
  }
  function draw() {
    pending = false;
    const fresh = document.createElement('div');
    renderInto(rootDef, insts.root, fresh, 'root');
    morph(root, fresh);
    while (pendingMount.length) { const i = pendingMount.shift(); if (!i.__mounted && i.componentDidMount) { i.__mounted = 1; setTimeout(() => i.componentDidMount(), 0); } }
  }
  function schedule() { if (!pending) { pending = true; queueMicrotask(draw); } }
  ['click', 'input', 'change'].forEach((t) => document.addEventListener(t, (e) => {
    let n = e.target;
    while (n && n !== document) {
      if (n.__h && n.__h[t]) { if (t === 'click' && n.tagName === 'A') e.preventDefault(); n.__h[t](e); return; }
      if (t === 'click' && n.tagName === 'A' && n.getAttribute('href') === '#') { e.preventDefault(); }
      n = n.parentNode;
    }
  }, true));
  document.addEventListener('DOMContentLoaded', () => {
    rootDef = compile(document, 'root');
    const props = Object.fromEntries(new URLSearchParams(location.search));
    insts.root = new rootDef.Comp(props); pendingMount.push(insts.root);
    root = document.createElement('div'); root.id = 'dc-root';
    document.body.appendChild(root);
    draw();
    window.__dc = { inst: insts.root, set: (p) => insts.root.setState(p) };
    document.documentElement.dataset.ready = '1';
  });
})();
