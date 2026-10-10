// The page background: Nærøyfjord, baked by tools/make_fjord_signature.py, drawn by the studio's signature.js.
import { mount as mountSignature, webglAvailable } from './signature.js';

export async function mount(el) {
  if (!webglAvailable()) return;
  const theme = () => document.documentElement.dataset.theme === 'light' ? 'light' : 'dark';
  const sig = await mountSignature(el, { theme: theme(), transparent: true, source: 'data', fit: 'cover', lod: 'auto', intro: true });
  if (sig.fallback) return;
  window.addEventListener('themechange', () => sig.setTheme(theme()));
  el.classList.add('is-live');
  window.__sig = sig;
  return sig;
}
