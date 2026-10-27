(() => {
  const HIDDEN = new Set(["microsoft yahei","microsoft yahei ui","simsun","nsimsun","simhei","kaiti","fangsong","dengxian","pingfang sc","hiragino sans gb","stheiti","stsong","songti sc","source han sans cn","source han sans sc","noto sans cjk sc","noto serif cjk sc","wenquanyi micro hei","wenquanyi zen hei","microsoft jhenghei","microsoft jhenghei ui","pmingliu","pmingliu-extb","mingliu","mingliu-extb","mingliu_hkscs","dfkai-sb","pingfang tc","pingfang hk","source han sans tw","noto sans cjk tc","misans","miui","harmonyos sans sc","harmonyos sans","honor sans","oppo sans","vivo sans","alibaba puhuiti","alibaba sans","dingtalk jinbuti","douyin sans","hyqihei","fzshusong-z01s","fzkai-z03s","fzhei-b01s","fzfangsong-z02s","kaiti_gb2312","fangsong_gb2312","simsun-extb","youyuan","lisu","stkaiti","stfangsong","stxihei","stzhongsong","sthupo","stxinwei","stliti","stcaiyun","fzyaoti","fzshuti","microsoft yahei light"]);
  const KEY = "__slcFontFamily7c1";
  function splitList(v) {
    const out = []; let cur = ""; let q = "";
    for (let i = 0; i < v.length; i++) {
      const c = v[i];
      if (q) { if (c === q) q = ""; cur += c; continue; }
      if (c === "'" || c === '"') { q = c; cur += c; continue; }
      if (c === ",") { out.push(cur); cur = ""; continue; }
      cur += c;
    }
    out.push(cur); return out;
  }
  function norm(n) { return n.trim().replace(/^['"]|['"]$/g, "").trim().toLowerCase(); }
  function clean(v) {
    if (typeof v !== "string" || !v) return v;
    const parts = splitList(v);
    const kept = parts.filter(p => !HIDDEN.has(norm(p)));
    if (kept.length === parts.length) return v;
    return kept.length ? kept.join(",") : "sans-serif";
  }
  function install(scope) {
    try {
      if (scope[KEY]) return;
      Object.defineProperty(scope, KEY, { value: true });
      const P = scope.CSSStyleDeclaration && scope.CSSStyleDeclaration.prototype;
      if (!P) return;
      let FP = null, d = null;
      for (const c of [scope.CSSStyleProperties, scope.CSS2Properties, scope.CSSStyleDeclaration]) {
        const pr = c && c.prototype; const x = pr && Object.getOwnPropertyDescriptor(pr, "fontFamily");
        if (x && x.set) { FP = pr; d = x; break; }
      }
      if (d && d.set) {
        Object.defineProperty(FP, "fontFamily", { configurable: true, enumerable: d.enumerable, get: d.get, set: function (v) { return d.set.call(this, clean(String(v))); } });
      }
      const HP = scope.HTMLElement && scope.HTMLElement.prototype;
      const EP = scope.Element && scope.Element.prototype;
      function withClean(el, fn) {
        let st = null, ff = "";
        try { st = el.style; ff = st ? st.fontFamily : ""; } catch (e) { st = null; }
        const c = ff ? clean(ff) : ff;
        if (!st || !ff || c === ff) return fn();
        st.fontFamily = c;
        try { return fn(); } finally { st.fontFamily = ff; }
      }
      if (HP) for (const key of ["offsetWidth", "offsetHeight"]) {
        const od = Object.getOwnPropertyDescriptor(HP, key);
        if (od && od.get) Object.defineProperty(HP, key, { configurable: true, enumerable: od.enumerable, get: function () { return withClean(this, () => od.get.call(this)); } });
      }
      if (EP) {
        for (const key of ["clientWidth", "clientHeight", "scrollWidth", "scrollHeight"]) {
          const od = Object.getOwnPropertyDescriptor(EP, key);
          if (od && od.get) Object.defineProperty(EP, key, { configurable: true, enumerable: od.enumerable, get: function () { return withClean(this, () => od.get.call(this)); } });
        }
        const gb = EP.getBoundingClientRect;
        if (typeof gb === "function") Object.defineProperty(EP, "getBoundingClientRect", { configurable: true, writable: true, value: function () { return withClean(this, () => gb.call(this)); } });
      }
      const sp = P.setProperty;
      if (typeof sp === "function") {
        Object.defineProperty(P, "setProperty", { configurable: true, writable: true, value: function (name, value, pr) {
          if (String(name).toLowerCase() === "font-family") value = clean(String(value));
          return sp.call(this, name, value, pr);
        } });
      }
    } catch (e) {}
  }
  install(globalThis);
  function hookFrames(scope) {
    try {
      const IP = scope.HTMLIFrameElement && scope.HTMLIFrameElement.prototype;
      if (!IP || IP.__slcFF7c1) return;
      Object.defineProperty(IP, "__slcFF7c1", { value: true });
      for (const key of ["contentWindow", "contentDocument"]) {
        const d = Object.getOwnPropertyDescriptor(IP, key);
        if (!d || !d.get) continue;
        Object.defineProperty(IP, key, { configurable: true, enumerable: d.enumerable, get: function () {
          const r = d.get.call(this);
          try {
            const w = key === "contentWindow" ? r : (r && r.defaultView);
            if (w) { install(w); hookFrames(w); }
          } catch (e) {}
          return r;
        } });
      }
    } catch (e) {}
  }
  hookFrames(globalThis);})();