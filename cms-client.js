/* =====================================================================
   ALUQE COUTURE — STOREFRONT CMS LOADER
   Include this AFTER the supabase-js CDN script and BEFORE your existing
   inline <script> block's carousel-setup code. See README-CMS.md for the
   exact wiring — the short version:

     1. Add before your closing </body>, ABOVE your existing script tag:
          <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
          <script src="cms-client.js"></script>

     2. In your existing inline script, wrap everything from
          const orbitCarousel = new RingCarousel(...)
        down to the end of the file in a function:
          function initInteractive(){ ...all that existing code... }

     3. Replace that block's call site with:
          ALUQE_CMS.init().finally(initInteractive);

   Every render function below is defensive: if Supabase isn't configured,
   the fetch fails, or a table is empty, it leaves your existing static
   HTML exactly as it is — nothing breaks if the CMS isn't reachable.
===================================================================== */

const ALUQE_CMS = (function(){
  const SUPABASE_URL = 'https://bhoqjvmtdvhamqeraxyo.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJob3Fqdm10ZHZoYW1xZXJheHlvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAxNjA1MTAsImV4cCI6MjEwNTczNjUxMH0.Jpy-ivIckgPWEJhnHX-2fhbWBmU3p3PcuHd8S0NBMHE';

  let db = null;
  try{
    if(window.supabase && SUPABASE_URL.startsWith('https://') && !SUPABASE_URL.includes('YOUR-PROJECT')){
      db = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    }
  }catch(e){ /* supabase-js not loaded yet, or bad config — storefront falls back to static content */ }

  function money(n){ return '$'+Number(n).toFixed(2); }

  /* ---------------- categories: feeds the avatar rail + the mood ring ---------------- */
  async function loadCategories(){
    if(!db) return;
    const { data, error } = await db.from('categories').select('*').eq('is_active',true).order('sort_order');
    if(error || !data || !data.length) return;

    // avatar rail (#catOrbitTrack) — duplicate the list once for the seamless drift loop
    const track = document.querySelector('#catOrbitTrack');
    if(track){
      const itemHtml = c => c.slug==='sale'
        ? `<a class="cat-orbit-item sale" data-filter="sale" href="#shop"><div class="cat-orbit-avatar sale"><em>%</em></div><span>Sale</span></a>`
        : `<a class="cat-orbit-item" data-filter="${c.slug}" href="#shop"><div class="cat-orbit-avatar"><img src="${c.image_url||''}" alt="${c.name}"></div><span>${c.name}</span></a>`;
      const all = `<a class="cat-orbit-item" data-filter="all" href="#shop"><div class="cat-orbit-avatar brand"><em>AC</em></div><span>All</span></a>`;
      const list = [all, ...data.map(itemHtml)];
      track.innerHTML = list.join('') + list.join('');
    }

    // "Shop by mood" ring (#orbitRing) — skip the synthetic 'sale' row here, it's a filter, not a mood
    const ring = document.querySelector('#orbitRing');
    if(ring){
      ring.innerHTML = data.filter(c=>c.slug!=='sale').map(c=>`
        <a class="ring-item pcard mood-card" href="#shop" data-category="${c.slug}" aria-label="Shop ${c.name}">
          <div class="pimg"><img src="${c.image_url||''}" alt="${c.name}"></div>
          <div class="pcopy"><h3>${c.name}</h3><p>Shop the edit</p><span class="add">Explore →</span></div>
        </a>`).join('');
    }
    return data;
  }

  /* ---------------- products: Shop All grid, Bestsellers ring, New This Week ---------------- */
  async function loadProducts(){
    if(!db) return;
    const { data, error } = await db.from('products')
      .select('*, categories(slug), product_images(face,url)')
      .eq('is_active',true).order('sort_order');
    if(error || !data || !data.length) return;

    const faceUrl=(p,face)=> (p.product_images||[]).find(i=>i.face===face)?.url || '';

    // Shop All grid (#plpGrid) — 3D cuboid cards
    const grid = document.querySelector('#plpGrid');
    if(grid){
      grid.innerHTML = data.map(p=>`
        <article class="plp-card" data-category="${p.categories?.slug||''}">
          <div class="cuboid-stage">
            <button class="wish-btn" aria-label="Add to wishlist">♡</button>
            ${p.required_tier?`<span class="discount-tag" style="background:var(--bronze);color:#0b0a08">${p.required_tier} exclusive</span>`:(p.badge?`<span class="discount-tag">${p.badge}</span>`:(p.compare_at_price?`<span class="discount-tag">-${Math.round((1-p.price/p.compare_at_price)*100)}%</span>`:''))}
            <div class="cuboid" data-rot="0">
              <div class="cube-face front"><img src="${faceUrl(p,'front')}"></div>
              <div class="cube-face right"><img src="${faceUrl(p,'right')||faceUrl(p,'front')}"></div>
              <div class="cube-face back"><img src="${faceUrl(p,'back')||faceUrl(p,'front')}"></div>
              <div class="cube-face left price-face"><div class="price-face-inner">
                <b>${p.is_custom_order?'From ':''}${money(p.price)}</b><span>${p.name}</span>
                <button class="add quick-add">Quick add</button>
              </div></div>
            </div>
            <button class="cube-nav prev" aria-label="Rotate left">‹</button>
            <button class="cube-nav next" aria-label="Rotate right">›</button>
          </div>
          <div class="plp-copy"><h4>${p.name}</h4>
            <div class="plp-price"><b>${p.is_custom_order?'From ':''}${money(p.price)}</b>${p.compare_at_price?`<s>${money(p.compare_at_price)}</s>`:''}</div>
          </div>
        </article>`).join('');
      const countEl=document.querySelector('#plpCount'); if(countEl) countEl.textContent=data.length;
    }

    // Bestsellers ring (#productRing)
    const bestsellers = data.filter(p=>p.is_bestseller);
    const productRing = document.querySelector('#productRing');
    if(productRing && bestsellers.length){
      productRing.innerHTML = bestsellers.map(p=>`
        <article class="ring-item pcard"><div class="pimg">${p.badge?`<div class="tag">${p.badge}</div>`:''}<img src="${faceUrl(p,'front')}"></div>
          <div class="pcopy"><h3>${p.name}</h3><p>${money(p.price)}</p><button class="add">Add to bag</button></div>
        </article>`).join('');
    }

    // New This Week coverflow (#coverflowTrack + #cfDots)
    const newItems = data.filter(p=>p.is_new_this_week);
    const cfTrack = document.querySelector('#coverflowTrack');
    if(cfTrack && newItems.length){
      cfTrack.innerHTML = newItems.map(p=>`
        <div class="cf-item"><img src="${faceUrl(p,'front')}" alt="${p.name}">
          <div class="cf-cap"><h3>${p.name}</h3><p>${money(p.price)}</p></div>
        </div>`).join('');
      const dots=document.querySelector('#cfDots');
      if(dots) dots.innerHTML = newItems.map(()=>'<span></span>').join('');
    }
    return data;
  }

  /* ---------------- hero slides ---------------- */
  async function loadHeroSlides(){
    if(!db) return;
    const { data, error } = await db.from('hero_slides').select('*').eq('is_active',true).order('sort_order');
    if(error || !data || !data.length) return;

    const stage = document.querySelector('.hero-stage');
    if(!stage) return;
    const mediaTag = s => (s.media_type==='video' && s.video_url)
      ? `<video autoplay muted loop playsinline poster="${s.image_url||''}" style="width:100%;height:100%;object-fit:cover;filter:saturate(.7) contrast(1.05)"><source src="${s.video_url}"></video>`
      : `<img src="${s.image_url}" alt="${(s.heading||'').replace(/"/g,'')}">`;
    const slides = data.map((s,i)=>`
      <div class="hero-slide${i===0?' active':''}">
        ${mediaTag(s)}
        <div class="hero-overlay"></div>
        <div class="hero-content">
          ${s.eyebrow?`<p class="eyebrow">${s.eyebrow}</p>`:''}
          <h1>${s.heading}${s.heading_em?` <em>${s.heading_em}</em>`:''}</h1>
          ${s.subtext?`<p>${s.subtext}</p>`:''}
          <a class="btn ${s.button_style==='wine'?'wine':'light'} magnetic" href="${s.cta_link}">${s.cta_label}</a>
        </div>
        ${s.side_note?`<div class="hero-side-note">${s.side_note}${s.side_note_sub?`<br><small>${s.side_note_sub}</small>`:''}</div>`:''}
      </div>`).join('');
    // keep existing arrows / progress dots / rail, just swap the slides themselves
    const oldSlides = stage.querySelectorAll('.hero-slide');
    oldSlides.forEach(el=>el.remove());
    stage.insertAdjacentHTML('afterbegin', slides);

    const progress = stage.querySelector('.hero-progress');
    if(progress) progress.innerHTML = data.map((_,i)=>`<span class="${i===0?'active':''}"></span>`).join('');
    return data;
  }

  /* ---------------- testimonials ---------------- */
  async function loadTestimonials(){
    if(!db) return;
    const { data, error } = await db.from('testimonials').select('*').eq('is_active',true).order('sort_order');
    if(error || !data || !data.length) return;
    const stage = document.querySelector('#stackStage');
    if(!stage) return;
    stage.innerHTML = data.map(t=>`
      <div class="stack-card"><div class="quote-mark">"</div><p>${t.quote}</p>
        <b>${t.author_name}</b>${t.author_location?`<small>${t.author_location}</small>`:''}
      </div>`).join('');
    return data;
  }

  /* ---------------- settings: announcement bar text ---------------- */
  async function loadSettings(){
    if(!db) return;
    const { data, error } = await db.from('site_settings').select('*');
    if(error || !data) return;
    const settings = Object.fromEntries(data.map(s=>[s.key, s.value]));
    if(settings.announcement){
      const bar = document.querySelector('.announcement');
      if(bar){
        const arrow = bar.querySelector('b');
        bar.childNodes[0].nodeValue = settings.announcement + ' ';
        if(!arrow){ bar.insertAdjacentHTML('beforeend','<b>→</b>'); }
      }
    }
    // NGN rate: your currency script keeps CURRENCIES as a top-level `const`, which
    // isn't reachable from this file. Easiest fix — in your script, change:
    //   const CURRENCIES = {...}   →   window.CURRENCIES = {...}
    // then this line below will pick up the CMS-configured rate automatically.
    if(settings.ngn_rate && window.CURRENCIES && window.CURRENCIES.NGN){
      window.CURRENCIES.NGN.rate = Number(settings.ngn_rate);
      if(typeof window.renderMoney==='function') window.renderMoney();
    }
    return settings;
  }

  /* ---------------- newsletter: wire the existing form to actually store emails ---------------- */
  function wireNewsletter(){
    if(!db) return;
    const form = document.querySelector('.newsletter form');
    if(!form || form.dataset.cmsWired) return;
    form.dataset.cmsWired = '1';
    form.addEventListener('submit', async ()=>{
      const email = form.querySelector('input[type="email"]')?.value;
      if(email) await db.from('newsletter_subscribers').insert({ email }).select();
      // your existing onsubmit="return subscribe(event)" still runs and shows the toast
    });
  }

  async function init(){
    if(!db){ console.info('[ALUQE CMS] Supabase not configured — showing static demo content.'); return; }
    await Promise.allSettled([
      loadCategories(),
      loadProducts(),
      loadHeroSlides(),
      loadTestimonials(),
      loadSettings(),
    ]);
    wireNewsletter();
  }

  return { init, db: ()=>db };
})();
