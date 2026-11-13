-- =====================================================================
-- 05_communes_import.sql : البلديات (1541) عبر استيراد ملف CSV ثم تحقق ثم نقل
-- لم أكتب البلديات بنفسي: 1541 اسما يدويا يعني أخطاء. نستورد من مصدر منشور ونتحقق.
--
-- المصدر: https://github.com/othmanus/algeria-cities  (58 ولاية / 1541 بلدية، رخصة مفتوحة)
--   يذكر المشروع أنه مطابق لقائمة وزارة الداخلية. نزّل ملف CSV (النسخة التي فيها العربية والفرنسية).
--
-- الخطوات من الهاتف:
--  A) شغّل القسم A (ينشئ جدول مؤقتا فارغا).
--  B) Supabase > Table Editor > اختر الجدول communes_raw > Insert > Import data from CSV.
--     إن عرض Supabase إنشاء جدول جديد من الملف فاسمه communes_raw واتركه كما يقترح.
--  C) شغّل القسم C: يعرض أسماء الأعمدة. يجب أن تكون:
--     id, commune_name_ascii, commune_name, daira_name_ascii, daira_name,
--     wilaya_code, wilaya_name_ascii, wilaya_name
--     إن اختلفت فأرسل لي لقطة الشاشة ولا تكمل.
--  D) شغّل القسم D (فحوصات). كل الفحوصات يجب أن تنجح.
--  E) فقط عندما تنجح، شغّل القسم E (النقل) ثم F (حذف المؤقت).
-- =====================================================================

-- ---------- A) جدول مؤقت (أعمدة نصية حتى لا يفشل الاستيراد) ----------
create table if not exists communes_raw (
  id text, commune_name_ascii text, commune_name text,
  daira_name_ascii text, daira_name text,
  wilaya_code text, wilaya_name_ascii text, wilaya_name text
);

-- ---------- C) تحقق من الأعمدة بعد الاستيراد ----------
-- select column_name from information_schema.columns
--  where table_schema = 'public' and table_name = 'communes_raw' order by ordinal_position;

-- ---------- D) فحوصات (يجب أن تعطي النتائج المذكورة) ----------
-- 1) العدد الكلي = 1541
-- select count(*) as total from communes_raw;
-- 2) لا ولاية خارج 1-58 (يجب 0)
-- select count(*) from communes_raw where wilaya_code::int not between 1 and 58;
-- 3) كل ولاية فيها بلدية واحدة على الأقل (يجب أن تعود قائمة فارغة)
-- select w.code from wilayas w left join communes_raw c on c.wilaya_code::int = w.code
--  where w.code <= 58 group by w.code having count(c.id) = 0;
-- 4) لا أسماء فارغة (يجب 0)
-- select count(*) from communes_raw where coalesce(trim(commune_name),'') = '' and coalesce(trim(commune_name_ascii),'') = '';
-- 5) لا معرفات مكررة (يجب 0)
-- select count(*) from (select id from communes_raw group by id having count(*) > 1) d;
-- 6) عيّنة للتحقق اليدوي: ولاية الجزائر تذكر المصادر أن فيها 57 بلدية
-- select count(*) from communes_raw where wilaya_code::int = 16;

-- ---------- E) النقل إلى الجدول الحقيقي (بعد نجاح D فقط) ----------
-- insert into communes(source_id, wilaya_code, name_ar, name_fr)
-- select id::int, wilaya_code::int, nullif(trim(commune_name), ''), nullif(trim(commune_name_ascii), '')
--   from communes_raw
-- on conflict (source_id) do update
--   set wilaya_code = excluded.wilaya_code, name_ar = excluded.name_ar, name_fr = excluded.name_fr;
-- select count(*) as communes_loaded from communes;   -- يجب 1541

-- ---------- F) تنظيف ----------
-- drop table communes_raw;

-- ---------- لتحديث البيانات لاحقا ----------
-- أعد الخطوات A-F بملف جديد. on conflict يحدّث الأسماء دون تغيير معرّفات البلديات
-- (الطلبات القديمة تحتفظ باسم البلدية كنص، فلا تتأثر).
