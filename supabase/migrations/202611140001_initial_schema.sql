-- Gestão de Projetos e Demandas TI
-- PostgreSQL / Supabase
-- Execute no SQL Editor de um projeto Supabase novo.

create extension if not exists pgcrypto;

-- Perfil de aplicação: a autenticação/senha fica em auth.users.
-- Nunca armazenar senha nesta tabela.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  department text,
  role text not null default 'Colaborador'
    check (role in ('Administrador','Gestor','Colaborador','Visualizador')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, department, role)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name',''),
      split_part(coalesce(new.email, 'usuario'), '@', 1)
    ),
    nullif(new.raw_user_meta_data ->> 'department',''),
    'Colaborador'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute procedure public.handle_new_auth_user();

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.id = (select auth.uid())
    and p.active = true
  limit 1;
$$;

revoke all on function public.current_app_role() from public;
grant execute on function public.current_app_role() to authenticated;

-- Iniciativas: PROJETO ou DEMANDA.
create table if not exists public.initiatives (
  id uuid primary key default gen_random_uuid(),
  legacy_id text unique,
  type text not null default 'PROJETO'
    check (type in ('PROJETO','DEMANDA')),
  name text not null,
  summary text not null default '',
  owner_name text,
  owner_user_id uuid references public.profiles(id) on delete set null,
  priority text not null default 'Média',
  start_date date,
  end_date date,
  status text not null default 'AGUARDANDO',
  progress numeric(5,2) not null default 0
    check (progress >= 0 and progress <= 100),
  auto_progress boolean not null default false,
  completed_at date,
  work_weekends boolean not null default false,
  show_in_daily boolean not null default false,
  comment text not null default '',
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Tarefas/subtarefas pertencentes a uma iniciativa.
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  initiative_id uuid not null references public.initiatives(id) on delete cascade,
  legacy_id text,
  name text not null,
  owner_name text,
  owner_user_id uuid references public.profiles(id) on delete set null,
  progress numeric(5,2) not null default 0
    check (progress >= 0 and progress <= 100),
  status text not null default 'AGUARDANDO',
  start_date date,
  end_date date,
  completed_at date,
  done boolean not null default false,
  sort_order integer not null default 0,
  history jsonb not null default '[]'::jsonb,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (initiative_id, legacy_id)
);

