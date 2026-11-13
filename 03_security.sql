-- =====================================================================
-- 03_security.sql : الصلاحيات وRLS والتخزين (آمن لإعادة التشغيل)
-- شغّله بعد 02. المبدأ: نسحب كل شيء أولا ثم نمنح الحد الأدنى فقط.
-- =====================================================================

-- ---------- 1) سحب كل الصلاحيات الافتراضية ----------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

-- ---------- 2) تفعيل RLS على كل الجداول ----------
do $$ declare t text; begin
  foreach t in array array['admins','categories','products','product_costs','product_images',
    'product_variants','stock_movements','wilayas','communes','delivery_companies','delivery_rates',
    'coupons','coupon_products','coupon_redemptions','settings','orders','order_items',
    'order_status_log','order_returns','order_return_items'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
  -- سياسة المدير على كل الجداول ما عدا admins (لا أحد يقرؤه مباشرة)
  foreach t in array array['categories','products','product_costs','product_images',
    'product_variants','stock_movements','wilayas','communes','delivery_companies','delivery_rates',
    'coupons','coupon_products','coupon_redemptions','settings','orders','order_items',
    'order_status_log','order_returns','order_return_items'] loop
    execute format('drop policy if exists admin_all on public.%I', t);
    execute format('create policy admin_all on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- ---------- 3) سياسات القراءة العامة (الزوار): ما يظهر في المتجر فقط ----------
drop policy if exists pub_categories on categories;
create policy pub_categories on categories for select to anon, authenticated using (active);
drop policy if exists pub_products on products;
create policy pub_products on products for select to anon, authenticated using (active);
drop policy if exists pub_images on product_images;
create policy pub_images on product_images for select to anon, authenticated
  using (exists (select 1 from products p where p.id = product_id and p.active));
drop policy if exists pub_variants on product_variants;
create policy pub_variants on product_variants for select to anon, authenticated
  using (active and exists (select 1 from products p where p.id = product_id and p.active));
drop policy if exists pub_wilayas on wilayas;
create policy pub_wilayas on wilayas for select to anon, authenticated using (true);
drop policy if exists pub_communes on communes;
create policy pub_communes on communes for select to anon, authenticated using (true);
drop policy if exists pub_companies on delivery_companies;
create policy pub_companies on delivery_companies for select to anon, authenticated using (active);
drop policy if exists pub_rates on delivery_rates;
create policy pub_rates on delivery_rates for select to anon, authenticated
  using (exists (select 1 from delivery_companies c where c.id = company_id and c.active));
drop policy if exists pub_settings on settings;
create policy pub_settings on settings for select to anon, authenticated
  using (key in ('whatsapp','instagram','store_name'));
-- لا سياسة عامة إطلاقا على: orders, order_items, product_costs, coupons, stock_movements, ...

-- ---------- 4) صلاحيات الجداول (الحد الأدنى) ----------
grant usage on schema public to anon, authenticated;

-- الزوار: قراءة فقط لجداول المتجر العامة
grant select on categories, products, product_images, product_variants, wilayas, communes,
                delivery_companies, delivery_rates, settings to anon;

-- المدير (authenticated + is_admin عبر RLS)
grant select, insert, update, delete on categories, products, product_costs, product_images,
      delivery_companies, delivery_rates, coupons, coupon_products, communes, settings to authenticated;
grant select on wilayas to authenticated;
grant usage on sequence communes_id_seq to authenticated;

-- المقاسات: لا تعديل مباشر لعمود stock (فقط عبر دوال المخزون)
grant select, insert, delete on product_variants to authenticated;
grant update (color, color_hex, color_image_url, size, low_stock_threshold, active)
  on product_variants to authenticated;

-- الطلبات: قراءة + تعديل أعمدة محددة فقط (لا تعديل للمبالغ أو بيانات الزبون أو البنود)
grant select on orders, order_items, order_status_log, stock_movements, order_returns,
                order_return_items, coupon_redemptions to authenticated;
grant update (status, company_id, tracking_no, admin_notes, cancel_reason) on orders to authenticated;

-- admins: لا صلاحيات لأحد (يُقرأ عبر is_admin() فقط)

-- ---------- 5) صلاحيات تنفيذ الدوال ----------
grant execute on function public.create_order(jsonb, jsonb, text, text) to anon, authenticated;
grant execute on function public.quote_order(jsonb, jsonb, text)        to anon, authenticated;
grant execute on function public.track_order(text, text)                to anon, authenticated;
grant execute on function public.is_admin()                             to authenticated;
grant execute on function public.admin_adjust_stock(uuid, int, text, text) to authenticated;
grant execute on function public.admin_set_stock_count(uuid, int, text)    to authenticated;
grant execute on function public.admin_process_return(uuid, text, jsonb)   to authenticated;
-- الدوال الداخلية (_process_order, _stock_change, _norm_phone, _order_json) والمشغّلات: لا أحد.

-- ---------- 6) تخزين الصور: القراءة بالرابط العام، والرفع/التعديل/الحذف للمدير فقط ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 5242880,
        array['image/jpeg','image/png','image/webp','image/avif'])
on conflict (id) do update set public = true, file_size_limit = 5242880,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "public read images"  on storage.objects;   -- من النسخة القديمة
drop policy if exists "admin write images"  on storage.objects;   -- من النسخة القديمة
drop policy if exists store_img_select on storage.objects;
drop policy if exists store_img_insert on storage.objects;
drop policy if exists store_img_update on storage.objects;
drop policy if exists store_img_delete on storage.objects;
-- لا سياسة select للزوار: الصور تُعرض بالرابط العام ولا يمكن سرد محتوى الحاوية
create policy store_img_select on storage.objects for select to authenticated
  using (bucket_id = 'product-images' and public.is_admin());
create policy store_img_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'product-images' and public.is_admin());
create policy store_img_update on storage.objects for update to authenticated
  using (bucket_id = 'product-images' and public.is_admin())
  with check (bucket_id = 'product-images' and public.is_admin());
create policy store_img_delete on storage.objects for delete to authenticated
  using (bucket_id = 'product-images' and public.is_admin());
