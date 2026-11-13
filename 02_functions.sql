-- =====================================================================
-- 02_functions.sql : الدوال والمشغّلات (آمن لإعادة التشغيل)
-- شغّله بعد 01. كل الدوال الحساسة: SECURITY DEFINER مع search_path ثابت.
-- الصلاحيات (من يستطيع استدعاءها) تُضبط في 03_security.sql
-- =====================================================================

-- ---------- المدير ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public, pg_temp as
$$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

-- ---------- أدوات صغيرة ----------
create or replace function public._norm_phone(p text) returns text
language sql immutable set search_path = public, pg_temp as
$$ select case when n ~ '^0[567][0-9]{8}$' then n end
   from (select regexp_replace(regexp_replace(coalesce(p,''), '[\s.()-]', '', 'g'),
                               '^(\+213|00213)', '0') as n) s $$;

create or replace function public._order_json(o public.orders) returns jsonb
language sql stable set search_path = public, pg_temp as
$$ select jsonb_build_object('order_no', o.order_no, 'status', o.status, 'subtotal', o.subtotal,
        'discount', o.discount, 'delivery_fee', o.delivery_fee, 'total', o.total) $$;

-- ---------- المخزون: المسار الوحيد لتغيير الكميات ----------
create or replace function public._stock_change(p_variant uuid, p_delta int, p_reason text,
                                                p_order uuid, p_note text) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_new int;
begin
  perform set_config('app.stock_fn', '1', true);
  update product_variants set stock = stock + p_delta
   where id = p_variant and stock + p_delta >= 0
   returning stock into v_new;
  perform set_config('app.stock_fn', '0', true);
  if v_new is null then
    if exists (select 1 from product_variants where id = p_variant) then
      raise exception 'INSUFFICIENT_STOCK';
    end if;
    raise exception 'VARIANT_NOT_FOUND';
  end if;
  insert into stock_movements(variant_id, delta, reason, order_id, note, created_by)
    values (p_variant, p_delta, p_reason, p_order, p_note, auth.uid());
  return v_new;
end $$;

-- حارس: يمنع أي تعديل مباشر لعمود stock خارج _stock_change (حتى لو اتسعت الصلاحيات لاحقا)
create or replace function public.trg_variant_stock_guard() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if new.stock is distinct from old.stock
     and coalesce(current_setting('app.stock_fn', true), '') <> '1' then
    raise exception 'STOCK_CHANGE_NOT_ALLOWED';
  end if;
  return new;
end $$;
drop trigger if exists variant_stock_guard on public.product_variants;
create trigger variant_stock_guard before update on public.product_variants
  for each row execute function public.trg_variant_stock_guard();