-- Pautas da DAILY: os nomes correspondem aos campos já existentes no HTML.
create table if not exists public.daily_meetings (
  meeting_date date primary key,
  daily_lead text not null default '',
  daily_people text not null default '',
  daily_done text not null default '',
  daily_priorities text not null default '',
  daily_tickets text not null default '',
  daily_projects text not null default '',
  daily_blockers text not null default '',
  daily_decisions text not null default '',
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Status e cores configuráveis pela administração.
create table if not exists public.status_definitions (
  name text primary key,
  background_color text not null default '#eef2ff',
  text_color text not null default '#454f91',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.status_definitions(name, background_color, text_color, sort_order)
values
 ('AGUARDANDO','#fff7df','#9b7100',1),
 ('EM ANDAMENTO','#e8f2ff','#1769aa',2),
 ('ATRASADO','#fff0f0','#c0392b',3),
 ('CONCLUÍDO','#e8f7ef','#12834f',4),
 ('CANCELADO','#eef0f3','#667085',5)
on conflict (name) do nothing;

-- Trilha de auditoria: escrita somente por triggers, leitura por usuários autenticados.
create table if not exists public.activity_log (
  id bigint generated always as identity primary key,
  entity_type text not null,
  entity_id text not null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  actor_id uuid references public.profiles(id) on delete set null,
  old_data jsonb,
  new_data jsonb,
  occurred_at timestamptz not null default now()
);

create or replace function public.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_json jsonb;
  new_json jsonb;
  row_id text;
begin
  if tg_op = 'INSERT' then
    new_json := to_jsonb(new);
    row_id := coalesce(new_json ->> 'id', new_json ->> 'meeting_date', new_json ->> 'name');
  elsif tg_op = 'UPDATE' then
    old_json := to_jsonb(old);
    new_json := to_jsonb(new);
    row_id := coalesce(new_json ->> 'id', new_json ->> 'meeting_date', new_json ->> 'name');
  else
    old_json := to_jsonb(old);
    row_id := coalesce(old_json ->> 'id', old_json ->> 'meeting_date', old_json ->> 'name');
  end if;

  insert into public.activity_log(entity_type, entity_id, action, actor_id, old_data, new_data)
  values (tg_table_name, coalesce(row_id,'unknown'), tg_op, (select auth.uid()), old_json, new_json);

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

-- updated_at
drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute procedure public.set_updated_at();

drop trigger if exists initiatives_set_updated_at on public.initiatives;
create trigger initiatives_set_updated_at before update on public.initiatives
for each row execute procedure public.set_updated_at();

drop trigger if exists tasks_set_updated_at on public.tasks;
create trigger tasks_set_updated_at before update on public.tasks
for each row execute procedure public.set_updated_at();

drop trigger if exists daily_meetings_set_updated_at on public.daily_meetings;
create trigger daily_meetings_set_updated_at before update on public.daily_meetings
for each row execute procedure public.set_updated_at();

drop trigger if exists status_definitions_set_updated_at on public.status_definitions;
create trigger status_definitions_set_updated_at before update on public.status_definitions
for each row execute procedure public.set_updated_at();

-- Auditoria
drop trigger if exists initiatives_audit on public.initiatives;
create trigger initiatives_audit after insert or update or delete on public.initiatives
for each row execute procedure public.audit_row_change();

drop trigger if exists tasks_audit on public.tasks;
create trigger tasks_audit after insert or update or delete on public.tasks
for each row execute procedure public.audit_row_change();

drop trigger if exists daily_meetings_audit on public.daily_meetings;
create trigger daily_meetings_audit after insert or update or delete on public.daily_meetings
for each row execute procedure public.audit_row_change();

drop trigger if exists status_definitions_audit on public.status_definitions;
create trigger status_definitions_audit after insert or update or delete on public.status_definitions
for each row execute procedure public.audit_row_change();

-- RLS em todas as tabelas acessíveis pela aplicação.
alter table public.profiles enable row level security;
alter table public.initiatives enable row level security;
alter table public.tasks enable row level security;
alter table public.daily_meetings enable row level security;
alter table public.status_definitions enable row level security;
alter table public.activity_log enable row level security;

-- Perfis: cada pessoa lê o próprio perfil; administradores/gestores podem consultar a equipe.
drop policy if exists profiles_read_team on public.profiles;
create policy profiles_read_team on public.profiles
for select to authenticated
using (
  id = (select auth.uid())
  or (select public.current_app_role()) in ('Administrador','Gestor')
);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

-- Iniciativas: equipe autenticada compartilha leitura e edição; exclusão restrita à gestão.
drop policy if exists initiatives_select_team on public.initiatives;
create policy initiatives_select_team on public.initiatives
for select to authenticated using (true);

drop policy if exists initiatives_insert_team on public.initiatives;
create policy initiatives_insert_team on public.initiatives
for insert to authenticated with check (
  (select public.current_app_role()) in ('Administrador','Gestor','Colaborador')
);

drop policy if exists initiatives_update_team on public.initiatives;
create policy initiatives_update_team on public.initiatives
for update to authenticated
using ((select public.current_app_role()) in ('Administrador','Gestor','Colaborador'))
with check ((select public.current_app_role()) in ('Administrador','Gestor','Colaborador'));

drop policy if exists initiatives_delete_managers on public.initiatives;
create policy initiatives_delete_managers on public.initiatives
for delete to authenticated
using ((select public.current_app_role()) in ('Administrador','Gestor'));

-- Tarefas
drop policy if exists tasks_select_team on public.tasks;
create policy tasks_select_team on public.tasks
for select to authenticated using (true);

drop policy if exists tasks_insert_team on public.tasks;
create policy tasks_insert_team on public.tasks
for insert to authenticated with check (
  (select public.current_app_role()) in ('Administrador','Gestor','Colaborador')
);

drop policy if exists tasks_update_team on public.tasks;
create policy tasks_update_team on public.tasks
for update to authenticated
using ((select public.current_app_role()) in ('Administrador','Gestor','Colaborador'))
with check ((select public.current_app_role()) in ('Administrador','Gestor','Colaborador'));

drop policy if exists tasks_delete_managers on public.tasks;
create policy tasks_delete_managers on public.tasks
for delete to authenticated
using ((select public.current_app_role()) in ('Administrador','Gestor'));

-- DAILY
drop policy if exists daily_select_team on public.daily_meetings;
create policy daily_select_team on public.daily_meetings
for select to authenticated using (true);

drop policy if exists daily_insert_team on public.daily_meetings;
create policy daily_insert_team on public.daily_meetings
for insert to authenticated with check (
  (select public.current_app_role()) in ('Administrador','Gestor','Colaborador')
);

drop policy if exists daily_update_team on public.daily_meetings;
create policy daily_update_team on public.daily_meetings
for update to authenticated
using ((select public.current_app_role()) in ('Administrador','Gestor','Colaborador'))
with check ((select public.current_app_role()) in ('Administrador','Gestor','Colaborador'));

drop policy if exists daily_delete_managers on public.daily_meetings;
create policy daily_delete_managers on public.daily_meetings
for delete to authenticated
using ((select public.current_app_role()) in ('Administrador','Gestor'));

-- Status: leitura para equipe; manutenção apenas por Administrador/Gestor.
drop policy if exists statuses_select_team on public.status_definitions;
create policy statuses_select_team on public.status_definitions
for select to authenticated using (true);

drop policy if exists statuses_insert_managers on public.status_definitions;
create policy statuses_insert_managers on public.status_definitions
for insert to authenticated with check (
  (select public.current_app_role()) in ('Administrador','Gestor')
);

drop policy if exists statuses_update_managers on public.status_definitions;
create policy statuses_update_managers on public.status_definitions
for update to authenticated
using ((select public.current_app_role()) in ('Administrador','Gestor'))
with check ((select public.current_app_role()) in ('Administrador','Gestor'));

drop policy if exists statuses_delete_managers on public.status_definitions;
create policy statuses_delete_managers on public.status_definitions
for delete to authenticated
using ((select public.current_app_role()) in ('Administrador','Gestor'));

-- Auditoria: somente leitura; triggers escrevem com privilégio do proprietário.
drop policy if exists activity_log_select_team on public.activity_log;
create policy activity_log_select_team on public.activity_log
for select to authenticated using (true);

-- Grants mínimos para a API do Supabase.
grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant update (full_name, department) on public.profiles to authenticated;
grant select, insert, update, delete on public.initiatives to authenticated;
grant select, insert, update, delete on public.tasks to authenticated;
grant select, insert, update, delete on public.daily_meetings to authenticated;
grant select, insert, update, delete on public.status_definitions to authenticated;
grant select on public.activity_log to authenticated;
grant usage, select on sequence public.activity_log_id_seq to authenticated;

create index if not exists initiatives_status_idx on public.initiatives(status);
create index if not exists initiatives_end_date_idx on public.initiatives(end_date);
create index if not exists initiatives_show_in_daily_idx on public.initiatives(show_in_daily)
  where show_in_daily = true;
create index if not exists tasks_initiative_id_idx on public.tasks(initiative_id);
create index if not exists tasks_status_idx on public.tasks(status);
create index if not exists activity_log_entity_idx on public.activity_log(entity_type, entity_id);
create index if not exists activity_log_occurred_at_idx on public.activity_log(occurred_at desc);
