-- =====================================================================
-- 06_tests.sql : اختبارات الأمان والطلبات والمخزون والتوصيل
-- * تجري كل الاختبارات داخل معاملة فرعية ثم تتراجع تلقائيا: لا تبقى أي بيانات اختبار.
-- * شغّلها على مشروع Supabase تجريبي أولا، وبعد تنفيذ 01 إلى 04 (والبلديات 05 اختيارية: الاختبار ينشئ بلديتين وهميتين).
-- * لاختبارات المدير: أنشئ حسابك وأضفه إلى admins أولا (انظر README).
-- * النتيجة: جدول فيه passed = true/false. المطلوب: كل الصفوف true.
-- * تنبيه صغير: عدّاد أرقام الطلبات (sequence) يتقدم ولا يتراجع، وهذا طبيعي.
-- =====================================================================

create or replace function pg_temp.try_as(p_role text, p_claims text, p_sql text) returns text
language plpgsql as $$
declare r text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into r;
    r := coalesce(r, 'NULL');
  exception when others then
    r := 'ERR: ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return r;
end $$;

create or replace function pg_temp.r(p_test text, p_pass boolean, p_detail text) returns jsonb
language sql as $$ select jsonb_build_object('test', p_test, 'passed', coalesce(p_pass, false),
                                              'detail', left(coalesce(p_detail, ''), 160)) $$;

create or replace function pg_temp.jget(r text, k text) returns text
language plpgsql as $$ begin return (r::jsonb)->>k; exception when others then return null; end $$;

create or replace function pg_temp.stk(p_v uuid) returns int
language sql as $$ select stock from public.product_variants where id = p_v $$;

create or replace function pg_temp.cust(p_phone text, p_wil int, p_comm int,
                                        p_type text default 'home', p_company text default null) returns jsonb
language sql as $$
  select jsonb_strip_nulls(jsonb_build_object('name', 'Test Customer', 'phone', p_phone,
    'wilaya_code', p_wil, 'commune_id', p_comm, 'delivery_type', p_type,
    'address', '12 rue de test', 'company_id', p_company)) $$;

create or replace function pg_temp.items(p_v uuid, p_q int) returns jsonb
language sql as $$ select jsonb_build_array(jsonb_build_object('variant_id', p_v, 'qty', p_q)) $$;

create or replace function pg_temp.co(p_c jsonb, p_i jsonb, p_coupon text default null,
                                      p_key text default null, p_quote boolean default false) returns text
language plpgsql as $$
begin
  if p_quote then
    return pg_temp.try_as('anon', '{"role":"anon"}',
      format('select public.quote_order(%L::jsonb, %L::jsonb, %L)::text', p_c, p_i, p_coupon));
  end if;
  return pg_temp.try_as('anon', '{"role":"anon"}',
    format('select public.create_order(%L::jsonb, %L::jsonb, %L, %L)::text', p_c, p_i, p_coupon, p_key));
end $$;

create or replace function pg_temp.run_tests() returns table(t_name text, t_passed boolean, t_detail text)
language plpgsql as $$
declare
  res jsonb := '[]'::jsonb;
  anon_c constant text := '{"role":"anon"}';
  user_c text := json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text;
  v_admin uuid; admin_c text;
  cat uuid; p1 uuid; p2 uuid; pin uuid; v1 uuid; v3 uuid; v0 uuid; vin uuid;
  cA uuid; cB uuid; cC uuid; cm16 int; cm31 int;
  x text; x2 text; t text; rec record; n int; b int;
  ord uuid; ord2 uuid; ord3 uuid; ono text; it uuid;
