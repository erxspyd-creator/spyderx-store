-- =====================================================================
-- 01_schema.sql : الجداول والقيود فقط (آمن لإعادة التشغيل)
-- شغّله أولا. لا يحتوي بيانات ولا دوال ولا صلاحيات.
-- =====================================================================

create table if not exists admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- ---------- الكتالوج ----------
create table if not exists categories (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null, name_fr text, name_en text,
  sort int not null default 0, active boolean not null default true
);

create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  name_ar text not null, name_fr text, name_en text,
  desc_ar text, desc_fr text, desc_en text, features text,
  category_id uuid references categories(id) on delete set null,
  brand text,
  price_original numeric(12,2) check (price_original is null or price_original >= 0),
  price_sale numeric(12,2) not null check (price_sale >= 0),
  price_discount numeric(12,2) check (price_discount is null or price_discount >= 0),
  badge text check (badge in ('NEW','SALE','BEST SELLER')),
  featured boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint discount_not_above_sale check (price_discount is null or price_discount <= price_sale)
);

-- التكلفة في جدول منفصل: لا يقرؤه الزوار إطلاقا
create table if not exists product_costs (
  product_id uuid primary key references products(id) on delete cascade,
  cost numeric(12,2) not null default 0 check (cost >= 0)
);

create table if not exists product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  url text not null, is_main boolean not null default false, sort int not null default 0
);
create unique index if not exists one_main_image on product_images(product_id) where is_main;

create table if not exists product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  color text not null, color_hex text, color_image_url text,
  size text not null,
  stock int not null default 0 check (stock >= 0),
  low_stock_threshold int not null default 3 check (low_stock_threshold >= 0),
  active boolean not null default true,
  unique (product_id, color, size)
);
create index if not exists variants_product_idx on product_variants(product_id);

create table if not exists stock_movements (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid references product_variants(id) on delete set null,
  delta int not null,
  reason text not null check (reason in
    ('initial','purchase','sale','return','damaged','inventory_count','manual','order_cancelled')),
  order_id uuid, note text,
  created_by uuid, created_at timestamptz not null default now()
);
create index if not exists movements_variant_idx on stock_movements(variant_id, created_at);

-- ---------- الجزائر والتوصيل ----------
create table if not exists wilayas (
  code int primary key check (code between 1 and 99),
  name_ar text not null, name_fr text not null
);
create table if not exists communes (
  id serial primary key,
  source_id int,
  wilaya_code int not null references wilayas(code),
  name_ar text, name_fr text,
  check (name_ar is not null or name_fr is not null)
);
create unique index if not exists communes_source_id_uq on communes(source_id);
create index if not exists communes_wilaya_idx on communes(wilaya_code);

create table if not exists delivery_companies (
  id uuid primary key default gen_random_uuid(),
  name text not null, active boolean not null default true, is_default boolean not null default false
);
create unique index if not exists one_default_company on delivery_companies(is_default) where is_default;

-- السعر null = غير محدد = لا يمكن الطلب. تدخل الأسعار بنفسك من لوحة الإدارة.
create table if not exists delivery_rates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references delivery_companies(id) on delete cascade,
  wilaya_code int not null references wilayas(code),
  home_price numeric(10,2) check (home_price is null or home_price >= 0),
  desk_price numeric(10,2) check (desk_price is null or desk_price >= 0),
  home_enabled boolean not null default true,
  desk_enabled boolean not null default true,
  unique (company_id, wilaya_code)
);
create index if not exists rates_wilaya_idx on delivery_rates(wilaya_code);

