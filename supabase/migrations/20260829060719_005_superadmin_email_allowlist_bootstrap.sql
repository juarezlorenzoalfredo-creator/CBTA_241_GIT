-- CBTA 241 Portal Institucional
-- Migration 005: one-time SUPERADMIN bootstrap bound to an approved email fingerprint.

create table if not exists private.superadmin_bootstrap_identity (
  singleton boolean primary key default true check (singleton),
  email_sha256 bytea not null unique,
  created_at timestamptz not null default now(),
  consumed_at timestamptz,
  consumed_by uuid references auth.users(id) on delete set null,
  check ((consumed_at is null and consumed_by is null) or (consumed_at is not null and consumed_by is not null))
);

alter table private.superadmin_bootstrap_identity enable row level security;
revoke all on table private.superadmin_bootstrap_identity from public, anon, authenticated, service_role;

insert into private.superadmin_bootstrap_identity(singleton, email_sha256)
values (true, decode('ae96df648c47167723de76f37ffdeaab11526f451c608d6f0e81ab8622017f67','hex'))
on conflict (singleton) do update
set email_sha256 = excluded.email_sha256
where private.superadmin_bootstrap_identity.consumed_at is null;

create or replace function private.try_bootstrap_superadmin_from_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  bootstrap_row private.superadmin_bootstrap_identity%rowtype;
  superadmin_role_id uuid;
  already_exists boolean;
  candidate_hash bytea;
begin
  if new.email is null
     or new.is_anonymous
     or new.deleted_at is not null
     or (new.banned_until is not null and new.banned_until > now())
     or coalesce(new.email_confirmed_at, new.confirmed_at) is null then
    return new;
  end if;

  select * into bootstrap_row
  from private.superadmin_bootstrap_identity
  where singleton = true
  for update;

  if not found or bootstrap_row.consumed_at is not null then
    return new;
  end if;

  candidate_hash := extensions.digest(lower(btrim(new.email)), 'sha256');
  if candidate_hash is distinct from bootstrap_row.email_sha256 then
    return new;
  end if;

  select r.id into superadmin_role_id
  from private.roles r
  where r.key = 'superadministrator';

  if superadmin_role_id is null then
    raise exception 'superadministrator role is missing';
  end if;

  select exists (
    select 1
    from private.user_roles ur
    join private.roles r on r.id = ur.role_id
    where r.key = 'superadministrator'
  ) into already_exists;

  if already_exists then
    return new;
  end if;

  insert into private.user_access(user_id, is_active)
  values (new.id, true)
  on conflict (user_id) do update
    set is_active = true,
        disabled_at = null,
        disabled_by = null,
        disabled_reason = null,
        updated_at = now();

  insert into private.user_roles(user_id, role_id, assigned_by)
  values (new.id, superadmin_role_id, null)
  on conflict (user_id, role_id) do nothing;

  update private.superadmin_bootstrap_identity
  set consumed_at = now(), consumed_by = new.id
  where singleton = true and consumed_at is null;

  insert into private.audit_events(
    actor_id, action, entity_schema, entity_table, entity_id, new_data, result
  ) values (
    new.id,
    'BOOTSTRAP_SUPERADMIN',
    'auth',
    'users',
    new.id::text,
    jsonb_build_object(
      'role', 'superadministrator',
      'bootstrap_method', 'approved_email_sha256',
      'email_confirmed', true
    ),
    'success'
  );

  return new;
end;
$$;

revoke execute on function private.try_bootstrap_superadmin_from_auth_user() from public, anon, authenticated, service_role;

drop trigger if exists cbta241_try_bootstrap_superadmin_on_auth_user on auth.users;
create trigger cbta241_try_bootstrap_superadmin_on_auth_user
after insert or update of email, email_confirmed_at, confirmed_at, banned_until, deleted_at on auth.users
for each row execute function private.try_bootstrap_superadmin_from_auth_user();
