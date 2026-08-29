-- CBTA 241 Portal Institucional
-- Migration 001: core security, RBAC, institutional source of truth, content versioning and audit

create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- Secure defaults: objects in public are opt-in, not auto-exposed.
-- -----------------------------------------------------------------------------
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema private
  revoke select, insert, update, delete on tables from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema private
  revoke usage, select on sequences from public, anon, authenticated, service_role;
alter default privileges for role postgres in schema private
  revoke execute on functions from public, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Private RBAC and account state
-- -----------------------------------------------------------------------------
create table private.roles (
  id uuid primary key default gen_random_uuid(),
  key text not null unique check (key ~ '^[a-z][a-z0-9_]{1,63}$'),
  name text not null,
  description text,
  is_system boolean not null default true,
  created_at timestamptz not null default now()
);

create table private.permissions (
  id uuid primary key default gen_random_uuid(),
  key text not null unique check (key ~ '^[a-z][a-z0-9_.]{1,95}$'),
  description text,
  created_at timestamptz not null default now()
);

create table private.role_permissions (
  role_id uuid not null references private.roles(id) on delete cascade,
  permission_id uuid not null references private.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table private.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null references private.roles(id) on delete cascade,
  assigned_by uuid references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  primary key (user_id, role_id)
);

create index user_roles_user_id_idx on private.user_roles(user_id);
create index role_permissions_role_id_idx on private.role_permissions(role_id);
create index role_permissions_permission_id_idx on private.role_permissions(permission_id);

create table private.user_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  disabled_at timestamptz,
  disabled_by uuid references auth.users(id) on delete set null,
  disabled_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((is_active and disabled_at is null) or (not is_active))
);

revoke all on all tables in schema private from public, anon, authenticated, service_role;

-- Seed permissions.
insert into private.permissions(key, description) values
  ('system.superadmin', 'Full system authority'),
  ('content.read_all', 'Read all editorial content including unpublished content'),
  ('content.create', 'Create editorial content'),
  ('content.edit_own', 'Edit own editorial content'),
  ('content.edit_any', 'Edit editorial content created by any user'),
  ('content.submit', 'Submit content for review'),
  ('content.approve', 'Approve reviewed content'),
  ('content.schedule', 'Schedule approved content'),
  ('content.publish', 'Publish approved or scheduled content'),
  ('content.archive', 'Archive published content'),
  ('content.restore', 'Restore archived content'),
  ('institution.read_private', 'Read non-public institutional source-of-truth data'),
  ('institution.edit', 'Edit institutional source-of-truth data'),
  ('institution.verify', 'Verify controlled and critical institutional data'),
  ('media.manage', 'Manage multimedia assets'),
  ('documents.manage', 'Manage institutional documents'),
  ('users.read', 'Read administrative user directory'),
  ('users.manage', 'Manage administrative users'),
  ('roles.manage', 'Assign and manage RBAC roles'),
  ('audit.read', 'Read protected audit history'),
  ('quality.manage', 'Manage digital quality findings'),
  ('settings.edit', 'Edit ordinary system settings'),
  ('settings.critical_edit', 'Edit critical system settings'),
  ('security.read', 'Read security status and security events')
on conflict (key) do nothing;

insert into private.roles(key, name, description) values
  ('superadministrator', 'Superadministrador', 'Control total y acciones críticas'),
  ('administrator', 'Administrador institucional', 'Administración general del portal'),
  ('publisher', 'Publicador', 'Revisión, aprobación y publicación editorial'),
  ('editor', 'Editor', 'Creación y edición de contenido'),
  ('contributor', 'Colaborador', 'Creación y edición de borradores propios'),
  ('auditor', 'Auditor', 'Consulta de contenido, auditoría y seguridad sin modificación')
on conflict (key) do nothing;