-- الكمية الأولية عند إنشاء مقاس/لون تُسجَّل في سجل الحركة
create or replace function public.trg_variant_initial() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.stock > 0 then
    insert into stock_movements(variant_id, delta, reason, note, created_by)
      values (new.id, new.stock, 'initial', 'initial quantity', auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists variant_initial on public.product_variants;
create trigger variant_initial after insert on public.product_variants
  for each row execute function public.trg_variant_initial();

-- ---------- حالة الطلب: انتقالات مسموحة + سجل + إرجاع المخزون مرة واحدة ----------
create or replace function public.trg_orders_status() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare ok boolean; r record;
begin
  if new.company_id is distinct from old.company_id and new.company_id is not null then
    if not exists (select 1 from delivery_rates dr join delivery_companies c on c.id = dr.company_id
                    where c.id = new.company_id and c.active and dr.wilaya_code = new.wilaya_code) then
      raise exception 'COMPANY_NOT_AVAILABLE_FOR_WILAYA';
    end if;
  end if;

  if new.status is distinct from old.status then
    ok := case old.status
      when 'new'                 then new.status in ('pending_confirmation','confirmed','cancelled')
      when 'pending_confirmation' then new.status in ('confirmed','cancelled')
      when 'confirmed'           then new.status in ('preparing','cancelled')
      when 'preparing'           then new.status in ('packed','cancelled')
      when 'packed'              then new.status in ('sent_to_courier','cancelled')
      when 'sent_to_courier'     then new.status in ('out_for_delivery','delivered','returned')
      when 'out_for_delivery'    then new.status in ('delivered','returned')
      when 'delivered'           then new.status = 'returned'
      else false end;                                   -- cancelled / returned: نهائية
    if not ok then
      raise exception 'INVALID_STATUS_TRANSITION: % -> %', old.status, new.status;
    end if;
    if new.status = 'returned' and coalesce(current_setting('app.return_fn', true), '') <> '1' then
      raise exception 'RETURN_REQUIRES_RETURN_RECORD';  -- يتم فقط عبر admin_process_return
    end if;

    if new.status = 'cancelled' then
      if char_length(trim(coalesce(new.cancel_reason, ''))) < 3 then
        raise exception 'CANCEL_REASON_REQUIRED';
      end if;
      -- إرجاع المخزون: فقط إن كان الطلب قد خصم فعلا ولم يُرجع من قبل
      if old.stock_deducted and not old.stock_restored then
        for r in select variant_id, qty from order_items
                  where order_id = new.id and variant_id is not null order by variant_id loop
          perform public._stock_change(r.variant_id, r.qty, 'order_cancelled', new.id, null);
        end loop;
        new.stock_restored := true;
      end if;
      -- تحرير استخدام الكوبون
      delete from coupon_redemptions where order_id = new.id;
      if found and old.coupon_code is not null then
        update coupons set used_count = greatest(used_count - 1, 0) where code = old.coupon_code;
      end if;
    end if;

    insert into order_status_log(order_id, old_status, new_status, note, changed_by)
      values (new.id, old.status, new.status,
              case when new.status = 'cancelled' then new.cancel_reason end, auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists orders_status on public.orders;
create trigger orders_status before update on public.orders
  for each row execute function public.trg_orders_status();

-- ---------- المعالجة الداخلية للطلب (تسعير + تحقق + كتابة) ----------
-- p_commit = false  => معاينة فقط (لا تغيّر شيئا)
create or replace function public._process_order(p_customer jsonb, p_items jsonb, p_coupon text,
                                                  p_key text, p_commit boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_name text; v_phone text; v_phone2 text; v_raw2 text; v_wil int; v_cid int; v_commune text;
  v_addr text; v_type text; v_company uuid; v_rawco text; v_notes text; v_fee numeric;
  v_lines jsonb := '[]'::jsonb; v_qty int := 0; v_n int;
  v_sub numeric := 0; v_elig numeric := 0; v_disc numeric := 0;
  e jsonb; l jsonb; r record; v record; c coupons; v_order orders; v_ex orders;
begin
  -- 1) إعادة الإرسال: نفس المفتاح => نفس الطلب (بلا خصم ثان)
  if p_commit and p_key is not null then
    if char_length(p_key) > 64 then raise exception 'INVALID_KEY'; end if;
    perform pg_advisory_xact_lock(hashtext(p_key));
    select * into v_ex from orders where idempotency_key = p_key;
    if found then return public._order_json(v_ex); end if;
  end if;

  -- 2) بيانات الزبون
  if p_customer is null or jsonb_typeof(p_customer) <> 'object' then raise exception 'INVALID_CUSTOMER'; end if;
  v_name := regexp_replace(trim(coalesce(p_customer->>'name', '')), '\s+', ' ', 'g');
  if char_length(v_name) < 3 or char_length(v_name) > 80 or v_name ~ '[<>]' then raise exception 'INVALID_NAME'; end if;
  v_phone := public._norm_phone(p_customer->>'phone');
  if v_phone is null then raise exception 'INVALID_PHONE'; end if;
  v_raw2 := nullif(trim(coalesce(p_customer->>'phone2', '')), '');
  if v_raw2 is not null then
    v_phone2 := public._norm_phone(v_raw2);
    if v_phone2 is null then raise exception 'INVALID_PHONE2'; end if;
  end if;
  if p_commit and (select count(*) from orders where phone = v_phone
                    and created_at > now() - interval '10 minutes') >= 3 then
    raise exception 'TOO_MANY_ORDERS';
  end if;

  if coalesce(p_customer->>'wilaya_code', '') !~ '^[0-9]{1,2}$' then raise exception 'INVALID_WILAYA'; end if;
  v_wil := (p_customer->>'wilaya_code')::int;
  if not exists (select 1 from wilayas where code = v_wil) then raise exception 'INVALID_WILAYA'; end if;
  if not exists (select 1 from communes where wilaya_code = v_wil) then raise exception 'COMMUNES_NOT_LOADED'; end if;
  if coalesce(p_customer->>'commune_id', '') !~ '^[0-9]{1,6}$' then raise exception 'INVALID_COMMUNE'; end if;
  v_cid := (p_customer->>'commune_id')::int;
  select concat_ws(' / ', name_fr, name_ar) into v_commune from communes where id = v_cid and wilaya_code = v_wil;
  if v_commune is null then raise exception 'INVALID_COMMUNE'; end if;

  v_type := p_customer->>'delivery_type';
  if coalesce(v_type, '') not in ('home', 'stop_desk') then raise exception 'INVALID_DELIVERY_TYPE'; end if;
  v_addr := nullif(trim(coalesce(p_customer->>'address', '')), '');
  if v_type = 'home' and (v_addr is null or char_length(v_addr) < 5) then raise exception 'ADDRESS_REQUIRED'; end if;
  if v_addr is not null and char_length(v_addr) > 250 then raise exception 'INVALID_ADDRESS'; end if;
  v_notes := left(nullif(trim(coalesce(p_customer->>'notes', '')), ''), 500);

  -- 3) شركة التوصيل والسعر (من قاعدة البيانات فقط)
  v_rawco := nullif(p_customer->>'company_id', '');
  if v_rawco is null then
    select id into v_company from delivery_companies where is_default and active;
    if v_company is null then raise exception 'NO_DEFAULT_COMPANY'; end if;
  else
    if v_rawco !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'INVALID_COMPANY'; end if;
    v_company := v_rawco::uuid;
    if not exists (select 1 from delivery_companies where id = v_company) then raise exception 'INVALID_COMPANY'; end if;
    if not exists (select 1 from delivery_companies where id = v_company and active) then raise exception 'DELIVERY_COMPANY_INACTIVE'; end if;
  end if;
  select case when v_type = 'home' then (case when home_enabled then home_price end)
              else (case when desk_enabled then desk_price end) end
    into v_fee from delivery_rates where company_id = v_company and wilaya_code = v_wil;
  if v_fee is null then raise exception 'DELIVERY_PRICE_NOT_SET'; end if;

  -- 4) المنتجات
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'INVALID_ITEMS'; end if;
  v_n := jsonb_array_length(p_items);
  if v_n < 1 or v_n > 30 then raise exception 'INVALID_ITEMS'; end if;
  for e in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(e) <> 'object'
       or coalesce(e->>'variant_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'INVALID_ITEMS';
    end if;
    if coalesce(e->>'qty', '') !~ '^[0-9]{1,3}$' or (e->>'qty')::int < 1 or (e->>'qty')::int > 20 then
      raise exception 'INVALID_QTY';
    end if;
    v_qty := v_qty + (e->>'qty')::int;
  end loop;
  if v_qty > 50 then raise exception 'INVALID_QTY'; end if;

  -- القفل بترتيب ثابت يمنع التعارض والجمود في الطلبات المتزامنة
  for r in select (x->>'variant_id')::uuid as vid, sum((x->>'qty')::int)::int as q
             from jsonb_array_elements(p_items) x group by 1 order by 1 loop
    if r.q > 20 then raise exception 'INVALID_QTY'; end if;
    if p_commit then perform 1 from product_variants where id = r.vid for update; end if;
    select pv.stock, pv.color, pv.size, pv.active as va, p.id as pid, p.active as pa,
           coalesce(p.price_discount, p.price_sale) as price, coalesce(pc.cost, 0) as cost,
           coalesce(p.name_fr, p.name_ar) as pname
      into v
      from product_variants pv join products p on p.id = pv.product_id
      left join product_costs pc on pc.product_id = p.id
     where pv.id = r.vid;
    if not found or not v.va or not v.pa then raise exception 'VARIANT_UNAVAILABLE'; end if;
    if v.stock < r.q then raise exception 'OUT_OF_STOCK:%', r.vid; end if;
    v_lines := v_lines || jsonb_build_object('variant_id', r.vid, 'product_id', v.pid, 'name', v.pname,
                 'color', v.color, 'size', v.size, 'qty', r.q, 'price', v.price, 'cost', v.cost);
    v_sub := v_sub + v.price * r.q;
  end loop;

  -- 5) الكوبون
  if nullif(trim(coalesce(p_coupon, '')), '') is not null then
    if p_commit then perform 1 from coupons where code = upper(trim(p_coupon)) for update; end if;
    select * into c from coupons
     where code = upper(trim(p_coupon)) and active
       and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at >= now());
    if not found then raise exception 'INVALID_COUPON'; end if;
    if c.max_uses is not null and c.used_count >= c.max_uses then raise exception 'COUPON_EXHAUSTED'; end if;
    if c.max_per_phone is not null
       and (select count(*) from coupon_redemptions where code = c.code and phone = v_phone) >= c.max_per_phone then
      raise exception 'COUPON_LIMIT_PER_PHONE';
    end if;
    if exists (select 1 from coupon_products where code = c.code) then
      select coalesce(sum((q->>'price')::numeric * (q->>'qty')::int), 0) into v_elig
        from jsonb_array_elements(v_lines) q
       where (q->>'product_id')::uuid in (select product_id from coupon_products where code = c.code);
    else
      v_elig := v_sub;
    end if;
    if v_elig <= 0 or v_sub < c.min_order then raise exception 'INVALID_COUPON'; end if;
    v_disc := least(v_elig, case c.kind when 'percent' then round(v_elig * c.value / 100) else c.value end);
  end if;

  if not p_commit then
    return jsonb_build_object('lines', v_lines, 'subtotal', v_sub, 'discount', v_disc,
                              'delivery_fee', v_fee, 'total', v_sub - v_disc + v_fee);
  end if;

  -- 6) الكتابة (كلها داخل معاملة واحدة: أي خطأ يلغي كل شيء)
  insert into orders(customer_name, phone, phone2, wilaya_code, commune_id, commune, address,
                     delivery_type, company_id, notes, status, subtotal, discount, delivery_fee,
                     total, coupon_code, stock_deducted, idempotency_key)
  values (v_name, v_phone, v_phone2, v_wil, v_cid, v_commune, v_addr, v_type, v_company, v_notes,
          'new', v_sub, v_disc, v_fee, v_sub - v_disc + v_fee, c.code, true, p_key)
  returning * into v_order;

  for l in select value from jsonb_array_elements(v_lines) loop
    insert into order_items(order_id, variant_id, product_name, color, size, qty, unit_price, unit_cost)
      values (v_order.id, (l->>'variant_id')::uuid, l->>'name', l->>'color', l->>'size',
              (l->>'qty')::int, (l->>'price')::numeric, (l->>'cost')::numeric);
    perform public._stock_change((l->>'variant_id')::uuid, -((l->>'qty')::int), 'sale', v_order.id, null);
  end loop;

  if c.code is not null then
    insert into coupon_redemptions(code, order_id, phone) values (c.code, v_order.id, v_phone);
    update coupons set used_count = used_count + 1 where code = c.code;
  end if;
  insert into order_status_log(order_id, old_status, new_status) values (v_order.id, null, 'new');
  return public._order_json(v_order);