begin
  select user_id into v_admin from admins limit 1;
  admin_c := case when v_admin is not null
                  then json_build_object('sub', v_admin, 'role', 'authenticated')::text end;
  begin
    -- ===================== تجهيز بيانات الاختبار (تتراجع في النهاية) =====================
    update delivery_companies set is_default = false;
    insert into categories(name_ar, name_fr) values ('اختبار', 'Test') returning id into cat;
    insert into products(name_ar, name_fr, category_id, price_original, price_sale, price_discount)
      values ('منتج', 'Prod A', cat, 5000, 4500, 4000) returning id into p1;
    insert into product_costs values (p1, 2500);
    insert into products(name_ar, name_fr, category_id, price_sale) values ('منتج2', 'Prod B', cat, 3000) returning id into p2;
    insert into products(name_ar, price_sale, active) values ('مخفي', 1000, false) returning id into pin;
    insert into product_variants(product_id, color, size, stock) values (p1, 'Black', 'M', 5) returning id into v1;
    insert into product_variants(product_id, color, size, stock) values (p1, 'Black', 'S', 0) returning id into v0;
    insert into product_variants(product_id, color, size, stock) values (p2, 'Grey', 'L', 50) returning id into v3;
    insert into product_variants(product_id, color, size, stock) values (pin, 'Black', 'M', 5) returning id into vin;
    insert into communes(source_id, wilaya_code, name_ar, name_fr) values (-1, 16, 'اختبار16', 'Test16') returning id into cm16;
    insert into communes(source_id, wilaya_code, name_ar, name_fr) values (-2, 31, 'اختبار31', 'Test31') returning id into cm31;
    insert into delivery_companies(name, active, is_default) values ('TestA', true, true) returning id into cA;
    insert into delivery_companies(name, active, is_default) values ('TestB-inactive', false, false) returning id into cB;
    insert into delivery_companies(name, active, is_default) values ('TestC-norates', true, false) returning id into cC;
    insert into delivery_rates(company_id, wilaya_code, home_price, desk_price) values (cA, 16, 600, 400), (cA, 31, null, 500);
    insert into delivery_rates(company_id, wilaya_code, home_price, desk_price) values (cB, 16, 100, 100);
    insert into coupons(code, kind, value, max_uses) values ('TESTPCT', 'percent', 10, 2);
    insert into coupons(code, kind, value, ends_at) values ('TESTEXPIRED', 'fixed', 100, now() - interval '1 day');
    insert into coupons(code, kind, value, max_per_phone) values ('TESTONCE', 'fixed', 200, 1);
    insert into settings(key, value) values ('test_secret', '"x"');

    res := res || pg_temp.r('SETUP initial stock logged', (select count(*) from stock_movements where variant_id = v1 and reason = 'initial') = 1, null);

    -- ===================== A) أمان الزائر (anon) =====================
    foreach t in array array['orders','order_items','product_costs','coupons','coupon_redemptions',
        'stock_movements','admins','order_status_log','order_returns','order_return_items'] loop
      x := pg_temp.try_as('anon', anon_c, format('select count(*)::text from %I', t));
      res := res || pg_temp.r('SEC anon cannot read ' || t, x like 'ERR: permission denied%', x);
    end loop;
    x := pg_temp.try_as('anon', anon_c, 'with u as (update product_variants set stock = 999 returning 1) select count(*)::text from u');
    res := res || pg_temp.r('SEC anon cannot change stock', x like 'ERR: permission denied%', x);
    x := pg_temp.try_as('anon', anon_c, 'with i as (insert into orders(customer_name, phone, wilaya_code, commune, delivery_type, subtotal, delivery_fee, total) values (''Hacker'', ''0550000000'', 16, ''x'', ''stop_desk'', 0, 0, 0) returning 1) select count(*)::text from i');
    res := res || pg_temp.r('SEC anon cannot insert orders directly', x like 'ERR: permission denied%', x);
    x := pg_temp.try_as('anon', anon_c, 'with d as (delete from products returning 1) select count(*)::text from d');
    res := res || pg_temp.r('SEC anon cannot delete products', x like 'ERR: permission denied%', x);
    x := pg_temp.try_as('anon', anon_c, format('select public.admin_adjust_stock(%L, 1, ''manual'', ''hack'')::text', v1));
    res := res || pg_temp.r('SEC anon cannot call admin_adjust_stock', x like 'ERR: permission denied%', x);
    x := pg_temp.try_as('anon', anon_c, 'select public._process_order(''{}''::jsonb, ''[]''::jsonb, null, null, true)::text');
    res := res || pg_temp.r('SEC anon cannot call internal _process_order', x like 'ERR: permission denied%', x);
    x := pg_temp.try_as('anon', anon_c, format('select public._stock_change(%L, 5, ''manual'', null, null)::text', v1));
    res := res || pg_temp.r('SEC anon cannot call internal _stock_change', x like 'ERR: permission denied%', x);
    x := pg_temp.try_as('anon', anon_c, format('select count(*)::text from products where id = %L', pin));
    res := res || pg_temp.r('SEC anon cannot see hidden product', x = '0', x);
    x := pg_temp.try_as('anon', anon_c, format('select count(*)::text from products where id = %L', p1));
    res := res || pg_temp.r('SEC anon sees active product', x = '1', x);
    x := pg_temp.try_as('anon', anon_c, format('select count(*)::text from product_variants where id = %L', vin));
    res := res || pg_temp.r('SEC anon cannot see variants of hidden product', x = '0', x);
    x := pg_temp.try_as('anon', anon_c, 'select count(*)::text from settings where key = ''test_secret''');
    res := res || pg_temp.r('SEC anon cannot read non-public settings', x = '0', x);
    x := pg_temp.try_as('anon', anon_c, format('select count(*)::text from delivery_rates where company_id = %L', cB));
    res := res || pg_temp.r('SEC anon cannot see rates of inactive company', x = '0', x);
    x := pg_temp.try_as('anon', anon_c, 'with i as (insert into storage.objects(bucket_id, name) values (''product-images'', ''t.png'') returning 1) select count(*)::text from i');
    res := res || pg_temp.r('SEC anon cannot upload images', x like 'ERR:%', x);
    x := pg_temp.try_as('authenticated', user_c, 'with i as (insert into storage.objects(bucket_id, name) values (''product-images'', ''t.png'') returning 1) select count(*)::text from i');
    res := res || pg_temp.r('SEC non-admin user cannot upload images', x like 'ERR:%', x);

    -- ===================== B) إنشاء الطلبات =====================
    x := pg_temp.co(pg_temp.cust('0551000001', 16, cm16), pg_temp.items(v1, 2), null, null, true);
    res := res || pg_temp.r('ORD quote total = 4000*2 + 600', pg_temp.jget(x, 'total')::numeric = 8600, x);
    res := res || pg_temp.r('ORD quote does not change stock', pg_temp.stk(v1) = 5, null);

    x := pg_temp.co(pg_temp.cust('0551000002', 16, cm16),
          jsonb_build_array(jsonb_build_object('variant_id', v1, 'qty', 2, 'price', 1)));
    ono := pg_temp.jget(x, 'order_no');
    res := res || pg_temp.r('ORD create: client price ignored, total from DB', pg_temp.jget(x, 'total')::numeric = 8600, x);
    res := res || pg_temp.r('ORD create: stock 5 -> 3', pg_temp.stk(v1) = 3, null);
    select id into ord from orders where order_no = ono;
    res := res || pg_temp.r('ORD sale movement logged', exists (select 1 from stock_movements where order_id = ord and reason = 'sale' and delta = -2), null);
    res := res || pg_temp.r('ORD cost snapshot saved', (select unit_cost from order_items where order_id = ord) = 2500, null);

    x := pg_temp.co(pg_temp.cust('0551000003', 16, cm16), pg_temp.items(v1, 4));
    res := res || pg_temp.r('ORD oversell rejected, stock unchanged', position('OUT_OF_STOCK' in x) > 0 and pg_temp.stk(v1) = 3, x);

    x := pg_temp.co(pg_temp.cust('0551000005', 16, cm16),
          jsonb_build_array(jsonb_build_object('variant_id', v3, 'qty', 1), jsonb_build_object('variant_id', v1, 'qty', 4)));
    res := res || pg_temp.r('ATOMIC failing 2nd line leaves 1st untouched, no order',
          position('OUT_OF_STOCK' in x) > 0 and pg_temp.stk(v3) = 50 and pg_temp.stk(v1) = 3
          and (select count(*) from orders where phone = '0551000005') = 0, x);

    x := pg_temp.co(pg_temp.cust('0551000006', 16, cm16), pg_temp.items(v0, 1));
    res := res || pg_temp.r('ORD zero-stock variant rejected', position('OUT_OF_STOCK' in x) > 0, x);
    x := pg_temp.co(pg_temp.cust('0551000006', 16, cm16), pg_temp.items(vin, 1));
    res := res || pg_temp.r('ORD hidden-product variant rejected', position('VARIANT_UNAVAILABLE' in x) > 0, x);

    -- مصفوفة التحقق من المدخلات
    for rec in select * from (values
      ('bad phone',      pg_temp.cust('0123456789', 16, cm16), pg_temp.items(v3, 1), 'INVALID_PHONE'),
      ('short name',     pg_temp.cust('0551000007', 16, cm16) || '{"name":"ab"}'::jsonb, pg_temp.items(v3, 1), 'INVALID_NAME'),
      ('bad delivery',   pg_temp.cust('0551000007', 16, cm16) || '{"delivery_type":"drone"}'::jsonb, pg_temp.items(v3, 1), 'INVALID_DELIVERY_TYPE'),
      ('home no address',pg_temp.cust('0551000007', 16, cm16) - 'address', pg_temp.items(v3, 1), 'ADDRESS_REQUIRED'),
      ('bad wilaya',     pg_temp.cust('0551000007', 16, cm16) || '{"wilaya_code":99}'::jsonb, pg_temp.items(v3, 1), 'INVALID_WILAYA'),
      ('commune of other wilaya', pg_temp.cust('0551000007', 16, cm31), pg_temp.items(v3, 1), 'INVALID_COMMUNE'),
      ('missing commune',pg_temp.cust('0551000007', 16, cm16) - 'commune_id', pg_temp.items(v3, 1), 'INVALID_COMMUNE'),
      ('customer is array', '[]'::jsonb, pg_temp.items(v3, 1), 'INVALID_CUSTOMER'),
      ('empty items',    pg_temp.cust('0551000007', 16, cm16), '[]'::jsonb, 'INVALID_ITEMS'),
      ('items is object',pg_temp.cust('0551000007', 16, cm16), '{}'::jsonb, 'INVALID_ITEMS'),
      ('item is number', pg_temp.cust('0551000007', 16, cm16), '[1]'::jsonb, 'INVALID_ITEMS'),
      ('variant not uuid', pg_temp.cust('0551000007', 16, cm16), '[{"variant_id":"abc","qty":1}]'::jsonb, 'INVALID_ITEMS'),
      ('qty zero',       pg_temp.cust('0551000007', 16, cm16), pg_temp.items(v3, 0), 'INVALID_QTY'),
      ('qty negative',   pg_temp.cust('0551000007', 16, cm16), '[{"variant_id":"00000000-0000-0000-0000-000000000000","qty":-1}]'::jsonb, 'INVALID_QTY'),
      ('qty text',       pg_temp.cust('0551000007', 16, cm16), jsonb_build_array(jsonb_build_object('variant_id', v3, 'qty', '2x')), 'INVALID_QTY'),
      ('qty decimal',    pg_temp.cust('0551000007', 16, cm16), jsonb_build_array(jsonb_build_object('variant_id', v3, 'qty', 1.5)), 'INVALID_QTY'),
      ('qty too large',  pg_temp.cust('0551000007', 16, cm16), pg_temp.items(v3, 21), 'INVALID_QTY'),
      ('unknown variant',pg_temp.cust('0551000007', 16, cm16), pg_temp.items(gen_random_uuid(), 1), 'VARIANT_UNAVAILABLE')
    ) as m(label, c, i, code) loop
      x := pg_temp.co(rec.c, rec.i);
      res := res || pg_temp.r('VALID ' || rec.label, position(rec.code in x) > 0, x);
    end loop;
    res := res || pg_temp.r('VALID none of the invalid calls created an order', (select count(*) from orders where phone = '0551000007') = 0, null);

    -- ===================== C) التوصيل =====================
    x := pg_temp.co(pg_temp.cust('0551000008', 31, cm31, 'home'), pg_temp.items(v3, 1));
    res := res || pg_temp.r('DELIV unset price (Oran home) blocks order', position('DELIVERY_PRICE_NOT_SET' in x) > 0, x);
    x := pg_temp.co(pg_temp.cust('0551000008', 31, cm31, 'stop_desk'), pg_temp.items(v3, 1));
    res := res || pg_temp.r('DELIV stop_desk price applied (3000+500)', pg_temp.jget(x, 'total')::numeric = 3500, x);
    x := pg_temp.co(pg_temp.cust('0551000009', 16, cm16, 'home', cB::text), pg_temp.items(v3, 1));
    res := res || pg_temp.r('DELIV inactive company rejected', position('DELIVERY_COMPANY_INACTIVE' in x) > 0, x);
    x := pg_temp.co(pg_temp.cust('0551000009', 16, cm16, 'home', cC::text), pg_temp.items(v3, 1));
    res := res || pg_temp.r('DELIV company without rate for wilaya rejected', position('DELIVERY_PRICE_NOT_SET' in x) > 0, x);
    x := pg_temp.co(pg_temp.cust('0551000009', 16, cm16, 'home', gen_random_uuid()::text), pg_temp.items(v3, 1));
    res := res || pg_temp.r('DELIV unknown company rejected', position('INVALID_COMPANY' in x) > 0, x);
    x := pg_temp.co(pg_temp.cust('0551000009', 16, cm16, 'home', 'abc'), pg_temp.items(v3, 1));
    res := res || pg_temp.r('DELIV malformed company id rejected', position('INVALID_COMPANY' in x) > 0, x);
    update delivery_companies set is_default = false where id = cA;
    x := pg_temp.co(pg_temp.cust('0551000009', 16, cm16), pg_temp.items(v3, 1));
    res := res || pg_temp.r('DELIV no default company rejected', position('NO_DEFAULT_COMPANY' in x) > 0, x);
    update delivery_companies set is_default = true where id = cA;

    -- ===================== D) الكوبونات =====================
    x := pg_temp.co(pg_temp.cust('0551000010', 16, cm16), pg_temp.items(v3, 1), 'testpct', null, true);
    res := res || pg_temp.r('COUPON 10% quote (3000-300+600)', pg_temp.jget(x, 'total')::numeric = 3300, x);
    x := pg_temp.co(pg_temp.cust('0551000010', 16, cm16), pg_temp.items(v3, 1), 'TESTPCT');
    x2 := pg_temp.co(pg_temp.cust('0551000011', 16, cm16), pg_temp.items(v3, 1), 'TESTPCT');
    res := res || pg_temp.r('COUPON used twice OK', pg_temp.jget(x, 'discount')::numeric = 300 and pg_temp.jget(x2, 'discount')::numeric = 300, x || x2);
    x := pg_temp.co(pg_temp.cust('0551000012', 16, cm16), pg_temp.items(v3, 1), 'TESTPCT');
    res := res || pg_temp.r('COUPON max_uses enforced', position('COUPON_EXHAUSTED' in x) > 0, x);
    x := pg_temp.co(pg_temp.cust('0551000013', 16, cm16), pg_temp.items(v3, 1), 'TESTEXPIRED');
    res := res || pg_temp.r('COUPON expired rejected', position('INVALID_COUPON' in x) > 0, x);
    x := pg_temp.co(pg_temp.cust('0551000014', 16, cm16), pg_temp.items(v3, 1), 'NOSUCHCODE');
    res := res || pg_temp.r('COUPON unknown rejected', position('INVALID_COUPON' in x) > 0, x);
    x := pg_temp.co(pg_temp.cust('0551000015', 16, cm16), pg_temp.items(v3, 1), 'TESTONCE');
    x2 := pg_temp.co(pg_temp.cust('0551000015', 16, cm16), pg_temp.items(v3, 1), 'TESTONCE');
    res := res || pg_temp.r('COUPON per-phone limit enforced', pg_temp.jget(x, 'discount')::numeric = 200 and position('COUPON_LIMIT_PER_PHONE' in x2) > 0, x || x2);

    -- ===================== E) الحماية من التكرار =====================
    n := 0;
    for b in 1..3 loop
      x := pg_temp.co(pg_temp.cust('0551000020', 16, cm16), pg_temp.items(v3, 1));
      if pg_temp.jget(x, 'order_no') is not null then n := n + 1; end if;
    end loop;
    x := pg_temp.co(pg_temp.cust('0551000020', 16, cm16), pg_temp.items(v3, 1));
    res := res || pg_temp.r('RATE 3 orders ok then 4th blocked', n = 3 and position('TOO_MANY_ORDERS' in x) > 0, x);

    b := pg_temp.stk(v3);
    x := pg_temp.co(pg_temp.cust('0551000021', 16, cm16), pg_temp.items(v3, 1), null, 'key-test-1');
    x2 := pg_temp.co(pg_temp.cust('0551000021', 16, cm16), pg_temp.items(v3, 1), null, 'key-test-1');
    res := res || pg_temp.r('IDEMP same key = same order, stock deducted once',
          pg_temp.jget(x, 'order_no') = pg_temp.jget(x2, 'order_no') and pg_temp.stk(v3) = b - 1, x || x2);

    -- ===================== F) تتبع الطلب =====================
    x := pg_temp.try_as('anon', anon_c, format('select public.track_order(%L, %L)::text', lower(ono), '0551000002'));
    res := res || pg_temp.r('TRACK right number+phone works', pg_temp.jget(x, 'status') = 'new', x);
    res := res || pg_temp.r('TRACK exposes no personal data', pg_temp.jget(x, 'phone') is null and pg_temp.jget(x, 'customer_name') is null, x);
    x := pg_temp.try_as('anon', anon_c, format('select public.track_order(%L, %L)::text', ono, '0559999999'));
    res := res || pg_temp.r('TRACK wrong phone returns nothing', x = 'NULL', x);

    -- ===================== G) مستخدم عادي مسجّل (ليس مدير) =====================
    x := pg_temp.try_as('authenticated', user_c, 'select count(*)::text from orders');
    res := res || pg_temp.r('SEC non-admin sees 0 orders', x = '0', x);
    x := pg_temp.try_as('authenticated', user_c, 'select count(*)::text from product_costs');
    res := res || pg_temp.r('SEC non-admin sees 0 costs', x = '0', x);
    x := pg_temp.try_as('authenticated', user_c, format('select public.admin_adjust_stock(%L, 1, ''manual'', ''hack!'')::text', v1));
    res := res || pg_temp.r('SEC non-admin blocked from admin_adjust_stock', position('FORBIDDEN' in x) > 0, x);
    x := pg_temp.try_as('authenticated', user_c, 'with u as (update orders set status = ''confirmed'' returning 1) select count(*)::text from u');
    res := res || pg_temp.r('SEC non-admin cannot update orders', x = '0' or x like 'ERR:%', x);

    -- ===================== H) المدير: المخزون والإلغاء والإرجاع =====================
    if v_admin is null then
      res := res || pg_temp.r('ADMIN tests', false, 'SKIPPED: أنشئ حساب المدير وأضفه إلى admins ثم أعد التشغيل');
    else
      x := pg_temp.try_as('authenticated', admin_c, 'select count(*)::text from orders');
      res := res || pg_temp.r('ADMIN can read orders', x ~ '^[1-9]', x);
      x := pg_temp.try_as('authenticated', admin_c, format('with u as (update product_variants set stock = 1 where id = %L returning 1) select count(*)::text from u', v1));
      res := res || pg_temp.r('ADMIN cannot edit stock column directly', x like 'ERR: permission denied%', x);
      x := pg_temp.try_as('postgres', anon_c, format('with u as (update product_variants set stock = 1 where id = %L returning 1) select count(*)::text from u', v1));
      res := res || pg_temp.r('GUARD trigger blocks direct stock update even for owner', position('STOCK_CHANGE_NOT_ALLOWED' in x) > 0, x);
      x := pg_temp.try_as('authenticated', admin_c, format('with u as (update orders set total = 1 where id = %L returning 1) select count(*)::text from u', ord));
      res := res || pg_temp.r('ADMIN cannot edit order totals', x like 'ERR: permission denied%', x);

      -- إلغاء طلب خصم مخزونه: يعود المخزون مرة واحدة فقط
      x := pg_temp.try_as('authenticated', admin_c, format('with u as (update orders set status = ''cancelled'' where id = %L returning 1) select count(*)::text from u', ord));
      res := res || pg_temp.r('CANCEL requires a reason', position('CANCEL_REASON_REQUIRED' in x) > 0, x);
      x := pg_temp.try_as('authenticated', admin_c, format('with u as (update orders set status = ''cancelled'', cancel_reason = ''test cancel'' where id = %L returning 1) select count(*)::text from u', ord));
      res := res || pg_temp.r('CANCEL ok and stock restored 3 -> 5', x = '1' and pg_temp.stk(v1) = 5, x);
      x := pg_temp.try_as('authenticated', admin_c, format('with u as (update orders set status = ''cancelled'', cancel_reason = ''again again'' where id = %L returning 1) select count(*)::text from u', ord));
      res := res || pg_temp.r('CANCEL again does NOT restore twice', pg_temp.stk(v1) = 5, x);
      res := res || pg_temp.r('CANCEL movement logged exactly once', (select count(*) from stock_movements where order_id = ord and reason = 'order_cancelled') = 1, null);
      x := pg_temp.try_as('authenticated', admin_c, format('with u as (update orders set status = ''new'' where id = %L returning 1) select count(*)::text from u', ord));
      res := res || pg_temp.r('CANCEL cancelled order cannot be reopened', position('INVALID_STATUS_TRANSITION' in x) > 0, x);

      -- طلب لم يخصم المخزون أصلا: الإلغاء لا يرجع شيئا
      insert into orders(customer_name, phone, wilaya_code, commune, delivery_type, subtotal, delivery_fee, total, stock_deducted)
        values ('Manual Order', '0551000099', 16, 'x', 'stop_desk', 8000, 400, 8400, false) returning id into ord2;
      insert into order_items(order_id, variant_id, product_name, qty, unit_price) values (ord2, v1, 'x', 2, 4000);
      x := pg_temp.try_as('authenticated', admin_c, format('with u as (update orders set status = ''cancelled'', cancel_reason = ''manual test'' where id = %L returning 1) select count(*)::text from u', ord2));
      res := res || pg_temp.r('CANCEL order that never deducted stock restores nothing', x = '1' and pg_temp.stk(v1) = 5, x);

      -- طلب مسلّم: لا يُلغى، والإرجاع لا يتم إلا بسجل إرجاع فعلي
      x := pg_temp.co(pg_temp.cust('0551000030', 16, cm16), pg_temp.items(v1, 2));
      select id into ord3 from orders where order_no = pg_temp.jget(x, 'order_no');
      res := res || pg_temp.r('RETURN setup: new order deducted 5 -> 3', pg_temp.stk(v1) = 3, x);
      update orders set status = 'confirmed' where id = ord3;
      update orders set status = 'preparing' where id = ord3;
      update orders set status = 'packed' where id = ord3;
      update orders set status = 'sent_to_courier' where id = ord3;
      update orders set status = 'delivered' where id = ord3;
      x := pg_temp.try_as('authenticated', admin_c, format('with u as (update orders set status = ''cancelled'', cancel_reason = ''try cancel'' where id = %L returning 1) select count(*)::text from u', ord3));
      res := res || pg_temp.r('DELIVERED order cannot be cancelled', position('INVALID_STATUS_TRANSITION' in x) > 0 and pg_temp.stk(v1) = 3, x);
      x := pg_temp.try_as('authenticated', admin_c, format('with u as (update orders set status = ''returned'' where id = %L returning 1) select count(*)::text from u', ord3));
      res := res || pg_temp.r('RETURN direct status change blocked', position('RETURN_REQUIRES_RETURN_RECORD' in x) > 0, x);
      select id into it from order_items where order_id = ord3;
      x := pg_temp.try_as('authenticated', admin_c, format('select public.admin_process_return(%L, ''test return'', %L::jsonb)::text', ord3, jsonb_build_array(jsonb_build_object('order_item_id', it, 'qty', 3, 'condition', 'good'))));
      res := res || pg_temp.r('RETURN more than sold rejected, nothing changed',
            position('RETURN_QTY_EXCEEDS_SOLD' in x) > 0 and pg_temp.stk(v1) = 3 and not exists (select 1 from order_returns where order_id = ord3), x);
      x := pg_temp.try_as('authenticated', admin_c, format('select public.admin_process_return(%L, ''test return'', %L::jsonb)::text', ord3,
            jsonb_build_array(jsonb_build_object('order_item_id', it, 'qty', 1, 'condition', 'good'), jsonb_build_object('order_item_id', it, 'qty', 1, 'condition', 'damaged'))));
      res := res || pg_temp.r('RETURN good piece restocked, damaged not (3 -> 4), status returned',
            pg_temp.jget(x, 'status') = 'returned' and pg_temp.stk(v1) = 4 and (select status from orders where id = ord3) = 'returned', x);
      x := pg_temp.try_as('authenticated', admin_c, format('select public.admin_process_return(%L, ''again'', %L::jsonb)::text', ord3, jsonb_build_array(jsonb_build_object('order_item_id', it, 'qty', 1, 'condition', 'good'))));
      res := res || pg_temp.r('RETURN cannot be processed twice (stock stays 4)', x like 'ERR:%' and pg_temp.stk(v1) = 4, x);

      -- دوال المخزون
      x := pg_temp.try_as('authenticated', admin_c, format('select public.admin_adjust_stock(%L, 0, ''manual'', ''zero delta'')::text', v1));
      res := res || pg_temp.r('STOCK delta 0 rejected', position('INVALID_DELTA' in x) > 0, x);
      x := pg_temp.try_as('authenticated', admin_c, format('select public.admin_adjust_stock(%L, 1, ''sale'', ''fake sale'')::text', v1));
      res := res || pg_temp.r('STOCK system reason (sale) rejected', position('INVALID_REASON' in x) > 0, x);
      x := pg_temp.try_as('authenticated', admin_c, format('select public.admin_adjust_stock(%L, -1, ''purchase'', null)::text', v1));
      res := res || pg_temp.r('STOCK purchase with negative delta rejected', position('DELTA_SIGN_MISMATCH' in x) > 0, x);
      x := pg_temp.try_as('authenticated', admin_c, format('select public.admin_adjust_stock(%L, 5, ''manual'', null)::text', v1));
      res := res || pg_temp.r('STOCK manual without note rejected', position('NOTE_REQUIRED' in x) > 0, x);
      x := pg_temp.try_as('authenticated', admin_c, format('select public.admin_adjust_stock(%L, -100, ''damaged'', ''too many'')::text', v1));
      res := res || pg_temp.r('STOCK cannot go negative', position('INSUFFICIENT_STOCK' in x) > 0 and pg_temp.stk(v1) = 4, x);
      x := pg_temp.try_as('authenticated', admin_c, format('select public.admin_adjust_stock(%L, 5, ''purchase'', ''supplier batch'')::text', v1));
      res := res || pg_temp.r('STOCK purchase +5 (4 -> 9) and logged', x = '9' and exists (select 1 from stock_movements where variant_id = v1 and reason = 'purchase' and delta = 5), x);
      x := pg_temp.try_as('authenticated', admin_c, format('select public.admin_set_stock_count(%L, 7, ''physical count'')::text', v1));
      res := res || pg_temp.r('STOCK inventory count sets 7 and logs -2', x = '7' and exists (select 1 from stock_movements where variant_id = v1 and reason = 'inventory_count' and delta = -2), x);
      x := pg_temp.try_as('authenticated', admin_c, 'with i as (insert into storage.objects(bucket_id, name) values (''product-images'', ''admin-test.png'') returning 1) select count(*)::text from i');
      res := res || pg_temp.r('ADMIN can upload images (storage)', x = '1', x);
    end if;

    raise exception 'TESTS_DONE';   -- يلغي كل بيانات الاختبار
  exception when others then
    if sqlerrm <> 'TESTS_DONE' then
      res := res || pg_temp.r('FATAL ERROR (الاختبار توقف)', false, sqlerrm);
    end if;
  end;
  return query select j->>'test', (j->>'passed')::boolean, j->>'detail' from jsonb_array_elements(res) j;
end $$;

-- النتيجة: الصفوف الفاشلة تظهر أولا. المطلوب: لا صفوف passed = false
select * from pg_temp.run_tests() order by t_passed, t_name;