-- Superadministrator receives every permission.
insert into private.role_permissions(role_id, permission_id)
select r.id, p.id
from private.roles r
cross join private.permissions p
where r.key = 'superadministrator'
on conflict do nothing;

-- Administrator receives all operational permissions except the superadmin marker.
insert into private.role_permissions(role_id, permission_id)
select r.id, p.id
from private.roles r
cross join private.permissions p
where r.key = 'administrator'
  and p.key <> 'system.superadmin'
on conflict do nothing;

-- Publisher.
insert into private.role_permissions(role_id, permission_id)
select r.id, p.id
from private.roles r
join private.permissions p on p.key = any(array[
  'content.read_all','content.create','content.edit_any','content.submit',
  'content.approve','content.schedule','content.publish','content.archive','content.restore',
  'institution.read_private'
])
where r.key = 'publisher'
on conflict do nothing;

-- Editor.
insert into private.role_permissions(role_id, permission_id)
select r.id, p.id
from private.roles r
join private.permissions p on p.key = any(array[
  'content.read_all','content.create','content.edit_own','content.edit_any','content.submit'
])
where r.key = 'editor'
on conflict do nothing;

-- Contributor.
insert into private.role_permissions(role_id, permission_id)
select r.id, p.id
from private.roles r
join private.permissions p on p.key = any(array[
  'content.create','content.edit_own','content.submit'
])
where r.key = 'contributor'
on conflict do nothing;

-- Auditor.
insert into private.role_permissions(role_id, permission_id)
select r.id, p.id
from private.roles r
join private.permissions p on p.key = any(array[
  'content.read_all','institution.read_private','audit.read','security.read'
])
where r.key = 'auditor'
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- Security helper functions. They stay outside exposed schemas.
-- -----------------------------------------------------------------------------
create or replace function private.has_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(exists (
    select 1
    from private.user_access ua
    join private.user_roles ur on ur.user_id = ua.user_id
    join private.role_permissions rp on rp.role_id = ur.role_id
    join private.permissions p on p.id = rp.permission_id
    where ua.user_id = (select auth.uid())
      and ua.is_active
      and (p.key = p_permission or p.key = 'system.superadmin')
  ), false);
$$;

create or replace function private.mfa_satisfied()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with privileged as (
    select exists (
      select 1
      from private.user_access ua
      join private.user_roles ur on ur.user_id = ua.user_id
      join private.role_permissions rp on rp.role_id = ur.role_id
      join private.permissions p on p.id = rp.permission_id
      where ua.user_id = (select auth.uid())
        and ua.is_active
        and p.key in ('system.superadmin', 'settings.critical_edit', 'roles.manage')
    ) as required
  )
  select case
    when not privileged.required then true
    else coalesce((select auth.jwt()->>'aal'), 'aal1') = 'aal2'
  end
  from privileged;
$$;

-- Authenticated users need these helpers only for RLS evaluation. The private
-- schema remains outside the Data API exposed schemas and its tables remain revoked.
grant usage on schema private to authenticated;
grant execute on function private.has_permission(text) to authenticated;
grant execute on function private.mfa_satisfied() to authenticated;

-- -----------------------------------------------------------------------------
-- Public profile mirror. Authorization data never lives in user-editable metadata.
-- -----------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text check (display_name is null or char_length(display_name) between 1 and 160),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
revoke all on table public.profiles from anon, authenticated, service_role;
grant select on table public.profiles to authenticated, service_role;
grant update(display_name, avatar_url) on table public.profiles to authenticated;
grant insert, update, delete on table public.profiles to service_role;

create policy profiles_select_own
on public.profiles for select
to authenticated
using ((select auth.uid()) is not null and id = (select auth.uid()));