-- ---------- الخصومات والإعدادات ----------
create table if not exists coupons (
  code text primary key,
  kind text not null check (kind in ('percent','fixed')),
  value numeric(10,2) not null check (value > 0),
  min_order numeric(12,2) not null default 0 check (min_order >= 0),
  max_uses int check (max_uses is null or max_uses > 0),                 -- الحد الإجمالي
  used_count int not null default 0 check (used_count >= 0),
  max_per_phone int check (max_per_phone is null or max_per_phone > 0),  -- الحد لكل رقم هاتف
  starts_at timestamptz, ends_at timestamptz,
  active boolean not null default true,
  constraint coupon_code_fmt check (code = upper(code) and char_length(code) between 3 and 32),
  constraint coupon_pct_max check (kind <> 'percent' or value <= 100),
  constraint coupon_dates check (starts_at is null or ends_at is null or ends_at > starts_at)
);
-- إن وُجدت صفوف هنا فالكوبون يخص هذه المنتجات فقط
create table if not exists coupon_products (
  code text not null references coupons(code) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  primary key (code, product_id)
);

create table if not exists settings (key text primary key, value jsonb);
insert into settings(key, value) values ('whatsapp','""'), ('instagram','""'), ('store_name','""')
  on conflict (key) do nothing;

-- ---------- الطلبات ----------
create sequence if not exists order_seq start 1000;

create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  order_no text unique not null default ('ORD-' || nextval('order_seq')),
  status text not null default 'new' check (status in
    ('new','pending_confirmation','confirmed','preparing','packed',
     'sent_to_courier','out_for_delivery','delivered','cancelled','returned')),
  customer_name text not null check (char_length(customer_name) between 3 and 80),
  phone text not null check (phone ~ '^0[567][0-9]{8}$'),
  phone2 text check (phone2 is null or phone2 ~ '^0[567][0-9]{8}$'),
  wilaya_code int not null references wilayas(code),
  commune_id int references communes(id),
  commune text not null,
  address text check (address is null or char_length(address) <= 250),
  delivery_type text not null check (delivery_type in ('home','stop_desk')),
  company_id uuid references delivery_companies(id),
  tracking_no text check (tracking_no is null or char_length(tracking_no) <= 64),
  subtotal numeric(12,2) not null check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  delivery_fee numeric(10,2) not null check (delivery_fee >= 0),
  total numeric(12,2) not null,
  coupon_code text,
  notes text check (notes is null or char_length(notes) <= 500),
  admin_notes text, cancel_reason text,
  stock_deducted boolean not null default false,   -- هل خُصم المخزون لهذا الطلب فعلا
  stock_restored boolean not null default false,   -- هل أُعيد (مرة واحدة فقط)
  idempotency_key text unique,
  created_at timestamptz not null default now(),
  constraint orders_total_formula check (total = subtotal - discount + delivery_fee),
  constraint orders_discount_le_subtotal check (discount <= subtotal),
  constraint orders_home_address check (delivery_type <> 'home' or (address is not null and char_length(address) >= 5))
);
create index if not exists orders_phone_idx on orders(phone, created_at);
create index if not exists orders_status_idx on orders(status);
create index if not exists orders_created_idx on orders(created_at);
create index if not exists orders_wilaya_idx on orders(wilaya_code);

create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  variant_id uuid references product_variants(id) on delete set null,
  product_name text not null, color text, size text,
  qty int not null check (qty > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  unit_cost numeric(12,2) not null default 0 check (unit_cost >= 0)
);
create index if not exists order_items_order_idx on order_items(order_id);

create table if not exists order_status_log (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  old_status text, new_status text, note text,
  changed_by uuid, created_at timestamptz not null default now()
);

create table if not exists coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  code text not null references coupons(code) on delete cascade,
  order_id uuid not null references orders(id) on delete cascade,
  phone text not null, created_at timestamptz not null default now()
);
create index if not exists redemptions_idx on coupon_redemptions(code, phone);

-- المرتجعات: سجل حقيقي لكل إرجاع (طلب واحد = عملية إرجاع واحدة)
create table if not exists order_returns (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references orders(id) on delete cascade,
  reason text not null, created_by uuid, created_at timestamptz not null default now()
);
create table if not exists order_return_items (
  id uuid primary key default gen_random_uuid(),
  return_id uuid not null references order_returns(id) on delete cascade,
  order_item_id uuid not null references order_items(id) on delete cascade,
  qty int not null check (qty > 0),
  condition text not null check (condition in ('good','damaged'))  -- good: يعود للمخزون
);
