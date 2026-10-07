-- Treenisovelluksen pilvitallennus. Ajetaan kerran Supabasen SQL-editorissa.
-- Taulut ovat RLS:n takana ilman käytäntöjä: selain pääsee dataan vain alla
-- olevien funktioiden kautta, ja jokainen niistä vaatii käyttäjän linkkikoodin.

create table if not exists public.treeni_users (
  code text primary key,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.treeni_docs (
  code text not null references public.treeni_users(code) on delete cascade,
  id text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (code, id)
);

alter table public.treeni_users enable row level security;
alter table public.treeni_docs enable row level security;

create or replace function public.treeni_pull(p_code text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (select 1 from treeni_users where code = p_code) then
      jsonb_build_object('ok', true, 'docs',
        coalesce((select jsonb_object_agg(id, data) from treeni_docs where code = p_code), '{}'::jsonb))
    else jsonb_build_object('ok', false)
  end;
$$;

create or replace function public.treeni_put(p_code text, p_id text, p_data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from treeni_users where code = p_code) then
    return jsonb_build_object('ok', false);
  end if;
  if p_id !~ '^(config|\d{4}-\d{2}-\d{2}-[AP])$' or length(p_data::text) > 200000 then
    raise exception 'invalid_argument';
  end if;
  insert into treeni_docs (code, id, data) values (p_code, p_id, p_data)
  on conflict (code, id) do update set data = excluded.data, updated_at = now();
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.treeni_del(p_code text, p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from treeni_users where code = p_code) then
    return jsonb_build_object('ok', false);
  end if;
  delete from treeni_docs where code = p_code and id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.treeni_pull(text) from public;
revoke all on function public.treeni_put(text, text, jsonb) from public;
revoke all on function public.treeni_del(text, text) from public;
grant execute on function public.treeni_pull(text) to anon, authenticated;
grant execute on function public.treeni_put(text, text, jsonb) to anon, authenticated;
grant execute on function public.treeni_del(text, text) to anon, authenticated;