create policy profiles_update_own
on public.profiles for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles(id, display_name, avatar_url)
  values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', '')), ''),
    nullif(trim(coalesce(new.raw_user_meta_data->>'avatar_url', '')), '')
  )
  on conflict (id) do nothing;

  insert into private.user_access(user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

revoke execute on function private.handle_new_user() from public, anon, authenticated, service_role;

drop trigger if exists on_auth_user_created_cbta241 on auth.users;
create trigger on_auth_user_created_cbta241
after insert on auth.users
for each row execute function private.handle_new_user();

-- Backfill mirrors for any pre-existing auth users, without assigning roles.
insert into public.profiles(id, display_name, avatar_url)
select
  u.id,
  nullif(trim(coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '')), ''),
  nullif(trim(coalesce(u.raw_user_meta_data->>'avatar_url', '')), '')
from auth.users u
on conflict (id) do nothing;

insert into private.user_access(user_id)
select u.id from auth.users u
on conflict (user_id) do nothing;

-- -----------------------------------------------------------------------------
-- Institutional Source of Truth
-- -----------------------------------------------------------------------------
create table public.institutional_data (
  id uuid primary key default gen_random_uuid(),
  key text not null unique check (key ~ '^[a-z][a-z0-9_.]{1,95}$'),
  label text not null check (char_length(label) between 1 and 180),
  value jsonb not null,
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified','in_review','verified','outdated')),
  classification text not null default 'normal'
    check (classification in ('normal','controlled','critical')),
  source_reference text,
  responsible_area text,
  is_public boolean not null default false,
  is_active boolean not null default true,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,
  review_due_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (verified_at is null or verification_status = 'verified')
);

create index institutional_data_public_idx
  on public.institutional_data(is_public, is_active, verification_status)
  where deleted_at is null;
create index institutional_data_review_due_idx
  on public.institutional_data(review_due_at)
  where deleted_at is null and is_active;

alter table public.institutional_data enable row level security;
revoke all on table public.institutional_data from anon, authenticated, service_role;
grant select on table public.institutional_data to anon, authenticated, service_role;
grant insert, update on table public.institutional_data to authenticated, service_role;
grant delete on table public.institutional_data to service_role;

create policy institutional_public_read
on public.institutional_data for select
to anon, authenticated
using (
  is_public
  and is_active
  and deleted_at is null
  and verification_status = 'verified'
);

create policy institutional_admin_read
on public.institutional_data for select
to authenticated
using ((select private.has_permission('institution.read_private')));

create policy institutional_admin_insert
on public.institutional_data for insert
to authenticated
with check ((select private.has_permission('institution.edit')));

create policy institutional_admin_update
on public.institutional_data for update
to authenticated
using ((select private.has_permission('institution.edit')))
with check ((select private.has_permission('institution.edit')));

create policy institutional_privileged_mfa_insert
on public.institutional_data as restrictive for insert
to authenticated
with check ((select private.mfa_satisfied()));

create policy institutional_privileged_mfa_update
on public.institutional_data as restrictive for update
to authenticated
using ((select private.mfa_satisfied()))
with check ((select private.mfa_satisfied()));

create or replace function private.enforce_institutional_data_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if (select auth.uid()) is not null then
      new.created_by := coalesce(new.created_by, (select auth.uid()));
      new.updated_by := (select auth.uid());
      if new.verification_status = 'verified' and not private.has_permission('institution.verify') then
        raise exception 'permission denied: institution.verify required';
      end if;
      if new.verification_status = 'verified' then
        new.verified_by := (select auth.uid());
        new.verified_at := now();
      else
        new.verified_by := null;
        new.verified_at := null;
      end if;
    end if;
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := now();
    return new;
  end if;

  if (select auth.uid()) is not null then
    if new.created_by is distinct from old.created_by then
      raise exception 'created_by is immutable';
    end if;
    new.updated_by := (select auth.uid());

    -- Any changed official value must be re-reviewed. Verification is a
    -- separate explicit step and cannot be inherited accidentally.
    if new.value is distinct from old.value then
      new.verification_status := 'in_review';
      new.verified_by := null;
      new.verified_at := null;
    elsif new.verification_status = 'verified' and old.verification_status <> 'verified' then
      if not private.has_permission('institution.verify') then
        raise exception 'permission denied: institution.verify required';
      end if;
      new.verified_by := (select auth.uid());
      new.verified_at := now();
    elsif new.verification_status <> 'verified' then
      new.verified_by := null;
      new.verified_at := null;
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.enforce_institutional_data_change() from public, anon, authenticated, service_role;

