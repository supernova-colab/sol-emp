// Guarda la app para que abra rápido y sin internet.
// - La app (index.html): siempre intenta la versión nueva primero; si no hay internet usa la guardada.
// - Librerías y letras de internet (llevan versión en su dirección): se guardan y se usan desde el teléfono.
// - Imágenes de la app: se muestran al instante desde lo guardado y se actualizan por detrás.
// - La base de datos (Supabase) nunca se guarda aquí: siempre va directo a internet.
const CACHE="sol-emp-v51";
const LIBS=["cdn.jsdelivr.net","unpkg.com","cdnjs.cloudflare.com","fonts.googleapis.com","fonts.gstatic.com"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(["./","./index.html","./manifest.webmanifest","./icon-192.png","./logo.png","./monigote.png?v=2"].map(u=>new Request(u,{cache:"reload"})))));self.skipWaiting()});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE&&k!=="sol-emp-libs").map(k=>caches.delete(k)))));self.clients.claim()});
self.addEventListener("fetch",e=>{
  if(e.request.method!=="GET")return;
  const u=new URL(e.request.url);
  if(LIBS.includes(u.hostname)){
    e.respondWith(caches.open("sol-emp-libs").then(c=>c.match(e.request).then(m=>m||fetch(e.request).then(r=>{if(r.ok||r.type==="opaque")c.put(e.request,r.clone());return r}))));
    return;
  }
  if(u.origin!==location.origin)return;
  if(e.request.mode==="navigate"||/\.(html|js|webmanifest)$/.test(u.pathname)||u.pathname.endsWith("/")){
    const req=e.request.mode==="navigate"?new Request(e.request.url,{cache:"no-cache"}):new Request(e.request,{cache:"no-cache"});
    e.respondWith(fetch(req).then(r=>{if(r.ok){const cp=r.clone();caches.open(CACHE).then(c=>c.put(e.request,cp))}return r}).catch(()=>caches.match(e.request).then(m=>m||caches.match("./index.html"))));
    return;
  }
  e.respondWith(caches.open(CACHE).then(c=>c.match(e.request).then(m=>{const f=fetch(e.request).then(r=>{if(r.ok)c.put(e.request,r.clone());return r}).catch(()=>m);return m||f})));
});
