/* Local fixed Canvas readback profiles. Does not write cookies or browser data. */
(() => {
  'use strict';
  const host = location.hostname;
  if (host === 'challenges.cloudflare.com' ||
      ((host === 'www.google.com' || host === 'www.recaptcha.net') && location.pathname.startsWith('/recaptcha/'))) return;
  const profiles = {"Chrome":3526629240,"Edge":3341653863};
  const seed = /\bEdg\//.test(navigator.userAgent) ? profiles.Edge : profiles.Chrome;
  const canvasProto = globalThis.HTMLCanvasElement?.prototype;
  const contextProto = globalThis.CanvasRenderingContext2D?.prototype;
  if (!canvasProto || !contextProto) return;
  const read = contextProto.getImageData;
  const put = contextProto.putImageData;
  const encode = canvasProto.toDataURL;
  const blob = canvasProto.toBlob;
  const getContextNative = canvasProto.getContext;
  const contextSpaces = new WeakMap();

  function eligible(canvas) {
    return canvas && canvas.width > 0 && canvas.height > 0 &&
      canvas.width <= 1024 && canvas.height <= 1024 && canvas.width * canvas.height <= 262144;
  }
  function bits(x, y, width) {
    let value = (seed ^ Math.imul(y * width + x + 1, 0x9e3779b1)) >>> 0;
    value = Math.imul(value ^ value >>> 16, 0x85ebca6b);
    return (value ^ value >>> 13) >>> 0;
  }
  function transform(image, canvas, left, top) {
    if (!(image.data instanceof Uint8ClampedArray) || image.colorSpace !== 'srgb') return false;
    let changed = false;
    for (let y = 0; y < image.height; y++) {
      const cy = top + y;
      if (cy < 0 || cy >= canvas.height) continue;
      for (let x = 0; x < image.width; x++) {
        const cx = left + x;
        if (cx < 0 || cx >= canvas.width) continue;
        const offset = (y * image.width + x) * 4;
        // Leave blank and translucent pixels unchanged, including alpha.
        if (image.data[offset + 3] !== 255) continue;
        const value = bits(cx, cy, canvas.width);
        for (let channel = 0; channel < 3; channel++) {
          const before = image.data[offset + channel];
          const after = (before & 254) | ((value >>> channel) & 1);
          image.data[offset + channel] = after;
          changed ||= before !== after;
        }
      }
    }
    return changed;
  }
  function copyForExport(canvas) {
    if (!(canvas instanceof HTMLCanvasElement) || !eligible(canvas)) return null;
    // Querying getContext here would bind an untouched canvas to 2D forever.
    // Only transform canvases whose page already requested an sRGB 2D context.
    if (contextSpaces.get(canvas) !== 'srgb') return null;
    const copy = canvas.ownerDocument.createElement('canvas');
    copy.width = canvas.width;
    copy.height = canvas.height;
    const context = copy.getContext('2d', { willReadFrequently: true });
    context.drawImage(canvas, 0, 0);
    const image = read.call(context, 0, 0, copy.width, copy.height);
    if (!transform(image, canvas, 0, 0)) return null;
    put.call(context, image, 0, 0);
    return copy;
  }
  function replace(proto, key, fn) {
    const descriptor = Object.getOwnPropertyDescriptor(proto, key);
    if (descriptor?.configurable) Object.defineProperty(proto, key, { ...descriptor, value: fn });
  }
  replace(canvasProto, 'getContext', function getContext(...args) {
    const context = getContextNative.apply(this, args);
    if (context && args[0] === '2d')
      contextSpaces.set(this, context.getContextAttributes?.().colorSpace || 'srgb');
    return context;
  });
  replace(contextProto, 'getImageData', function getImageData(...args) {
    const image = read.apply(this, args);
    if (!eligible(this.canvas) || !args.slice(0, 4).every(value =>
      typeof value === 'number' && Number.isSafeInteger(value) && Math.abs(value) < 0x40000000)) return image;
    const left = args[0] + (args[2] < 0 ? -image.width : 0);
    const top = args[1] + (args[3] < 0 ? -image.height : 0);
    transform(image, this.canvas, left, top);
    return image;
  });
  replace(canvasProto, 'toDataURL', function toDataURL(...args) {
    let copy = null;
    try { copy = copyForExport(this); } catch { /* Native method retains its own errors. */ }
    return encode.apply(copy || this, args);
  });
  replace(canvasProto, 'toBlob', function toBlob(...args) {
    if (typeof args[0] !== 'function') return blob.apply(this, args);
    let copy = null;
    try { copy = copyForExport(this); } catch { /* Native method retains its own errors. */ }
    return blob.apply(copy || this, args);
  });
})();
