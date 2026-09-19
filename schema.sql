-- ליגת המספרים – שמירת התקדמות ב-Supabase
-- מריצים פעם אחת: Supabase Dashboard → SQL Editor → New query → הדבקה → Run.
--
-- העיקרון: הטבלה סגורה לגמרי מבחוץ. הדף מדבר רק עם שתי פונקציות,
-- וכל אחת מהן דורשת קוד שחקן. בלי הקוד אי אפשר לקרוא או לרשום כלום,
-- ואי אפשר לקבל רשימה של שחקנים.
-- קוד שחקן: 12 תווים (60 ביט אקראיים), למשל K7QM-2XRA-9TPD.

create table if not exists public.league_progress (
  code        text primary key
              check (code ~ '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$'),
  data        jsonb not null check (jsonb_typeof(data) = 'object'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- RLS בלי אף policy = אין גישה ישירה לטבלה דרך ה-API. גם ההרשאות נשללות.
alter table public.league_progress enable row level security;
revoke all on table public.league_progress from public;
revoke all on table public.league_progress from anon, authenticated;

-- קריאה: מחזירה את ההתקדמות של קוד אחד, או null אם אין כזה.
create or replace function public.get_progress(p_code text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select lp.data from public.league_progress lp where lp.code = p_code;
$$;

-- שמירה: יוצרת או מעדכנת את ההתקדמות של קוד אחד.
create or replace function public.save_progress(p_code text, p_data jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  if p_code is null
     or p_code !~ '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$' then
    raise exception 'invalid player code' using errcode = '22023';
  end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' then
    raise exception 'progress must be a JSON object' using errcode = '22023';
  end if;
  if octet_length(p_data::text) > 65536 then
    raise exception 'progress too large' using errcode = '54000';
  end if;
  insert into public.league_progress as lp (code, data)
  values (p_code, p_data)
  on conflict (code) do update
    set data = excluded.data, updated_at = now();
end;
$$;

-- רק שתי הפונקציות פתוחות לדף, ורק לתפקיד anon (האתר לא מחבר משתמשים).
revoke all on function public.get_progress(text)        from public;
revoke all on function public.save_progress(text, jsonb) from public;
revoke all on function public.get_progress(text)        from authenticated;
revoke all on function public.save_progress(text, jsonb) from authenticated;
grant execute on function public.get_progress(text)        to anon;
grant execute on function public.save_progress(text, jsonb) to anon;
-- הערה: ב-Security Advisor יופיעו אזהרות "RLS Enabled No Policy" ו-"SECURITY DEFINER function executable by anon".
-- שתיהן מכוונות: הטבלה סגורה בכוונה, והפונקציות האלה הן הדלת היחידה (עם בדיקת קוד, סוג וגודל).

-- אופציונלי – ניקוי שחקנים שלא שיחקו שנה (דורש את ההרחבה pg_cron):
-- select cron.schedule('league-cleanup', '0 3 * * 0',
--   $$delete from public.league_progress where updated_at < now() - interval '1 year'$$);
