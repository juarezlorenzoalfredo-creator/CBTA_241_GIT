-- CBTA 241 Portal Institucional
-- Migration 004: one-time, non-API bootstrap guard for the initial superadministrator.
-- This function is intentionally not executable by anon/authenticated/service_role.

create or replace function private.bootstrap_initial_superadministrator(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role_id uuid;
  v_existing_superadmins integer;
  v_email text;
  v_email_confirmed_at timestamptz;
  v_is_anonymous boolean;
  v_banned_until timestamptz;
  v_deleted_at timestamptz;
begin
  select u.email, u.email_confirmed_at, u.is_anonymous, u.banned_until, u.deleted_at
    into v_email, v_email_confirmed_at, v_is_anonymous, v_banned_until, v_deleted_at
  from auth.users u
  where u.id = p_user_id;

  if not found then
    raise exception 'bootstrap denied: auth user does not exist';
  end if;

  if v_email is null or btrim(v_email) = '' then
    raise exception 'bootstrap denied: user must have an email';
  end if;

  if coalesce(v_is_anonymous, false) then
    raise exception 'bootstrap denied: anonymous users cannot be administrators';
  end if;

  if v_deleted_at is not null then
    raise exception 'bootstrap denied: deleted user';
  end if;

  if v_banned_until is not null and v_banned_until > now() then
    raise exception 'bootstrap denied: banned user';
  end if;

  if v_email_confirmed_at is null then
    raise exception 'bootstrap denied: email must be confirmed first';
  end if;

  select r.id into v_role_id
  from private.roles r
  where r.key = 'superadministrator';

  if v_role_id is null then
    raise exception 'bootstrap denied: superadministrator role is missing';
  end if;

  select count(*)::int into v_existing_superadmins
  from private.user_roles ur
  where ur.role_id = v_role_id;

  if v_existing_superadmins <> 0 then
    raise exception 'bootstrap denied: initial superadministrator already exists';
  end if;

  insert into private.user_access(user_id, is_active, updated_at)
  values (p_user_id, true, now())
  on conflict (user_id) do update
    set is_active = true,
        disabled_at = null,
        disabled_by = null,
        disabled_reason = null,
        updated_at = now();

  insert into private.user_roles(user_id, role_id, assigned_by)
  values (p_user_id, v_role_id, null);

  insert into private.audit_events(
    actor_id, action, entity_schema, entity_table, entity_id, new_data, result
  ) values (
    null,
    'BOOTSTRAP_SUPERADMIN',
    'private',
    'user_roles',
    p_user_id::text,
    jsonb_build_object('role', 'superadministrator', 'email', v_email),
    'success'
  );
end;
$$;

revoke execute on function private.bootstrap_initial_superadministrator(uuid)
  from public, anon, authenticated, service_role;
