-- CBTA 241 Portal Institucional
-- Migration 008: invitation-only administrative identities and bootstrap hardening.
-- The administrative portal has no public sign-up surface. Auth user creation must
-- originate from an explicit Supabase invitation, which also prevents a third party
-- from pre-registering the bootstrap email and blocking the one-time invite flow.

create or replace function private.enforce_invitation_only_auth_user_creation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.is_anonymous, false)
     or new.email is null
     or btrim(new.email) = ''
     or new.invited_at is null then
    raise exception 'administrative account creation requires an invitation';
  end if;

  return new;
end;
$$;

revoke execute on function private.enforce_invitation_only_auth_user_creation()
  from public, anon, authenticated, service_role;

drop trigger if exists cbta241_require_invited_auth_user on auth.users;
create trigger cbta241_require_invited_auth_user
before insert on auth.users
for each row execute function private.enforce_invitation_only_auth_user_creation();

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
     or new.invited_at is null
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
      'bootstrap_method', 'approved_invited_email_sha256',
      'email_confirmed', true,
      'invitation_required', true
    ),
    'success'
  );

  return new;
end;
$$;

revoke execute on function private.try_bootstrap_superadmin_from_auth_user()
  from public, anon, authenticated, service_role;
