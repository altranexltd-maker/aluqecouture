-- =====================================================================
-- ALUQE COUTURE — SUPABASE CMS SCHEMA
-- Run this in your Supabase project: Dashboard → SQL Editor → New query
-- Safe to re-run: uses IF NOT EXISTS / CREATE OR REPLACE throughout.
-- =====================================================================

create extension if not exists "uuid-ossp";

-- =====================================================================
-- 1. PROFILES  (extends auth.users — every signed-up user gets a row)
-- =====================================================================
create table if not exists profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  role        text not null default 'customer' check (role in ('customer','admin')),
  created_at  timestamptz not null default now()
);

-- auto-create a profile row whenever someone signs up
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- helper used by every RLS policy below
create or replace function is_admin()
returns boolean as $$
  select exists (
    select 1 from profiles where id = auth.uid() and role = 'admin'
  );
$$ language sql security definer stable;

-- =====================================================================
-- 2. CATEGORIES  (drives the category menu bar + "Shop by mood" ring)
-- =====================================================================
create table if not exists categories (
  id          uuid primary key default uuid_generate_v4(),
  slug        text unique not null,          -- e.g. 'tops', matches data-filter
  name        text not null,                  -- e.g. 'Tops'
  image_url   text,                           -- avatar/ring image
  is_sale     boolean not null default false, -- true for the 'Sale' chip
  sort_order  int not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- =====================================================================
-- 3. PRODUCTS  (drives Shop All grid, Bestsellers ring, New This Week)
-- =====================================================================
create table if not exists products (
  id                  uuid primary key default uuid_generate_v4(),
  slug                text unique not null,
  name                text not null,
  description         text,
  price               numeric(10,2) not null,
  compare_at_price    numeric(10,2),                 -- shown struck-through when set
  category_id         uuid references categories(id) on delete set null,
  badge               text,                           -- 'New' / 'Limited' / 'Custom' / null
  is_bestseller       boolean not null default false, -- shows in the Bestsellers ring
  is_new_this_week    boolean not null default false, -- shows in the coverflow
  is_custom_order     boolean not null default false, -- "From $x" pricing style
  stock               int not null default 0,
  is_active           boolean not null default true,
  sort_order          int not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- up to 3 photo faces per product (front / right / back of the 3D cuboid thumbnail);
-- the 4th ("price") face is generated client-side from name + price, no image needed
create table if not exists product_images (
  id          uuid primary key default uuid_generate_v4(),
  product_id  uuid not null references products(id) on delete cascade,
  face        text not null check (face in ('front','right','back')),
  url         text not null,
  unique (product_id, face)
);

-- =====================================================================
-- 4. HERO SLIDES  (the 3-slide cinematic hero at the top of the page)
-- =====================================================================
create table if not exists hero_slides (
  id            uuid primary key default uuid_generate_v4(),
  eyebrow       text,
  heading       text not null,      -- plain part, e.g. "The new\npower"
  heading_em    text,               -- italic/bronze part, e.g. "dressing"
  subtext       text,
  image_url     text not null,
  cta_label     text not null default 'Shop now',
  cta_link      text not null default '#shop',
  button_style  text not null default 'light' check (button_style in ('light','wine')),
  side_note     text,               -- e.g. "City / 06:40 PM"
  side_note_sub text,               -- e.g. "The Aluqe Couture woman"
  sort_order    int not null default 0,
  is_active     boolean not null default true
);

-- =====================================================================
-- 5. SHOP THE LOOK  (one interactive editorial look, with hotspots)
-- =====================================================================
create table if not exists looks (
  id          uuid primary key default uuid_generate_v4(),
  title       text not null default 'The Power Edit',
  image_url   text not null,
  is_active   boolean not null default true
);

create table if not exists look_items (
  id          uuid primary key default uuid_generate_v4(),
  look_id     uuid not null references looks(id) on delete cascade,
  product_id  uuid not null references products(id) on delete cascade,
  hotspot_x   numeric(5,2) not null,   -- percentage, e.g. 47.00
  hotspot_y   numeric(5,2) not null,
  sort_order  int not null default 0
);

-- =====================================================================
-- 6. TESTIMONIALS  ("In Her Words" stacked-deck carousel)
-- =====================================================================
create table if not exists testimonials (
  id              uuid primary key default uuid_generate_v4(),
  quote           text not null,
  author_name     text not null,
  author_location text,
  sort_order      int not null default 0,
  is_active       boolean not null default true
);

-- =====================================================================
-- 7. NEWSLETTER SIGNUPS
-- =====================================================================
create table if not exists newsletter_subscribers (
  id          uuid primary key default uuid_generate_v4(),
  email       text unique not null,
  created_at  timestamptz not null default now()
);

-- =====================================================================
-- 8. SITE SETTINGS  (announcement bar text, NGN rate, free-shipping copy…)
-- =====================================================================
create table if not exists site_settings (
  key         text primary key,
  value       jsonb not null
);

-- =====================================================================
-- 9. WISHLISTS  &  ORDERS  (scaffold for the account/profile features)
-- =====================================================================
create table if not exists wishlists (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references profiles(id) on delete cascade,
  product_id  uuid not null references products(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (user_id, product_id)
);

create table if not exists orders (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid references profiles(id) on delete set null,
  status      text not null default 'pending' check (status in ('pending','paid','fulfilled','cancelled')),
  currency    text not null default 'USD',
  total       numeric(10,2) not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists order_items (
  id          uuid primary key default uuid_generate_v4(),
  order_id    uuid not null references orders(id) on delete cascade,
  product_id  uuid references products(id) on delete set null,
  quantity    int not null default 1,
  unit_price  numeric(10,2) not null
);

-- =====================================================================
-- 10. ROW LEVEL SECURITY
-- =====================================================================
alter table profiles               enable row level security;
alter table categories             enable row level security;
alter table products               enable row level security;
alter table product_images         enable row level security;
alter table hero_slides            enable row level security;
alter table looks                  enable row level security;
alter table look_items             enable row level security;
alter table testimonials           enable row level security;
alter table newsletter_subscribers enable row level security;
alter table site_settings          enable row level security;
alter table wishlists              enable row level security;
alter table orders                 enable row level security;
alter table order_items            enable row level security;

-- profiles: users see/edit their own row; admins see everyone
drop policy if exists "profiles_select_own_or_admin" on profiles;
create policy "profiles_select_own_or_admin" on profiles for select
  using (id = auth.uid() or is_admin());
drop policy if exists "profiles_update_own" on profiles;
create policy "profiles_update_own" on profiles for update
  using (id = auth.uid());

-- public read on storefront content, admin-only writes — repeated per table
drop policy if exists "categories_public_read" on categories;
create policy "categories_public_read" on categories for select using (is_active or is_admin());
drop policy if exists "categories_admin_write" on categories;
create policy "categories_admin_write" on categories for all using (is_admin()) with check (is_admin());

drop policy if exists "products_public_read" on products;
create policy "products_public_read" on products for select using (is_active or is_admin());
drop policy if exists "products_admin_write" on products;
create policy "products_admin_write" on products for all using (is_admin()) with check (is_admin());

drop policy if exists "product_images_public_read" on product_images;
create policy "product_images_public_read" on product_images for select using (true);
drop policy if exists "product_images_admin_write" on product_images;
create policy "product_images_admin_write" on product_images for all using (is_admin()) with check (is_admin());

drop policy if exists "hero_slides_public_read" on hero_slides;
create policy "hero_slides_public_read" on hero_slides for select using (is_active or is_admin());
drop policy if exists "hero_slides_admin_write" on hero_slides;
create policy "hero_slides_admin_write" on hero_slides for all using (is_admin()) with check (is_admin());

drop policy if exists "looks_public_read" on looks;
create policy "looks_public_read" on looks for select using (is_active or is_admin());
drop policy if exists "looks_admin_write" on looks;
create policy "looks_admin_write" on looks for all using (is_admin()) with check (is_admin());

drop policy if exists "look_items_public_read" on look_items;
create policy "look_items_public_read" on look_items for select using (true);
drop policy if exists "look_items_admin_write" on look_items;
create policy "look_items_admin_write" on look_items for all using (is_admin()) with check (is_admin());

drop policy if exists "testimonials_public_read" on testimonials;
create policy "testimonials_public_read" on testimonials for select using (is_active or is_admin());
drop policy if exists "testimonials_admin_write" on testimonials;
create policy "testimonials_admin_write" on testimonials for all using (is_admin()) with check (is_admin());

-- newsletter: anyone can sign up, only admins can read the list
drop policy if exists "newsletter_public_insert" on newsletter_subscribers;
create policy "newsletter_public_insert" on newsletter_subscribers for insert with check (true);
drop policy if exists "newsletter_admin_read" on newsletter_subscribers;
create policy "newsletter_admin_read" on newsletter_subscribers for select using (is_admin());

drop policy if exists "settings_public_read" on site_settings;
create policy "settings_public_read" on site_settings for select using (true);
drop policy if exists "settings_admin_write" on site_settings;
create policy "settings_admin_write" on site_settings for all using (is_admin()) with check (is_admin());

-- wishlists: a user only ever sees/edits their own
drop policy if exists "wishlists_own" on wishlists;
create policy "wishlists_own" on wishlists for all
  using (user_id = auth.uid() or is_admin())
  with check (user_id = auth.uid());

-- orders: a user sees their own orders; admins see all
drop policy if exists "orders_select" on orders;
create policy "orders_select" on orders for select using (user_id = auth.uid() or is_admin());
drop policy if exists "orders_insert_own" on orders;
create policy "orders_insert_own" on orders for insert with check (user_id = auth.uid());
drop policy if exists "orders_admin_update" on orders;
create policy "orders_admin_update" on orders for update using (is_admin());

drop policy if exists "order_items_select" on order_items;
create policy "order_items_select" on order_items for select using (
  exists (select 1 from orders o where o.id = order_id and (o.user_id = auth.uid() or is_admin()))
);
drop policy if exists "order_items_insert_own" on order_items;
create policy "order_items_insert_own" on order_items for insert with check (
  exists (select 1 from orders o where o.id = order_id and o.user_id = auth.uid())
);

-- =====================================================================
-- 11. STORAGE — bucket for product / hero / look imagery
-- Create the bucket first: Dashboard → Storage → New bucket → "media" → Public
-- Then run this so anyone can view images but only admins can upload/replace/delete.
-- =====================================================================
drop policy if exists "media_public_read" on storage.objects;
create policy "media_public_read" on storage.objects for select
  using (bucket_id = 'media');

drop policy if exists "media_admin_write" on storage.objects;
create policy "media_admin_write" on storage.objects for insert
  with check (bucket_id = 'media' and is_admin());

drop policy if exists "media_admin_update" on storage.objects;
create policy "media_admin_update" on storage.objects for update
  using (bucket_id = 'media' and is_admin());

drop policy if exists "media_admin_delete" on storage.objects;
create policy "media_admin_delete" on storage.objects for delete
  using (bucket_id = 'media' and is_admin());

-- =====================================================================
-- 12. SEED DATA — mirrors what's already live on the storefront today,
-- so switching it over to Supabase doesn't change anything visually.
-- =====================================================================
insert into categories (slug,name,is_sale,sort_order,image_url) values
  ('tops','Tops',false,1,'https://images.unsplash.com/photo-1551803091-e20673f15770?auto=format&fit=crop&w=200&q=80'),
  ('denim','Denim',false,2,'https://images.unsplash.com/photo-1541099649105-f69ad21f3246?auto=format&fit=crop&w=200&q=80'),
  ('gowns','Gowns',false,3,'https://images.unsplash.com/photo-1566174053879-31528523f8ae?auto=format&fit=crop&w=200&q=80'),
  ('pants','Pants',false,4,'https://images.unsplash.com/photo-1495385794356-15371f348c31?auto=format&fit=crop&w=200&q=80'),
  ('skirts','Skirts',false,5,'https://images.unsplash.com/photo-1583496661160-fb5886a13d05?auto=format&fit=crop&w=200&q=80'),
  ('leather','Leather',false,6,'https://images.unsplash.com/photo-1551028719-00167b16eac5?auto=format&fit=crop&w=200&q=80'),
  ('accessories','Accessories',false,7,'https://images.unsplash.com/photo-1612902456551-333ac5afa26e?auto=format&fit=crop&w=200&q=80'),
  ('outfits','Full Outfits',false,8,'https://images.unsplash.com/photo-1539109136881-3be0616acf4b?auto=format&fit=crop&w=200&q=80'),
  ('custom','Custom',false,9,'https://images.unsplash.com/photo-1490481651871-ab68de25d43d?auto=format&fit=crop&w=200&q=80'),
  ('sale','Sale',true,10,null)
on conflict (slug) do nothing;

insert into site_settings (key,value) values
  ('announcement', '"FREE SHIPPING ON ORDERS OVER $75"'),
  ('ngn_rate', '1550'),
  ('brand_name', '"Aluqe Couture"')
on conflict (key) do nothing;

insert into testimonials (quote,author_name,author_location,sort_order) values
  ('The tailoring on the blazer is unreal — it fit like it was made for me straight off the rack.','Amara','Lagos',1),
  ('I get stopped constantly in the Statement collection. Worth every kobo.','Jade','London',2),
  ('Fast shipping, gorgeous packaging, and the leather pants are now in permanent rotation.','Precious','Port Harcourt',3),
  ('Quiet Luxury is the perfect name — understated but everyone notices.','Simone','Accra',4)
on conflict do nothing;

-- one sample product per category so the grid isn't empty on first load
insert into products (slug,name,description,price,compare_at_price,category_id,badge,is_bestseller,is_new_this_week,sort_order)
select 'satin-cami-top','Satin Cami Top','A fluid satin cami cut for effortless layering.',24.00,32.00,id,null,false,true,1 from categories where slug='tops'
on conflict (slug) do nothing;
insert into products (slug,name,description,price,category_id,is_bestseller,sort_order)
select 'wide-leg-denim','Wide-Leg Denim','High-rise wide-leg denim with a clean, long line.',38.00,id,false,2 from categories where slug='denim'
on conflict (slug) do nothing;
insert into products (slug,name,description,price,compare_at_price,category_id,sort_order)
select 'sequin-evening-gown','Sequin Evening Gown','Hand-finished sequin gown for the moment everyone remembers.',95.00,140.00,id,3 from categories where slug='gowns'
on conflict (slug) do nothing;
insert into products (slug,name,description,price,category_id,is_bestseller,sort_order)
select 'leather-flare-pants','Leather Flare Pants','High-rise leather trousers with a long, clean line.',49.00,id,true,4 from categories where slug='pants'
on conflict (slug) do nothing;
insert into products (slug,name,description,price,category_id,sort_order)
select 'pleated-midi-skirt','Pleated Midi Skirt','A satin pleated skirt that moves with you.',34.00,id,5 from categories where slug='skirts'
on conflict (slug) do nothing;
insert into products (slug,name,description,price,category_id,badge,sort_order)
select 'leather-biker-jacket','Leather Biker Jacket','Structured leather with polished hardware.',89.00,id,'New',6 from categories where slug='leather'
on conflict (slug) do nothing;
insert into products (slug,name,description,price,category_id,sort_order)
select 'gold-chain-belt','Gold Chain Belt','A compact statement belt with polished hardware.',28.00,id,7 from categories where slug='accessories'
on conflict (slug) do nothing;
insert into products (slug,name,description,price,compare_at_price,category_id,is_bestseller,sort_order)
select 'power-suit-set','The Power Suit Set','A cropped blazer and trouser set, cut for structure.',110.00,130.00,id,true,8 from categories where slug='outfits'
on conflict (slug) do nothing;
insert into products (slug,name,description,price,category_id,badge,is_custom_order,sort_order)
select 'made-to-measure-blazer','Made-to-Measure Blazer','Built to your measurements, from consultation to fitting.',75.00,id,'Custom',true,9 from categories where slug='custom'
on conflict (slug) do nothing;

-- =====================================================================
-- Done. Next: create the 'media' storage bucket (public), then promote
-- your own account to admin — see README-CMS.md for both steps.
-- =====================================================================


-- =====================================================================
-- 13. MEMBERSHIP TIERS + VIDEO SUPPORT  (run this after everything above)
-- Safe to re-run: every statement below is additive / idempotent.
-- =====================================================================

-- ---- profiles: email (so admins can see who they're looking at) + tier ----
alter table profiles add column if not exists email text;
alter table profiles add column if not exists membership_tier text not null default 'none'
  check (membership_tier in ('none','silver','gold','diamond'));

-- keep email populated on new sign-ups too
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, new.raw_user_meta_data->>'full_name', new.email);
  return new;
end;
$$ language plpgsql security definer;

-- backfill email for any accounts created before this column existed
update profiles p set email = u.email
from auth.users u where u.id = p.id and p.email is null;

-- admins can now update ANY profile (needed to set a client's tier from the CMS)
drop policy if exists "profiles_admin_update_any" on profiles;
create policy "profiles_admin_update_any" on profiles for update
  using (is_admin()) with check (is_admin());

-- ---- tier ranking, used to decide who can see a tier-locked product ----
create or replace function tier_rank(t text)
returns int as $$
  select case t
    when 'silver' then 1
    when 'gold' then 2
    when 'diamond' then 3
    else 0
  end;
$$ language sql immutable;

create or replace function can_view_tier(required text)
returns boolean as $$
  select required is null
    or is_admin()
    or exists (
      select 1 from profiles
      where id = auth.uid() and tier_rank(membership_tier) >= tier_rank(required)
    );
$$ language sql security definer stable;

-- ---- products: optional tier gate + optional video ----
alter table products add column if not exists required_tier text
  check (required_tier in ('silver','gold','diamond'));
alter table products add column if not exists video_url text;

-- replace the public-read policy so a tier-locked product is invisible
-- to anyone who doesn't qualify (enforced in the database, not just the UI)
drop policy if exists "products_public_read" on products;
create policy "products_public_read" on products for select
  using ((is_active and can_view_tier(required_tier)) or is_admin());

-- ---- hero slides: image OR video background ----
alter table hero_slides add column if not exists media_type text not null default 'image'
  check (media_type in ('image','video'));
alter table hero_slides add column if not exists video_url text;

-- =====================================================================
-- Storage note: videos go in the same 'media' bucket — no new bucket or
-- policy needed. Supabase's default per-file upload limit is 50MB; raise
-- it under Dashboard → Storage → Settings if a video is rejected.
-- =====================================================================

