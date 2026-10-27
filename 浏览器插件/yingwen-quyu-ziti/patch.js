globalThis.__slcSlot9f3e2a7c={"timezone":false,"webrtc":false,"language":true,"lang":"en-SG","intlLocale":true,"langs":["en-SG","en"],"timezoneOffset":false,"fonts":true};
globalThis.__slcCfg=globalThis.__slcSlot9f3e2a7c;delete globalThis.__slcSlot9f3e2a7c;try{
"use strict";
(() => {
  // src/generated/fonts.ts
  var HIDDEN_FONTS = [
    "Microsoft YaHei",
    "Microsoft YaHei UI",
    "SimSun",
    "NSimSun",
    "SimHei",
    "KaiTi",
    "FangSong",
    "DengXian",
    "PingFang SC",
    "Hiragino Sans GB",
    "STHeiti",
    "STSong",
    "Songti SC",
    "Source Han Sans CN",
    "Source Han Sans SC",
    "Noto Sans CJK SC",
    "Noto Serif CJK SC",
    "WenQuanYi Micro Hei",
    "WenQuanYi Zen Hei",
    "Microsoft JhengHei",
    "PMingLiU",
    "MingLiU",
    "DFKai-SB",
    "PingFang TC",
    "PingFang HK",
    "Source Han Sans TW",
    "Noto Sans CJK TC",
    "MiSans",
    "MIUI",
    "HarmonyOS Sans SC",
    "HarmonyOS Sans",
    "HONOR Sans",
    "OPPO Sans",
    "vivo Sans",
    "Alibaba PuHuiTi",
    "Alibaba Sans",
    "DingTalk JinBuTi",
    "Douyin Sans",
    "HYQiHei",
    "FZShuSong-Z01S",
    "FZKai-Z03S",
    "FZHei-B01S",
    "FZFangSong-Z02S"
  ];

  // src/patch/fonts.ts
  var SIZE = /^(?:xx-small|x-small|small|medium|large|x-large|xx-large|xxx-large|larger|smaller|(?:\d+(?:\.\d+)?(?:px|em|rem|pt|pc|ex|ch|vh|vw|vmin|vmax|%))(?:\/(?:normal|\d+(?:\.\d+)?(?:px|em|rem|%)?))?)$/i;
  function tokenizeFont(font) {
    const tokens = [];
    let cur = "";
    let quote = "";
    for (let i = 0; i < font.length; i += 1) {
      const ch = font[i] ?? "";
      if (quote) {
        cur += ch;
        if (ch === "\\" && i + 1 < font.length) {
          cur += font[i + 1];
          i += 1;
          continue;
        }
        if (ch === quote) quote = "";
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        cur += ch;
        continue;
      }
      if (ch === " " || ch === "	" || ch === "\n") {
        if (cur) tokens.push(cur);
        cur = "";
        continue;
      }
      cur += ch;
    }
    if (cur) tokens.push(cur);
    return tokens;
  }
  function splitFamilies(src) {
    const out = [];
    let cur = "";
    let quote = "";
    for (let i = 0; i < src.length; i += 1) {
      const ch = src[i] ?? "";
      if (quote) {
        cur += ch;
        if (ch === "\\" && i + 1 < src.length) {
          cur += src[i + 1];
          i += 1;
          continue;
        }
        if (ch === quote) quote = "";
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
        cur += ch;
        continue;
      }
      if (ch === ",") {
        if (cur.trim()) out.push(cur.trim());
        cur = "";
        continue;
      }
      cur += ch;
    }
    if (cur.trim()) out.push(cur.trim());
    return out;
  }
  function unquoteFamily(family) {
    const text = family.trim().replace(/\s+/g, " ");
    if (text.length >= 2 && (text.startsWith('"') && text.endsWith('"') || text.startsWith("'") && text.endsWith("'"))) {
      return text.slice(1, -1).replace(/\\(.)/g, "$1").trim();
    }
    return text;
  }
  function hiddenSet(hidden) {
    if (Array.isArray(hidden)) return new Set(hidden.map((name) => name.toLowerCase()));
    return hidden instanceof Set ? hidden : new Set(hidden);
  }
  function parseFontShorthand(font) {
    const tokens = tokenizeFont(font);
    let sizeIdx = -1;
    for (let i = 0; i < tokens.length; i += 1) {
      if (SIZE.test(tokens[i] || "")) {
        sizeIdx = i;
        break;
      }
    }
    if (sizeIdx < 0) return null;
    return {
      prefix: tokens.slice(0, sizeIdx + 1).join(" "),
      families: splitFamilies(tokens.slice(sizeIdx + 1).join(" "))
    };
  }
  function fontWithoutHidden(font, hidden) {
    const parsed = parseFontShorthand(font);
    if (!parsed) return null;
    const names = hiddenSet(hidden);
    let removed = false;
    const kept = [];
    for (const family of parsed.families) {
      if (names.has(unquoteFamily(family).toLowerCase())) removed = true;
      else kept.push(family);
    }
    if (!removed) return null;
    const families = kept.length ? kept.join(", ") : "sans-serif";
    return `${parsed.prefix} ${families}`;
  }
  function fontSpecHasHidden(font, hidden) {
    const names = hiddenSet(hidden);
    const parsed = parseFontShorthand(font);
    if (parsed) return parsed.families.some((family) => names.has(unquoteFamily(family).toLowerCase()));
    const lower = font.toLowerCase();
    for (const name of names) {
      if (lower.includes(`"${name}"`) || lower.includes(`'${name}'`)) return true;
    }
    return false;
  }
  function replaceMethod(proto, key, fn) {
    Object.defineProperty(proto, key, {
      value: fn,
      writable: true,
      configurable: true,
      enumerable: false
    });
  }
  function wrapMeasure(proto, hidden) {
    if (!proto || typeof proto.measureText !== "function") return;
    const orig = proto.measureText;
    replaceMethod(proto, "measureText", function(text) {
      let rewritten = false;
      let prev = "";
      try {
        const next = fontWithoutHidden(String(this.font ?? ""), hidden);
        if (next) {
          prev = String(this.font ?? "");
          this.font = next;
          rewritten = true;
        }
      } catch {
        rewritten = false;
      }
      try {
        return orig.call(this, text);
      } finally {
        if (rewritten) {
          try {
            this.font = prev;
          } catch {
          }
        }
      }
    });
  }
  var HIDDEN = new Set(HIDDEN_FONTS.map((name) => name.toLowerCase()));
  function installFonts(scope) {
    wrapMeasure(scope.CanvasRenderingContext2D?.prototype, HIDDEN);
    wrapMeasure(scope.OffscreenCanvasRenderingContext2D?.prototype, HIDDEN);
    const fonts = scope.FontFaceSet?.prototype;
    if (!fonts || typeof fonts.check !== "function") return;
    const orig = fonts.check;
    replaceMethod(fonts, "check", function(font, text) {
      try {
        if (fontSpecHasHidden(String(font), HIDDEN)) return false;
      } catch {
      }
      return orig.call(this, font, text);
    });
  }

  // src/patch/time.ts
  var cache = /* @__PURE__ */ new WeakMap();
  var GREGORIAN_400_MS = Date.UTC(2e3, 0, 1) - Date.UTC(1600, 0, 1);
  function utcFromWall(DateCtor, y, m, d, h = 0, mi = 0, s = 0, ms = 0) {
    const shift = y >= 0 && y <= 99 ? 400 : 0;
    return DateCtor.UTC(y + shift, m, d, h, mi, s, ms) - (shift ? GREGORIAN_400_MS : 0);
  }
  function formatter(deps, timeZone, kind) {
    let map = cache.get(deps.DateTimeFormat);
    if (!map) {
      map = /* @__PURE__ */ new Map();
      cache.set(deps.DateTimeFormat, map);
    }
    const key = kind + "\0" + timeZone;
    let dtf = map.get(key);
    if (!dtf) {
      dtf = kind === "name" ? new deps.DateTimeFormat("en-US", {
        timeZone,
        hourCycle: "h23",
        year: "numeric",
        timeZoneName: "long"
      }) : new deps.DateTimeFormat("en-US", {
        timeZone,
        hourCycle: "h23",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit"
      });
      map.set(key, dtf);
    }
    return dtf;
  }
  function partMap(dtf, instant) {
    const out = {};
    for (const part of dtf.formatToParts(instant)) {
      if (part.type !== "literal") out[part.type] = part.value;
    }
    return out;
  }
  function wallFromInstant(instantMs, timeZone, deps) {
    if (!Number.isFinite(instantMs)) return null;
    const map = partMap(formatter(deps, timeZone, "parts"), instantMs);
    let year = Number(map.year);
    let month = Number(map.month);
    let day = Number(map.day);
    let hour = Number(map.hour);
    const minute = Number(map.minute);
    const second = Number(map.second);
    if (![year, month, day, hour, minute, second].every(Number.isFinite)) return null;
    if (hour === 24) {
      hour = 0;
      const next = new deps.Date(utcFromWall(deps.Date, year, month - 1, day + 1));
      year = next.getUTCFullYear();
      month = next.getUTCMonth() + 1;
      day = next.getUTCDate();
    }
    const ms = new deps.Date(instantMs).getUTCMilliseconds();
    const wd = new deps.Date(utcFromWall(deps.Date, year, month - 1, day)).getUTCDay();
    return { y: year, m: month - 1, d: day, wd, h: hour, mi: minute, s: second, ms };
  }
  function getOffsetMinutes(instantMs, timeZone, deps) {
    const wall = wallFromInstant(instantMs, timeZone, deps);
    if (!wall) return 0;
    const asUTC = utcFromWall(deps.Date, wall.y, wall.m, wall.d, wall.h, wall.mi, wall.s, wall.ms);
    return -Math.round((asUTC - instantMs) / 6e4);
  }
  function sameWall(instant, y, m, d, h, mi, s, ms, timeZone, deps) {
    const wall = wallFromInstant(instant, timeZone, deps);
    return !!wall && wall.y === y && wall.m === m && wall.d === d && wall.h === h && wall.mi === mi && wall.s === s && wall.ms === ms;
  }
  function offsetsNear(desiredUtc, timeZone, deps) {
    const found = /* @__PURE__ */ new Set();
    const step = 15 * 60 * 1e3;
    for (let t = desiredUtc - 18 * 36e5; t <= desiredUtc + 18 * 36e5; t += step) {
      found.add(getOffsetMinutes(t, timeZone, deps));
    }
    found.add(getOffsetMinutes(desiredUtc, timeZone, deps));
    return [...found];
  }
  function wallToInstant(y, m, d, h, mi, s, ms, timeZone, deps) {
    const norm = utcFromWall(deps.Date, y, m, d, h, mi, s, ms);
    if (Number.isNaN(norm)) return NaN;
    const nd = new deps.Date(norm);
    const yy = nd.getUTCFullYear();
    const mm = nd.getUTCMonth();
    const dd = nd.getUTCDate();
    const hh = nd.getUTCHours();
    const mii = nd.getUTCMinutes();
    const ss = nd.getUTCSeconds();
    const mss = nd.getUTCMilliseconds();
    const desired = utcFromWall(deps.Date, yy, mm, dd, hh, mii, ss, mss);
    const off1 = getOffsetMinutes(desired, timeZone, deps);
    const t1 = desired + off1 * 6e4;
    if (sameWall(t1, yy, mm, dd, hh, mii, ss, mss, timeZone, deps)) {
      let best = t1;
      for (const delta of [60, -60, 30, -30, 120, -120]) {
        const probe = getOffsetMinutes(t1 + delta * 6e4, timeZone, deps);
        if (probe === off1) continue;
        const alt = desired + probe * 6e4;
        if (alt < best && sameWall(alt, yy, mm, dd, hh, mii, ss, mss, timeZone, deps)) best = alt;
      }
      return best;
    }
    const hits = [];
    const misses = [];
    for (const off of offsetsNear(desired, timeZone, deps)) {
      const instant = desired + off * 6e4;
      if (sameWall(instant, yy, mm, dd, hh, mii, ss, mss, timeZone, deps)) hits.push(instant);
      else misses.push(instant);
    }
    if (hits.length) return Math.min(...hits);
    if (misses.length) return Math.max(...misses);
    return desired;
  }
  function longTimeZoneName(instantMs, timeZone, deps) {
    const map = partMap(formatter(deps, timeZone, "name"), instantMs);
    return map.timeZoneName || timeZone;
  }
  function formatGmtOffset(offsetMin) {
    const sign = offsetMin > 0 ? "-" : "+";
    const abs = Math.abs(offsetMin);
    const hh = String(Math.floor(abs / 60)).padStart(2, "0");
    const mm = String(abs % 60).padStart(2, "0");
    return `GMT${sign}${hh}${mm}`;
  }
  var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  function pad2(n) {
    return String(n).padStart(2, "0");
  }
  function formatYear(y) {
    if (y >= 0 && y < 1e4) return String(y).padStart(4, "0");
    const sign = y < 0 ? "-" : "+";
    return sign + String(Math.abs(y));
  }
  function formatChromeDate(wall, offsetMin, tzName) {
    const date = `${DAYS[wall.wd]} ${MONTHS[wall.m]} ${pad2(wall.d)} ${formatYear(wall.y)}`;
    const time = `${pad2(wall.h)}:${pad2(wall.mi)}:${pad2(wall.s)} ${formatGmtOffset(offsetMin)} (${tzName})`;
    return { date, time, full: `${date} ${time}` };
  }

  // src/patch/ua.ts
  function defineGetter(proto, key, get) {
    Object.defineProperty(proto, key, {
      configurable: true,
      enumerable: true,
      get
    });
  }
  function copyBrands(list, freeze) {
    return (list || []).map((item) => freeze({ brand: String(item.brand), version: String(item.version) }));
  }
  function makeUaData(scope, cfg2) {
    const freeze = (value) => scope.Object.freeze(value);
    const brands = freeze(copyBrands(cfg2.brands, (value) => scope.Object.freeze(value)));
    const fullVersionList = freeze(copyBrands(cfg2.fullVersionList, (value) => scope.Object.freeze(value)));
    const platform = String(cfg2.uaPlatform || "");
    const high = freeze({
      brands,
      fullVersionList,
      mobile: false,
      platform,
      platformVersion: String(cfg2.platformVersion ?? ""),
      model: "",
      architecture: String(cfg2.architecture || "x86"),
      bitness: String(cfg2.bitness || "64"),
      wow64: false
    });
    return freeze({
      brands,
      mobile: false,
      platform,
      getHighEntropyValues() {
        return Promise.resolve(high);
      },
      toJSON() {
        return { brands, mobile: false, platform };
      }
    });
  }
  var KEYS = ["userAgent", "appVersion", "platform", "vendor", "userAgentData"];
  function installUserAgent(scope, cfg2) {
    const proto = scope.Navigator?.prototype;
    if (!proto || !cfg2.ua) return;
    const nav = scope.navigator;
    if (nav) {
      for (const key of KEYS) {
        try {
          if (scope.Object.prototype.hasOwnProperty.call(nav, key)) delete nav[key];
        } catch {
        }
      }
    }
    const ua = cfg2.ua;
    const appVersion = cfg2.appVersion || ua.replace(/^Mozilla\//, "");
    const data = makeUaData(scope, cfg2);
    defineGetter(proto, "userAgent", () => ua);
    defineGetter(proto, "appVersion", () => appVersion);
    defineGetter(proto, "platform", () => cfg2.navPlatform || "");
    defineGetter(proto, "vendor", () => cfg2.vendor || "Google Inc.");
    defineGetter(proto, "userAgentData", () => data);
  }

  // src/patch/webrtc.ts
  var WRAPPED = /* @__PURE__ */ Symbol.for("slc.webrtc.9f3e2a7c");
  function isIpv4(addr) {
    if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(addr)) return false;
    return addr.split(".").every((part) => Number(part) <= 255);
  }
  function isIpv6(addr) {
    if (!addr.includes(":") || !/^[0-9a-fA-F:]+$/.test(addr)) return false;
    const halves = addr.split("::");
    if (halves.length > 2) return false;
    const groups = (half) => half ? half.split(":").filter((part) => part.length > 0).length : 0;
    if (halves.length === 2) return groups(halves[0] || "") + groups(halves[1] || "") <= 7;
    return addr.split(":").length === 8;
  }
  function isIpAddress(addr) {
    return isIpv4(addr) || isIpv6(addr);
  }
  function parseCandidate(line) {
    const text = line.trim().replace(/^a=/i, "");
    const match = /^candidate:\S+ \d+ \S+ \d+ (\S+) \d+ typ (\S+)/i.exec(text);
    if (!match) return null;
    return { addr: match[1] || "", typ: (match[2] || "").toLowerCase() };
  }
  function tailHasIp(line) {
    const idx = line.toLowerCase().indexOf(" typ ");
    const tail = idx >= 0 ? line.slice(idx + 5).replace(/^(host|srflx|prflx|relay)\b/i, "") : line;
    if (/(?:^|[^0-9])(\d{1,3}(?:\.\d{1,3}){3})(?![0-9])/.test(tail)) return true;
    return /[0-9a-fA-F]{0,4}::|[0-9a-fA-F]+:[0-9a-fA-F]+:/.test(tail);
  }
  function candidateExposesAddress(line) {
    if (!line) return false;
    const parsed = parseCandidate(line);
    if (!parsed) return false;
    if (parsed.typ === "relay") return false;
    if (parsed.typ !== "host" && parsed.typ !== "srflx" && parsed.typ !== "prflx") return false;
    if (isIpAddress(parsed.addr)) return true;
    if (parsed.addr.endsWith(".local")) return tailHasIp(line);
    return false;
  }
  function iceEventExposesAddress(event) {
    if (!event || !event.candidate) return false;
    const line = event.candidate.candidate;
    if (!line) return false;
    return candidateExposesAddress(line);
  }
  function filterSdp(sdp) {
    if (!sdp) return sdp;
    const newline = sdp.includes("\r\n") ? "\r\n" : "\n";
    const parts = sdp.split(/\r?\n/);
    const kept = parts.filter((line) => {
      if (!/^a=candidate:/i.test(line) && !/^candidate:/i.test(line)) return true;
      return !candidateExposesAddress(line);
    });
    if (kept.length === parts.length) return sdp;
    return kept.join(newline);
  }
  function filterDescription(value, RTCSessionDescription) {
    if (!value || typeof value.sdp !== "string") return value;
    const sdp = filterSdp(value.sdp);
    if (sdp === value.sdp) return value;
    const type = value.type || "offer";
    if (typeof RTCSessionDescription === "function") {
      try {
        return new RTCSessionDescription({ type, sdp });
      } catch {
      }
    }
    return { type, sdp };
  }
  function replaceMethod2(proto, key, fn) {
    Object.defineProperty(proto, key, {
      value: fn,
      writable: true,
      configurable: true,
      enumerable: false
    });
  }
  function wrapIceSetter(proto) {
    const current = Object.getOwnPropertyDescriptor(proto, "onicecandidate");
    const store = /* @__PURE__ */ new WeakMap();
    Object.defineProperty(proto, "onicecandidate", {
      configurable: true,
      enumerable: current?.enumerable ?? true,
      get() {
        if (current?.get) return current.get.call(this);
        return store.get(this) ?? null;
      },
      set(handler) {
        const wrapped = typeof handler === "function" ? function(event) {
          try {
            if (iceEventExposesAddress(event)) return;
          } catch {
          }
          return handler.call(this, event);
        } : handler;
        if (current?.set) current.set.call(this, wrapped);
        else store.set(this, wrapped);
      }
    });
  }
  function wrapAddListener(proto) {
    const origAdd = proto.addEventListener;
    const origRemove = proto.removeEventListener;
    if (typeof origAdd !== "function") return;
    const map = /* @__PURE__ */ new WeakMap();
    const wrap = (listener) => {
      if (!listener || typeof listener !== "function" && typeof listener.handleEvent !== "function") {
        return listener;
      }
      const cached = map.get(listener);
      if (cached) return cached;
      const wrapped = typeof listener === "function" ? function(event) {
        try {
          if (iceEventExposesAddress(event)) return;
        } catch {
        }
        return listener.call(this, event);
      } : {
        handleEvent(event) {
          try {
            if (iceEventExposesAddress(event)) return;
          } catch {
          }
          return listener.handleEvent(event);
        }
      };
      map.set(listener, wrapped);
      return wrapped;
    };
    replaceMethod2(proto, "addEventListener", function(type, listener, options) {
      if (type === "icecandidate") return origAdd.call(this, type, wrap(listener), options);
      return origAdd.call(this, type, listener, options);
    });
    if (typeof origRemove === "function") {
      replaceMethod2(proto, "removeEventListener", function(type, listener, options) {
        if (type === "icecandidate" && listener && map.has(listener)) {
          return origRemove.call(this, type, map.get(listener), options);
        }
        return origRemove.call(this, type, listener, options);
      });
    }
  }
  function wrapSdpMethod(proto, key, RTCSessionDescription) {
    const orig = proto[key];
    if (typeof orig !== "function") return;
    const clean = (desc) => {
      try {
        return filterDescription(desc, RTCSessionDescription);
      } catch {
        return desc;
      }
    };
    replaceMethod2(proto, key, function(...args) {
      if (typeof args[0] === "function") {
        const success = args[0];
        args[0] = (desc) => success(clean(desc));
        return orig.apply(this, args);
      }
      const result = orig.apply(this, args);
      if (result && typeof result.then === "function") {
        return result.then((desc) => clean(desc));
      }
      return result;
    });
  }
  function wrapDescriptions(proto, RTCSessionDescription) {
    for (const key of ["localDescription", "currentLocalDescription", "pendingLocalDescription"]) {
      const current = Object.getOwnPropertyDescriptor(proto, key);
      if (!current?.get) continue;
      const orig = current.get;
      try {
        Object.defineProperty(proto, key, {
          configurable: true,
          enumerable: current.enumerable ?? true,
          get() {
            const value = orig.call(this);
            try {
              return filterDescription(value, RTCSessionDescription);
            } catch {
              return value;
            }
          }
        });
      } catch {
      }
    }
  }
  function patchPrototype(proto, scope) {
    if (!proto || proto[WRAPPED]) return;
    Object.defineProperty(proto, WRAPPED, { value: true, enumerable: false });
    wrapIceSetter(proto);
    wrapAddListener(proto);
    wrapSdpMethod(proto, "createOffer", scope.RTCSessionDescription);
    wrapSdpMethod(proto, "createAnswer", scope.RTCSessionDescription);
    wrapDescriptions(proto, scope.RTCSessionDescription);
  }
  function replaceConstructor(scope, name, Original) {
    function Patched(...args) {
      const reflect = scope.Reflect;
      const target = new.target && new.target !== Patched ? new.target : Original;
      if (reflect) return reflect.construct(Original, args, target);
      const Ctor = Original;
      return new Ctor(...args);
    }
    Patched.prototype = Original.prototype;
    try {
      Object.defineProperty(Patched, "name", { value: Original.name || name, configurable: true });
    } catch {
    }
    for (const key of Object.getOwnPropertyNames(Original)) {
      if (key === "prototype" || key === "length" || key === "name") continue;
      const desc = Object.getOwnPropertyDescriptor(Original, key);
      if (!desc) continue;
      try {
        Object.defineProperty(Patched, key, desc);
      } catch {
      }
    }
    try {
      scope[name] = Patched;
    } catch {
    }
  }
  function installWebrtc(scope) {
    const seen = /* @__PURE__ */ new Set();
    for (const name of ["RTCPeerConnection", "webkitRTCPeerConnection"]) {
      const Original = scope[name];
      if (typeof Original !== "function" || seen.has(Original)) continue;
      seen.add(Original);
      try {
        patchPrototype(Original.prototype, scope);
      } catch {
      }
      replaceConstructor(scope, name, Original);
    }
  }

  // src/patch/install.ts
  var INSTALLED = /* @__PURE__ */ Symbol.for("slc.installed.9f3e2a7c");
  function enabled(v) {
    return v === true || v === 1;
  }
  function replaceMethod3(proto, key, fn) {
    Object.defineProperty(proto, key, {
      value: fn,
      writable: true,
      configurable: true,
      enumerable: false
    });
  }
  function defineGetter2(proto, key, get) {
    Object.defineProperty(proto, key, {
      configurable: true,
      enumerable: true,
      get
    });
  }
  function install(scope, cfg2) {
    if (!cfg2) return;
    if (scope[INSTALLED]) return;
    Object.defineProperty(scope, INSTALLED, { value: true, enumerable: false, writable: false, configurable: false });
    const tzOn = enabled(cfg2.timezone);
    const offsetOn = enabled(cfg2.timezoneOffset);
    const langOn = enabled(cfg2.language);
    const intlOn = enabled(cfg2.intlLocale);
    const timeZone = cfg2.tz || "America/Los_Angeles";
    const locale = cfg2.lang || "en-US";
    const langs = (cfg2.langs && cfg2.langs.length ? cfg2.langs.slice() : [locale]).map(String);
    if (langs[0] !== locale) langs.unshift(locale);
    const OrigDate = scope.Date;
    const OrigDTF = scope.Intl.DateTimeFormat;
    const deps = { Date: OrigDate, DateTimeFormat: OrigDTF };
    if (tzOn || intlOn) guard(() => wrapIntl(scope, deps, { tzOn, intlOn, timeZone, locale }));
    if (offsetOn) guard(() => wrapDate(scope, deps, timeZone, { tzOn, intlOn, locale }));
    else if (intlOn || tzOn) guard(() => wrapDateToLocaleOnly(scope, deps, { tzOn, intlOn, timeZone, locale }));
    if (intlOn) guard(() => wrapOtherToLocale(scope, locale));
    if (langOn) guard(() => wrapNavigator(scope, locale, langs));
    if (tzOn) guard(() => wrapTemporal(scope, timeZone));
    if (enabled(cfg2.fonts)) guard(() => installFonts(scope));
    if (enabled(cfg2.webrtc)) guard(() => installWebrtc(scope));
    if (cfg2.ua) guard(() => installUserAgent(scope, cfg2));
  }
  function guard(fn) {
    try {
      fn();
    } catch (err) {
      console.error("slc", err);
    }
  }
  function wrapIntl(scope, deps, opts) {
    const intl = scope.Intl;
    const names = [
      "DateTimeFormat",
      "NumberFormat",
      "Collator",
      "PluralRules",
      "RelativeTimeFormat",
      "ListFormat",
      "DisplayNames",
      "Segmenter",
      "DurationFormat"
    ];
    for (const name of names) {
      const Original = intl[name];
      if (typeof Original !== "function") continue;
      const fillTz = name === "DateTimeFormat" && opts.tzOn;
      const fillLocale = opts.intlOn;
      if (!fillTz && !fillLocale) continue;
      if (name === "DateTimeFormat") {
        intl[name] = wrapCtor(deps.DateTimeFormat, scope, fillLocale ? opts.locale : null, fillTz ? opts.timeZone : null);
      } else {
        intl[name] = wrapCtor(Original, scope, fillLocale ? opts.locale : null, null);
      }
    }
  }
  function wrapCtor(Original, scope, locale, timeZone) {
    function Wrapped(locales, options) {
      let loc = locales;
      if (locale != null && locales === void 0) loc = locale;
      let opt = options;
      if (timeZone != null) {
        if (options == null) opt = { timeZone };
        else if (typeof options === "object" && options.timeZone == null) {
          opt = { ...options, timeZone };
        }
      }
      const target = new.target || Original;
      return scope.Reflect.construct(Original, [loc, opt], target);
    }
    Wrapped.prototype = Original.prototype;
    Object.defineProperty(Wrapped, "name", { value: Original.name, configurable: true });
    Object.defineProperty(Wrapped, "length", { value: Original.length, configurable: true });
    const supported = Original.supportedLocalesOf;
    if (typeof supported === "function") {
      Object.defineProperty(Wrapped, "supportedLocalesOf", {
        value(locales, options) {
          return supported(locales, options);
        },
        writable: true,
        configurable: true
      });
    }
    return Wrapped;
  }
  function captureLocal(OrigDate) {
    const p = OrigDate.prototype;
    return {
      getFullYear: p.getFullYear,
      getMonth: p.getMonth,
      getDate: p.getDate,
      getHours: p.getHours,
      getMinutes: p.getMinutes,
      getSeconds: p.getSeconds,
      getMilliseconds: p.getMilliseconds,
      getTime: p.getTime
    };
  }
  function wrapDate(scope, deps, timeZone, flags) {
    const OrigDate = deps.Date;
    const proto = OrigDate.prototype;
    const local = captureLocal(OrigDate);
    const origSetTime = proto.setTime;
    const origToString = proto.toString;
    const read = (instant) => wallFromInstant(instant, timeZone, deps);
    function component(key) {
      const t = local.getTime.call(this);
      if (Number.isNaN(t)) return NaN;
      const wall = read(t);
      return wall ? wall[key] : NaN;
    }
    replaceMethod3(proto, "getFullYear", function() {
      return component.call(this, "y");
    });
    replaceMethod3(proto, "getMonth", function() {
      return component.call(this, "m");
    });
    replaceMethod3(proto, "getDate", function() {
      return component.call(this, "d");
    });
    replaceMethod3(proto, "getDay", function() {
      return component.call(this, "wd");
    });
    replaceMethod3(proto, "getHours", function() {
      return component.call(this, "h");
    });
    replaceMethod3(proto, "getMinutes", function() {
      return component.call(this, "mi");
    });
    replaceMethod3(proto, "getSeconds", function() {
      return component.call(this, "s");
    });
    replaceMethod3(proto, "getTimezoneOffset", function() {
      const t = local.getTime.call(this);
      if (Number.isNaN(t)) return NaN;
      return getOffsetMinutes(t, timeZone, deps);
    });
    function write(nanMode, mutate) {
      let t = local.getTime.call(this);
      if (Number.isNaN(t)) {
        if (nanMode === "nan") return NaN;
        t = 0;
      }
      const wall = read(t);
      if (!wall) return NaN;
      mutate(wall);
      const next = wallToInstant(wall.y, wall.m, wall.d, wall.h, wall.mi, wall.s, wall.ms, timeZone, deps);
      return origSetTime.call(this, next);
    }
    const num = (v) => Number(v);
    replaceMethod3(proto, "setFullYear", function(y, m, d) {
      const argc = arguments.length;
      return write.call(this, "epoch", (wall) => {
        wall.y = num(y);
        if (argc >= 2) wall.m = num(m);
        if (argc >= 3) wall.d = num(d);
      });
    });
    replaceMethod3(proto, "setMonth", function(m, d) {
      const argc = arguments.length;
      return write.call(this, "epoch", (wall) => {
        wall.m = num(m);
        if (argc >= 2) wall.d = num(d);
      });
    });
    replaceMethod3(proto, "setDate", function(d) {
      return write.call(this, "epoch", (wall) => {
        wall.d = num(d);
      });
    });
    replaceMethod3(proto, "setHours", function(h, mi, s, ms) {
      const argc = arguments.length;
      return write.call(this, "nan", (wall) => {
        if (argc >= 1) wall.h = num(h);
        if (argc >= 2) wall.mi = num(mi);
        if (argc >= 3) wall.s = num(s);
        if (argc >= 4) wall.ms = num(ms);
      });
    });
    replaceMethod3(proto, "setMinutes", function(mi, s, ms) {
      const argc = arguments.length;
      return write.call(this, "nan", (wall) => {
        if (argc >= 1) wall.mi = num(mi);
        if (argc >= 2) wall.s = num(s);
        if (argc >= 3) wall.ms = num(ms);
      });
    });
    replaceMethod3(proto, "setSeconds", function(s, ms) {
      const argc = arguments.length;
      return write.call(this, "nan", (wall) => {
        if (argc >= 1) wall.s = num(s);
        if (argc >= 2) wall.ms = num(ms);
      });
    });
    function chromeParts() {
      const t = local.getTime.call(this);
      if (Number.isNaN(t)) return null;
      const wall = read(t);
      if (!wall) return null;
      const name = longTimeZoneName(t, timeZone, deps);
      const off = getOffsetMinutes(t, timeZone, deps);
      return formatChromeDate(wall, off, name);
    }
    replaceMethod3(proto, "toString", function() {
      return chromeParts.call(this)?.full ?? origToString.call(this);
    });
    replaceMethod3(proto, "toDateString", function() {
      return chromeParts.call(this)?.date ?? origToString.call(this).split(" ").slice(0, 4).join(" ");
    });
    replaceMethod3(proto, "toTimeString", function() {
      const parts = chromeParts.call(this);
      if (!parts) return origToString.call(this);
      return parts.time;
    });
    wrapDateToLocale(proto, flags.tzOn, flags.intlOn, timeZone, flags.locale);
    const parse = (input) => parseDateString(input, timeZone, deps, OrigDate, local);
    function PatchedDate(...args) {
      if (!new.target) return scope.Reflect.construct(PatchedDate, [], PatchedDate).toString();
      if (args.length === 0) return scope.Reflect.construct(OrigDate, [], new.target);
      if (args.length === 1) {
        const value = args[0];
        if (typeof value === "string") {
          return scope.Reflect.construct(OrigDate, [parse(value)], new.target);
        }
        return scope.Reflect.construct(OrigDate, [value], new.target);
      }
      const yRaw = Number(args[0]);
      const y = yRaw >= 0 && yRaw <= 99 ? yRaw + 1900 : yRaw;
      const m = Number(args[1]);
      const d = args.length >= 3 ? Number(args[2]) : 1;
      const h = args.length >= 4 ? Number(args[3]) : 0;
      const mi = args.length >= 5 ? Number(args[4]) : 0;
      const s = args.length >= 6 ? Number(args[5]) : 0;
      const ms = args.length >= 7 ? Number(args[6]) : 0;
      const instant = wallToInstant(y, m, d, h, mi, s, ms, timeZone, deps);
      return scope.Reflect.construct(OrigDate, [instant], new.target);
    }
    Object.defineProperty(PatchedDate, "prototype", { value: proto, writable: false, configurable: false });
    Object.defineProperty(PatchedDate, "name", { value: "Date", configurable: true });
    Object.defineProperty(PatchedDate, "length", { value: 7, configurable: true });
    Object.defineProperty(PatchedDate, "parse", {
      value: (input) => parse(String(input)),
      writable: true,
      configurable: true
    });
    Object.defineProperty(PatchedDate, "UTC", { value: OrigDate.UTC, writable: true, configurable: true });
    Object.defineProperty(PatchedDate, "now", { value: OrigDate.now, writable: true, configurable: true });
    try {
      Object.defineProperty(proto, "constructor", { value: PatchedDate, writable: true, configurable: true });
    } catch {
    }
    scope.Date = PatchedDate;
  }
  function wrapDateToLocaleOnly(scope, deps, flags) {
    wrapDateToLocale(deps.Date.prototype, flags.tzOn, flags.intlOn, flags.timeZone, flags.locale);
  }
  function wrapDateToLocale(proto, tzOn, intlOn, timeZone, locale) {
    for (const key of ["toLocaleString", "toLocaleDateString", "toLocaleTimeString"]) {
      const orig = proto[key];
      replaceMethod3(proto, key, function(locales, options) {
        let loc = locales;
        if (intlOn && locales === void 0) loc = locale;
        let opt = options;
        if (tzOn) {
          if (options == null) opt = { timeZone };
          else if (typeof options === "object" && options.timeZone == null) {
            opt = { ...options, timeZone };
          }
        }
        if (loc === locales && opt === options) return orig.apply(this, [locales, options]);
        return orig.call(this, loc, opt);
      });
    }
  }
  function wrapOtherToLocale(scope, locale) {
    const pairs = [
      [scope.Number.prototype, ["toLocaleString"]],
      [scope.String.prototype, ["toLocaleString", "toLocaleLowerCase", "toLocaleUpperCase"]]
    ];
    for (const [proto, keys] of pairs) {
      for (const key of keys) {
        const orig = proto[key];
        if (typeof orig !== "function") continue;
        replaceMethod3(proto, key, function(locales, ...rest) {
          if (locales !== void 0) return orig.apply(this, [locales, ...rest]);
          return orig.call(this, locale, ...rest);
        });
      }
    }
  }
  function wrapNavigator(scope, locale, langs) {
    const proto = scope.Navigator?.prototype;
    if (!proto) return;
    const frozen = scope.Object.freeze(langs.slice());
    const nav = scope.navigator;
    if (nav) {
      for (const key of ["language", "languages"]) {
        try {
          if (scope.Object.prototype.hasOwnProperty.call(nav, key)) delete nav[key];
        } catch {
        }
      }
    }
    defineGetter2(proto, "language", () => locale);
    defineGetter2(proto, "languages", () => frozen);
  }
  function wrapTemporal(scope, timeZone) {
    const Now = scope.Temporal?.Now;
    if (!Now) return;
    if (typeof Now.timeZoneId === "function") {
      Now.timeZoneId = function timeZoneId() {
        return timeZone;
      };
    }
    for (const name of ["zonedDateTimeISO", "plainDateTimeISO", "plainDateISO", "plainTimeISO"]) {
      const orig = Now[name];
      if (typeof orig !== "function") continue;
      Now[name] = function(tzLike, ...rest) {
        const argc = arguments.length;
        if (argc === 0 || tzLike == null) return orig.call(Now, timeZone, ...rest);
        return orig.call(Now, tzLike, ...rest);
      };
    }
  }
  var ISO_RE = /^(\d{4})(?:-(\d{2})(?:-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?)?)?)?(Z|([+-])(\d{2}):?(\d{2}))?$/;
  function parseDateString(input, timeZone, deps, OrigDate, local) {
    const text = String(input).trim();
    const match = ISO_RE.exec(text);
    if (match) {
      const year = Number(match[1]);
      const month = match[2];
      const day = match[3];
      const hour = match[4];
      const hasZone = Boolean(match[8]);
      if (!hour || hasZone || !month || !day) return OrigDate.parse(text);
      const mo = Number(month);
      const dd = Number(day);
      const hh = Number(hour);
      const mi = Number(match[5]);
      const ss = match[6] ? Number(match[6]) : 0;
      const frac = match[7] ? Number(match[7].padEnd(3, "0")) : 0;
      if (mo < 1 || mo > 12 || dd < 1 || dd > 31 || hh > 23 || mi > 59 || ss > 59) return NaN;
      const probe = `${match[1]}-${month}-${day}T${hour}:${match[5]}:${String(ss).padStart(2, "0")}.${String(frac).padStart(3, "0")}Z`;
      if (Number.isNaN(OrigDate.parse(probe))) return NaN;
      return wallToInstant(year, mo - 1, dd, hh, mi, ss, frac, timeZone, deps);
    }
    if (/(?:Z|[+-]\d{2}:?\d{2}|\bGMT\b|\bUTC\b)/i.test(text)) return OrigDate.parse(text);
    const sys = OrigDate.parse(text);
    if (Number.isNaN(sys)) return NaN;
    const date = new OrigDate(sys);
    return wallToInstant(
      local.getFullYear.call(date),
      local.getMonth.call(date),
      local.getDate.call(date),
      local.getHours.call(date),
      local.getMinutes.call(date),
      local.getSeconds.call(date),
      local.getMilliseconds.call(date),
      timeZone,
      deps
    );
  }

  // src/patch/entry.ts
  var cfg = globalThis.__slcCfg;
  install(globalThis, cfg);
})();
}finally{delete globalThis.__slcCfg;}