create trigger institutional_data_guard
before insert or update on public.institutional_data
for each row execute function private.enforce_institutional_data_change();

-- -----------------------------------------------------------------------------
-- Editorial content, workflow and immutable version snapshots
-- -----------------------------------------------------------------------------
create table public.contents (
  id uuid primary key default gen_random_uuid(),
  content_type text not null check (content_type ~ '^[a-z][a-z0-9_]{1,49}$'),
  title text not null check (char_length(title) between 1 and 220),
  slug text not null check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and char_length(slug) <= 180),
  summary text,
  body jsonb not null default '{}'::jsonb,
  seo jsonb not null default '{}'::jsonb,
  status text not null default 'draft'
    check (status in ('draft','in_review','approved','scheduled','published','archived')),
  priority text not null default 'normal'
    check (priority in ('normal','featured','priority','critical')),
  owner_area text,
  revision bigint not null default 1 check (revision > 0),
  publish_at timestamptz,
  expires_at timestamptz,
  published_at timestamptz,
  archived_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (expires_at is null or publish_at is null or expires_at > publish_at),
  check (status <> 'scheduled' or publish_at is not null),
  check (status <> 'published' or published_at is not null)
);

create unique index contents_type_slug_active_uidx
  on public.contents(content_type, lower(slug))
  where deleted_at is null;
create index contents_public_feed_idx
  on public.contents(status, publish_at, expires_at, updated_at desc)
  where deleted_at is null;
create index contents_created_by_idx on public.contents(created_by);
create index contents_updated_at_idx on public.contents(updated_at desc);

create table public.content_versions (
  id uuid primary key default gen_random_uuid(),
  content_id uuid not null references public.contents(id) on delete cascade,
  revision bigint not null,
  snapshot jsonb not null,
  changed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(content_id, revision)
);

create index content_versions_content_idx
  on public.content_versions(content_id, revision desc);

