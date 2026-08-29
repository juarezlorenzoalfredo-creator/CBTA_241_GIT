-- CBTA 241 Portal Institucional
-- Migration 007: least-privilege self-read policies + security-invoker admin context RPC.
-- Goal: allow the admin application to determine its own access context without
-- exposing private tables through the Data API and without an exposed SECURITY
-- DEFINER RPC.

-- Authenticated sessions may read only the authorization rows required to
-- describe their own account. The private schema remains outside exposed API schemas.
grant select on table private.user_access to authenticated;
grant select on table private.user_roles to authenticated;
grant select on table private.roles to authenticated;
grant select on table private.role_permissions to authenticated;
grant select on table private.permissions to authenticated;

-- Own account state only.
drop policy if exists user_access_self_read on private.user_access;
create policy user_access_self_read
on private.user_access
for select
to authenticated
using ((select auth.uid()) is not null and user_id = (select auth.uid()));

-- Own role assignments only.
drop policy if exists user_roles_self_read on private.user_roles;
create policy user_roles_self_read
on private.user_roles
for select
to authenticated
using ((select auth.uid()) is not null and user_id = (select auth.uid()));

-- Only role definitions actually assigned to the current user.
drop policy if exists roles_assigned_self_read on private.roles;
create policy roles_assigned_self_read
on private.roles
for select
to authenticated
using (
  exists (
    select 1
    from private.user_roles ur
    where ur.role_id = roles.id
      and ur.user_id = (select auth.uid())
  )
);

-- Only permission mappings belonging to roles assigned to the current user.
drop policy if exists role_permissions_assigned_self_read on private.role_permissions;
create policy role_permissions_assigned_self_read
on private.role_permissions
for select
to authenticated
using (
  exists (
    select 1
    from private.user_roles ur
    where ur.role_id = role_permissions.role_id
      and ur.user_id = (select auth.uid())
  )
);

-- Only permission definitions reachable from the current user's assigned roles.
drop policy if exists permissions_assigned_self_read on private.permissions;
create policy permissions_assigned_self_read
on private.permissions
for select
to authenticated
using (
  exists (
    select 1
    from private.role_permissions rp
    join private.user_roles ur on ur.role_id = rp.role_id
    where rp.permission_id = permissions.id
      and ur.user_id = (select auth.uid())
  )
);

create or replace function public.get_my_admin_context()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'user_id', (select auth.uid()),
    'is_active', coalesce((
      select ua.is_active
      from private.user_access ua
      where ua.user_id = (select auth.uid())
    ), false),
    'has_admin_access', coalesce((
      select ua.is_active
      from private.user_access ua
      where ua.user_id = (select auth.uid())
    ), false) and exists (
      select 1
      from private.user_roles ur
      where ur.user_id = (select auth.uid())
    ),
    'roles', coalesce((
      select jsonb_agg(r.key order by r.key)
      from private.user_roles ur
      join private.roles r on r.id = ur.role_id
      where ur.user_id = (select auth.uid())
    ), '[]'::jsonb),
    'permissions', coalesce((
      select jsonb_agg(x.key order by x.key)
      from (
        select distinct p.key
        from private.user_roles ur
        join private.role_permissions rp on rp.role_id = ur.role_id
        join private.permissions p on p.id = rp.permission_id
        where ur.user_id = (select auth.uid())
      ) x
    ), '[]'::jsonb),
    'is_superadministrator', exists (
      select 1
      from private.user_roles ur
      join private.roles r on r.id = ur.role_id
      where ur.user_id = (select auth.uid())
        and r.key = 'superadministrator'
    ),
    'aal', coalesce((select auth.jwt()->>'aal'), 'aal1'),
    'mfa_required', exists (
      select 1
      from private.user_roles ur
      join private.role_permissions rp on rp.role_id = ur.role_id
      join private.permissions p on p.id = rp.permission_id
      where ur.user_id = (select auth.uid())
        and p.key in ('system.superadmin', 'settings.critical_edit', 'roles.manage')
    ),
    'mfa_satisfied', (select private.mfa_satisfied())
  );
$$;

revoke all on function public.get_my_admin_context() from public, anon, authenticated, service_role;
grant execute on function public.get_my_admin_context() to authenticated;
