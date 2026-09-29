# Aluqe Couture — Supabase CMS setup

> **This round added:** video uploads (hero background videos + an optional product video), a sticky admin sidebar, a full client/membership system (`account.html` — sign-up, sign-in, "forgot password"), a new **Clients** tab in the admin panel to set each customer's membership tier, and tier-gated products (**Silver / Gold / Diamond**) that are invisible in the database itself to anyone who doesn't qualify — not just hidden in the UI.
>
> **You need to re-run `schema.sql` in the Supabase SQL Editor** to pick up the new tables/columns (it's additive and safe to run again — it won't touch your existing data).

Five files here now:

- **`schema.sql`** — every table, security rule, and starter data. Re-run this even if you ran it before; the new tier/video parts are appended at the bottom.
- **`admin.html`** — your day-to-day CMS: Products, Categories, Hero Slides, Testimonials, **Clients**, Newsletter, Settings.
- **`account.html`** — the customer-facing side: sign up, sign in, and a dashboard showing their membership tier and exclusive collection.
- **`cms-client.js`** — the loader that makes `index.html` pull its content from Supabase.
- **`index.html`** — your storefront, with the header/bottom-tab "Account" button now linking to `account.html`.

## 1. Create the Supabase project

1. Go to [supabase.com](https://supabase.com) → New project. Pick any name/region, save the database password somewhere safe.
2. Once it's ready, open **SQL Editor → New query**, paste the entire contents of `schema.sql`, and run it. This creates every table, security rule, and the starter products/categories/testimonials that match what's already on the site.

## 2. Create the image bucket

1. **Storage → New bucket** → name it exactly `media` → toggle **Public bucket** on → Create.
2. That's it — the storage security rules for it were already created by `schema.sql` (public can view, only admins can upload).

## 3. Create your admin account

1. **Authentication → Users → Add user** (or just sign up through your own app later) — use your real email + a password.
2. Copy that user's **UID** (shown in the Users table).
3. Back in **SQL Editor**, run:
   ```sql
   update profiles set role = 'admin' where id = 'paste-the-uid-here';
   ```
   Every new sign-up gets a `profiles` row automatically (with `role = 'customer'`) — this line just promotes yours.

## 4. Get your API keys

**Project Settings → API**. You need two values:
- **Project URL** (looks like `https://xxxxx.supabase.co`)
- **anon public** key (a long string — this is safe to put in client-side code, it's not a secret; the RLS rules from `schema.sql` are what actually protects your data)

## 5. Configure the two files

Open `admin.html` and `cms-client.js`, and near the top of each you'll find:
```js
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';
```
Paste in your real values in both files.

## 6. Open the admin panel

Open `admin.html` in a browser, sign in with the account you promoted in step 3. You'll see Products, Categories, Hero Slides, Testimonials, Newsletter, and Settings — all editable, with image upload built in for products (front / right / back faces of the 3D cuboid thumbnail — the fourth "price" face is generated automatically from the name and price, no image needed there).

## 7. The live storefront is already wired to it

Your `index.html` carousels (`RingCarousel`, `CoverflowCarousel`, `AutoSlider`, `StackCarousel`) all read the DOM the instant they're constructed, so the CMS data has to be in place *before* that code runs. Here's what's actually in your file now:

- The supabase-js CDN script and `cms-client.js` are loaded right before your inline `<script>` block.
- Everything that touches page content — the currency tagging, the custom cursor, magnetic buttons, the hero slider, and every carousel — now lives inside one function, `initInteractive()`, instead of running the instant the script loads.
- `showToast`, `addToBag`, and `subscribe` stay defined at the top level (outside that function) on purpose — your HTML calls them directly via `onclick`/`onsubmit`, so they have to stay reachable as plain global functions.
- At the very end of the script: `ALUQE_CMS.init().finally(initInteractive)` — this fetches everything from Supabase first (or fails silently and falls back to the static HTML), fills in the DOM, and only *then* builds the carousels and binds every click handler on top of the final content. If Supabase is unreachable, `initInteractive()` still runs against whatever static content shipped in the file, so the site never breaks.
- `CURRENCIES` is declared as `window.CURRENCIES` so the admin panel's Settings tab can change the live USD→NGN rate without a code deploy.

One thing to know: your "Shop the Look" section still uses its own hardcoded `lookProducts` object — that wasn't wired to Supabase in this pass (the schema has `looks`/`look_items` tables ready for it whenever you want that done too).

## Video uploads

Yes — the same `media` storage bucket takes any file type, videos included. Two places now use it:

- **Hero Slides**: each slide has a "Background type" dropdown (Image / Video). Pick Video and a file-upload field appears — upload an MP4, and it autoplays, muted and looped, behind that slide. The Image URL field doubles as the poster frame while the video loads.
- **Products**: an optional video upload per product, stored on `products.video_url`. Nothing on the storefront displays it yet — it's there for when you decide how you want product video shown (e.g. a fourth cuboid face, or a hover-preview).

One limit to know: Supabase's default per-file upload cap is 50MB. If a video gets rejected, either compress it first or raise the limit under **Storage → Settings** in the dashboard.

## The client dashboard (`account.html`)

This is the customer-facing counterpart to `admin.html` — sign up, sign in, "forgot password", and a dashboard showing their name, email, membership tier, and their **Exclusive Collection**. It uses Supabase Auth directly, the same auth system `admin.html` uses for you.

Your project almost certainly has **email confirmation** on by default — a new customer won't get a session until they click the link in their confirmation email. `account.html` already handles this: after sign-up it tells them to check their email rather than silently failing.

The storefront's header and mobile-tab "Account" buttons now link straight to `account.html` instead of showing the old "coming soon" toast.

## Membership tiers: Silver, Gold, Diamond

Every account has a `membership_tier` on their profile: `none`, `silver`, `gold`, or `diamond` (ranked in that order — Diamond sees everything Gold and Silver see, and so on). You set a client's tier from the new **Clients** tab in `admin.html` — there's no self-serve upgrade flow; that's a deliberate choice so a real person decides who gets access, which matches how a made-to-order fashion house usually runs memberships.

To make a product exclusive: open it in the Products tab and set **Required tier**. That's the whole workflow on your end.

**Why this is actually secure, not just hidden in the UI:** the restriction lives in the database's row-level security, not in JavaScript. A tier-locked product is invisible to a query from anyone who doesn't qualify — full stop, at the Postgres level. Someone opening dev tools and reading the storefront's source code, or hitting the Supabase API directly with the public anon key, still can't retrieve a product they're not entitled to. Only a logged-in account whose tier meets or exceeds the product's `required_tier` (or an admin) will ever have that row returned to them. This is exactly the same mechanism that already protects Shop All from showing inactive/draft products — I extended it rather than bolting on something separate.

Practically: `index.html`'s Shop All grid already picks up qualifying exclusive products automatically for a logged-in visitor (no code change needed there), and `account.html`'s "Your Exclusive Collection" section shows the same thing in one place. A visitor with no tier, or who isn't logged in, sees a normal storefront and nothing exclusive — not a locked padlock icon, just nothing, because the row was never sent to their browser to begin with.

## What's already in the database (from the seed data)

- All 9 categories (Tops, Denim, Gowns, Pants, Skirts, Leather, Accessories, Full Outfits, Custom) + the Sale filter.
- One starter product per category, matching what's live now.
- All 4 existing testimonials.
- Announcement bar text and the NGN exchange rate, editable from Settings.

Everything else (hero slides, "Shop the Look" hotspots, the rest of the product catalogue, and every client's tier) you set yourself from `admin.html` — that's the point of the CMS.

## What's still not wired up (known gaps, not bugs)

- **"Shop the Look"** still runs on its own hardcoded `lookProducts` object in `index.html` — never connected to the `looks`/`look_items` tables in the schema.
- **Checkout / payment** doesn't exist yet. `orders`/`order_items` are scaffolded and RLS-protected, but nothing creates an order today — "Add to bag" is still a local counter with no persistence.
- **Wishlist** is a client-side heart toggle only; it doesn't save to the `wishlists` table yet, so it resets on refresh. The table and its security rules are ready whenever you want that made real.

