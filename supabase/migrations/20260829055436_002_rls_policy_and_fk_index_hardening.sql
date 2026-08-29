-- CBTA 241 Portal Institucional
-- Migration 002: RLS policy consolidation + foreign-key index hardening

-- Cover foreign keys used for deletes, joins and audit lookups.
create index if not exists user_access_disabled_by_idx
  on private.user_access(disabled_by)
  where disabled_by is not null;

create index if not exists user_roles_assigned_by_idx
  on private.user_roles(assigned_by)
  where assigned_by is not null;

create index if not exists user_roles_role_id_idx
  on private.user_roles(role_id);

create index if not exists content_relations_created_by_idx
  on public.content_relations(created_by)
  where created_by is not null;

create index if not exists content_versions_changed_by_idx
  on public.content_versions(changed_by)
  where changed_by is not null;

create index if not exists contents_updated_by_idx
  on public.contents(updated_by)
  where updated_by is not null;

create index if not exists institutional_data_created_by_idx
  on public.institutional_data(created_by)
  where created_by is not null;

create index if not exists institutional_data_updated_by_idx
  on public.institutional_data(updated_by)
  where updated_by is not null;

create index if not exists institutional_data_verified_by_idx
  on public.institutional_data(verified_by)
  where verified_by is not null;

-- Avoid multiple permissive SELECT policies for authenticated role.
drop policy if exists contents_public_read on public.contents;
drop policy if exists contents_admin_read on public.contents;

drop policy if exists contents_public_read_anon on public.contents;
create policy contents_public_read_anon
on public.contents for select
to anon
using (
  deleted_at is null
  and status = 'published'
  and published_at <= now()
  and (expires_at is null or expires_at > now())
);

drop policy if exists contents_read_authenticated on public.contents;
create policy contents_read_authenticated
on public.contents for select
to authenticated
using (
  (
    deleted_at is null
    and status = 'published'
    and published_at <= now()
    and (expires_at is null or expires_at > now())
  )
  or (select private.has_permission('content.read_all'))
  or created_by = (select auth.uid())
);

-- Same consolidation for Institutional Source of Truth.
drop policy if exists institutional_public_read on public.institutional_data;
drop policy if exists institutional_admin_read on public.institutional_data;

drop policy if exists institutional_public_read_anon on public.institutional_data;
create policy institutional_public_read_anon
on public.institutional_data for select
to anon
using (
  is_public
  and is_active
  and deleted_at is null
  and verification_status = 'verified'
);

drop policy if exists institutional_read_authenticated on public.institutional_data;
create policy institutional_read_authenticated
on public.institutional_data for select
to authenticated
using (
  (
    is_public
    and is_active
    and deleted_at is null
    and verification_status = 'verified'
  )
  or (select private.has_permission('institution.read_private'))
);