create table public.content_relations (
  source_content_id uuid not null references public.contents(id) on delete cascade,
  target_content_id uuid not null references public.contents(id) on delete restrict,
  relation_type text not null check (relation_type ~ '^[a-z][a-z0-9_]{1,63}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(source_content_id, target_content_id, relation_type),
  check (source_content_id <> target_content_id)
);

create index content_relations_target_idx on public.content_relations(target_content_id);

alter table public.contents enable row level security;
alter table public.content_versions enable row level security;
alter table public.content_relations enable row level security;

revoke all on table public.contents, public.content_versions, public.content_relations from anon, authenticated, service_role;
grant select on table public.contents to anon, authenticated, service_role;
grant insert, update on table public.contents to authenticated, service_role;
grant delete on table public.contents to service_role;
grant select on table public.content_versions to authenticated, service_role;
grant insert, update, delete on table public.content_versions to service_role;
grant select, insert, delete on table public.content_relations to authenticated, service_role;
grant update on table public.content_relations to service_role;

create or replace function private.can_read_content(p_content_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(exists (
    select 1
    from public.contents c
    where c.id = p_content_id
      and c.deleted_at is null
      and (
        private.has_permission('content.read_all')
        or c.created_by = (select auth.uid())
      )
  ), false);
$$;

grant execute on function private.can_read_content(uuid) to authenticated;

create policy contents_public_read
on public.contents for select
to anon, authenticated
using (
  deleted_at is null
  and status = 'published'
  and published_at <= now()
  and (expires_at is null or expires_at > now())
);

create policy contents_admin_read
on public.contents for select
to authenticated
using (
  (select private.has_permission('content.read_all'))
  or created_by = (select auth.uid())
);

create policy contents_admin_insert
on public.contents for insert
to authenticated
with check (
  (select private.has_permission('content.create'))
  and created_by = (select auth.uid())
);

create policy contents_admin_update
on public.contents for update
to authenticated
using (
  (select private.has_permission('content.edit_any'))
  or ((select private.has_permission('content.edit_own')) and created_by = (select auth.uid()))
)
with check (
  (select private.has_permission('content.edit_any'))
  or ((select private.has_permission('content.edit_own')) and created_by = (select auth.uid()))
);

create policy contents_privileged_mfa_insert
on public.contents as restrictive for insert
to authenticated
with check ((select private.mfa_satisfied()));

create policy contents_privileged_mfa_update
on public.contents as restrictive for update
to authenticated
using ((select private.mfa_satisfied()))
with check ((select private.mfa_satisfied()));

create policy content_versions_admin_read
on public.content_versions for select
to authenticated
using ((select private.can_read_content(content_id)));

create policy content_relations_admin_read
on public.content_relations for select
to authenticated
using ((select private.can_read_content(source_content_id)));

create policy content_relations_admin_insert
on public.content_relations for insert
to authenticated
with check (
  (select private.has_permission('content.edit_any'))
  and (select private.can_read_content(source_content_id))
  and (select private.can_read_content(target_content_id))
);

create policy content_relations_admin_delete
on public.content_relations for delete
to authenticated
using ((select private.has_permission('content.edit_any')));

create or replace function private.enforce_content_workflow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  old_status text;
  new_status text;
begin
  if tg_op = 'INSERT' then
    if (select auth.uid()) is not null then
      new.created_by := coalesce(new.created_by, (select auth.uid()));
      new.updated_by := (select auth.uid());
      if new.status <> 'draft' then
        raise exception 'new content must start as draft';
      end if;
    end if;
    new.revision := 1;
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := now();
    return new;
  end if;

  old_status := old.status;
  new_status := new.status;

  if (select auth.uid()) is not null then
    if new.created_by is distinct from old.created_by then
      raise exception 'created_by is immutable';
    end if;
    new.updated_by := (select auth.uid());

    if new_status is distinct from old_status then
      if old_status = 'draft' and new_status = 'in_review' then
        if not private.has_permission('content.submit') then
          raise exception 'permission denied: content.submit required';
        end if;
      elsif old_status = 'in_review' and new_status = 'draft' then
        null;
      elsif old_status = 'in_review' and new_status = 'approved' then
        if not private.has_permission('content.approve') then
          raise exception 'permission denied: content.approve required';
        end if;
      elsif old_status = 'approved' and new_status = 'scheduled' then
        if not private.has_permission('content.schedule') then
          raise exception 'permission denied: content.schedule required';
        end if;
        if new.publish_at is null then
          raise exception 'publish_at is required for scheduled content';
        end if;
      elsif old_status in ('approved','scheduled') and new_status = 'published' then
        if not private.has_permission('content.publish') then
          raise exception 'permission denied: content.publish required';
        end if;
        new.published_at := coalesce(new.published_at, now());
      elsif old_status = 'published' and new_status = 'archived' then
        if not private.has_permission('content.archive') then
          raise exception 'permission denied: content.archive required';
        end if;
        new.archived_at := now();
      elsif old_status = 'archived' and new_status = 'approved' then
        if not private.has_permission('content.restore') then
          raise exception 'permission denied: content.restore required';
        end if;
        new.archived_at := null;
      else
        raise exception 'invalid editorial status transition: % -> %', old_status, new_status;
      end if;
    end if;
  end if;

  new.revision := old.revision + 1;
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.enforce_content_workflow() from public, anon, authenticated, service_role;

create trigger contents_workflow_guard
before insert or update on public.contents
for each row execute function private.enforce_content_workflow();

create or replace function private.capture_content_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.content_versions(content_id, revision, snapshot, changed_by)
  values (new.id, new.revision, to_jsonb(new), coalesce(new.updated_by, new.created_by));
  return new;
end;
$$;

revoke execute on function private.capture_content_version() from public, anon, authenticated, service_role;

create trigger contents_capture_version
after insert or update on public.contents
for each row execute function private.capture_content_version();

-- -----------------------------------------------------------------------------
-- Append-only audit trail. No client role receives direct privileges.
-- -----------------------------------------------------------------------------
create table private.audit_events (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default now(),
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_schema text not null,
  entity_table text not null,
  entity_id text,
  old_data jsonb,
  new_data jsonb,
  result text not null default 'success' check (result in ('success','denied','error')),
  request_id text
);

create index audit_events_time_idx on private.audit_events(occurred_at desc);
create index audit_events_actor_idx on private.audit_events(actor_id, occurred_at desc);
create index audit_events_entity_idx on private.audit_events(entity_table, entity_id, occurred_at desc);

revoke all on table private.audit_events from public, anon, authenticated, service_role;

create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  headers jsonb := '{}'::jsonb;
  rid text;
  entity text;
begin
  begin
    headers := coalesce(nullif(current_setting('request.headers', true), '')::jsonb, '{}'::jsonb);
  exception when others then
    headers := '{}'::jsonb;
  end;
  rid := headers->>'x-request-id';

  if tg_op = 'DELETE' then
    entity := coalesce(to_jsonb(old)->>'id', to_jsonb(old)->>'key');
    insert into private.audit_events(actor_id, action, entity_schema, entity_table, entity_id, old_data, result, request_id)
    values ((select auth.uid()), 'DELETE', tg_table_schema, tg_table_name, entity, to_jsonb(old), 'success', rid);
    return old;
  elsif tg_op = 'INSERT' then
    entity := coalesce(to_jsonb(new)->>'id', to_jsonb(new)->>'key');
    insert into private.audit_events(actor_id, action, entity_schema, entity_table, entity_id, new_data, result, request_id)
    values ((select auth.uid()), 'INSERT', tg_table_schema, tg_table_name, entity, to_jsonb(new), 'success', rid);
    return new;
  else
    entity := coalesce(to_jsonb(new)->>'id', to_jsonb(new)->>'key');
    insert into private.audit_events(actor_id, action, entity_schema, entity_table, entity_id, old_data, new_data, result, request_id)
    values ((select auth.uid()), 'UPDATE', tg_table_schema, tg_table_name, entity, to_jsonb(old), to_jsonb(new), 'success', rid);
    return new;
  end if;
end;
$$;

revoke execute on function private.audit_row_change() from public, anon, authenticated, service_role;

create trigger institutional_data_audit
after insert or update or delete on public.institutional_data
for each row execute function private.audit_row_change();

create trigger contents_audit
after insert or update or delete on public.contents
for each row execute function private.audit_row_change();

create trigger content_relations_audit
after insert or delete on public.content_relations
for each row execute function private.audit_row_change();

-- Final explicit grants for internal RLS helper functions only.
revoke all on all functions in schema private from public, anon, authenticated, service_role;
grant execute on function private.has_permission(text) to authenticated;
grant execute on function private.mfa_satisfied() to authenticated;
grant execute on function private.can_read_content(uuid) to authenticated;
grant usage on schema private to authenticated;

-- The service role remains server-only and may operate on exposed application
-- tables when explicitly used by trusted server code. Private tables stay non-API.
grant select, insert, update, delete on table public.profiles to service_role;
grant select, insert, update, delete on table public.institutional_data to service_role;
grant select, insert, update, delete on table public.contents to service_role;
grant select, insert, update, delete on table public.content_versions to service_role;
grant select, insert, update, delete on table public.content_relations to service_role;