end $$;

-- ---------- الدوال العامة (واجهة الزبون) ----------
create or replace function public.quote_order(p_customer jsonb, p_items jsonb, p_coupon text default null)
returns jsonb language sql security definer set search_path = public, pg_temp as
$$ select public._process_order(p_customer, p_items, p_coupon, null, false) $$;

create or replace function public.create_order(p_customer jsonb, p_items jsonb,
                                               p_coupon text default null, p_key text default null)
returns jsonb language sql security definer set search_path = public, pg_temp as
$$ select public._process_order(p_customer, p_items, p_coupon, p_key, true) $$;

-- تتبع الطلب: رقم الطلب + الهاتف معا، ولا يكشف أي بيانات شخصية
create or replace function public.track_order(p_order_no text, p_phone text) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('order_no', o.order_no, 'status', o.status, 'total', o.total,
                            'tracking_no', o.tracking_no, 'created_at', o.created_at)
    from orders o
   where o.order_no = upper(trim(p_order_no)) and o.phone = public._norm_phone(p_phone)
$$;

-- ---------- دوال المدير ----------
create or replace function public.admin_adjust_stock(p_variant uuid, p_delta int, p_reason text,
                                                     p_note text default null) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 100000 then raise exception 'INVALID_DELTA'; end if;
  if p_reason is null or p_reason not in ('purchase','return','damaged','inventory_count','manual') then
    raise exception 'INVALID_REASON';
  end if;
  if p_reason in ('purchase','return') and p_delta < 0 then raise exception 'DELTA_SIGN_MISMATCH'; end if;
  if p_reason = 'damaged' and p_delta > 0 then raise exception 'DELTA_SIGN_MISMATCH'; end if;
  if p_reason in ('manual','inventory_count') and char_length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'NOTE_REQUIRED';
  end if;
  perform 1 from product_variants where id = p_variant for update;
  if not found then raise exception 'VARIANT_NOT_FOUND'; end if;
  return public._stock_change(p_variant, p_delta, p_reason, null, left(trim(p_note), 300));
end $$;

-- جرد: أدخل الكمية الفعلية والنظام يحسب الفرق
create or replace function public.admin_set_stock_count(p_variant uuid, p_counted int, p_note text) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cur int;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if p_counted is null or p_counted < 0 or p_counted > 100000 then raise exception 'INVALID_COUNT'; end if;
  if char_length(trim(coalesce(p_note, ''))) < 3 then raise exception 'NOTE_REQUIRED'; end if;
  select stock into v_cur from product_variants where id = p_variant for update;
  if not found then raise exception 'VARIANT_NOT_FOUND'; end if;
  if p_counted = v_cur then raise exception 'NO_CHANGE'; end if;
  return public._stock_change(p_variant, p_counted - v_cur, 'inventory_count', null, left(trim(p_note), 300));
end $$;

-- إرجاع فعلي: p_items = [{"order_item_id": "...", "qty": 1, "condition": "good"|"damaged"}]
create or replace function public.admin_process_return(p_order uuid, p_reason text, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare o orders; e jsonb; it order_items; v_ret uuid; v_qty int; v_cond text;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  if char_length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'REASON_REQUIRED'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'INVALID_ITEMS';
  end if;
  select * into o from orders where id = p_order for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status not in ('sent_to_courier','out_for_delivery','delivered') then raise exception 'ORDER_NOT_RETURNABLE'; end if;
  if exists (select 1 from order_returns where order_id = p_order) then raise exception 'ALREADY_RETURNED'; end if;

  insert into order_returns(order_id, reason, created_by) values (p_order, trim(p_reason), auth.uid())
    returning id into v_ret;
  for e in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(e) <> 'object'
       or coalesce(e->>'order_item_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or coalesce(e->>'qty', '') !~ '^[0-9]{1,3}$' or (e->>'qty')::int < 1
       or coalesce(e->>'condition', '') not in ('good','damaged') then
      raise exception 'INVALID_ITEMS';
    end if;
    v_qty := (e->>'qty')::int; v_cond := e->>'condition';
    select * into it from order_items where id = (e->>'order_item_id')::uuid and order_id = p_order;
    if not found then raise exception 'INVALID_ITEM'; end if;
    if (select coalesce(sum(qty), 0) from order_return_items where order_item_id = it.id) + v_qty > it.qty then
      raise exception 'RETURN_QTY_EXCEEDS_SOLD';
    end if;
    insert into order_return_items(return_id, order_item_id, qty, condition) values (v_ret, it.id, v_qty, v_cond);
    if v_cond = 'good' and it.variant_id is not null then
      perform public._stock_change(it.variant_id, v_qty, 'return', p_order, 'return');
    end if;
  end loop;

  perform set_config('app.return_fn', '1', true);
  update orders set status = 'returned' where id = p_order;
  perform set_config('app.return_fn', '0', true);
  return jsonb_build_object('order_id', p_order, 'status', 'returned');
end $$;
