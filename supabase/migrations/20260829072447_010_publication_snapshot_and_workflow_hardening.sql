-- CBTA 241 Portal Institucional
-- Migration 010: decouple working editorial state from the public snapshot.

create table public.content_publications (
  content_id uuid primary key references public.contents(id) on delete cascade,
  revision bigint not null check (revision > 0),
  content_type text not null check (content_type ~ '^[a-z][a-z0-9_]{1,49}$'),
  title text not null check (char_length(title) between 1 and 220),
  slug text not null check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and char_length(slug) <= 180),
  summary text,
  body jsonb not null default '{}'::jsonb,
  seo jsonb not null default '{}'::jsonb,
  priority text not null default 'normal' check (priority in ('normal','featured','priority','critical')),
  publish_at timestamptz,
  expires_at timestamptz,
  published_at timestamptz not null,
  archived_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at is null or publish_at is null or expires_at > publish_at)
);

create unique index content_publications_type_slug_active_uidx on public.content_publications(content_type, lower(slug)) where archived_at is null;
create index content_publications_feed_idx on public.content_publications(content_type, published_at desc) where archived_at is null;
create index content_publications_expires_idx on public.content_publications(expires_at) where archived_at is null and expires_at is not null;
create index content_publications_published_by_idx on public.content_publications(published_by) where published_by is not null;

alter table public.content_publications enable row level security;
revoke all on table public.content_publications from anon, authenticated, service_role;
grant select on table public.content_publications to anon, authenticated, service_role;
grant insert, update on table public.content_publications to authenticated, service_role;
grant delete on table public.content_publications to service_role;

create policy content_publications_public_read on public.content_publications for select to anon, authenticated using (
  archived_at is null and published_at <= now() and (publish_at is null or publish_at <= now()) and (expires_at is null or expires_at > now())
);
create policy content_publications_workflow_insert on public.content_publications for insert to authenticated with check (
  current_setting('cbta.workflow_rpc', true) = 'on' and (select private.has_permission('content.publish'))
);
create policy content_publications_workflow_update on public.content_publications for update to authenticated
using (current_setting('cbta.workflow_rpc', true) = 'on' and ((select private.has_permission('content.publish')) or (select private.has_permission('content.archive')) or (select private.has_permission('content.restore'))))
with check (current_setting('cbta.workflow_rpc', true) = 'on' and ((select private.has_permission('content.publish')) or (select private.has_permission('content.archive')) or (select private.has_permission('content.restore'))));

drop policy if exists contents_public_read_anon on public.contents;
drop policy if exists contents_read_authenticated on public.contents;
create policy contents_admin_read on public.contents for select to authenticated using ((select private.has_permission('content.read_all')) or created_by = (select auth.uid()));
revoke select on table public.contents from anon;
revoke update on table public.contents from authenticated;
grant update (title, slug, summary, body, seo, priority, owner_area, expires_at, publish_at, status) on table public.contents to authenticated;

create or replace function private.enforce_content_workflow()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  old_status text;
  new_status text;
  via_workflow_rpc boolean := coalesce(current_setting('cbta.workflow_rpc', true), '') = 'on';
  editorial_changed boolean;
begin
  if tg_op = 'INSERT' then
    if (select auth.uid()) is not null then
      new.created_by := coalesce(new.created_by, (select auth.uid()));
      new.updated_by := (select auth.uid());
      if new.status <> 'draft' then raise exception 'new content must start as draft'; end if;
    end if;
    new.revision := 1; new.created_at := coalesce(new.created_at, now()); new.updated_at := now(); return new;
  end if;

  old_status := old.status; new_status := new.status;
  editorial_changed := new.content_type is distinct from old.content_type or new.title is distinct from old.title or new.slug is distinct from old.slug or new.summary is distinct from old.summary or new.body is distinct from old.body or new.seo is distinct from old.seo or new.priority is distinct from old.priority or new.owner_area is distinct from old.owner_area or new.expires_at is distinct from old.expires_at;

  if (select auth.uid()) is not null then
    if new.created_by is distinct from old.created_by then raise exception 'created_by is immutable'; end if;
    new.updated_by := (select auth.uid());
    if new_status is distinct from old_status and not via_workflow_rpc then raise exception 'editorial status transitions must use transition_content'; end if;
    if new.publish_at is distinct from old.publish_at and not via_workflow_rpc then raise exception 'publish_at can only change through transition_content'; end if;
    if new_status = old_status and old_status in ('approved','scheduled','published','archived') and editorial_changed then raise exception 'content is frozen in status %; begin a controlled revision first', old_status; end if;

    if new_status is distinct from old_status then
      if old_status = 'draft' and new_status = 'in_review' then
        if not private.has_permission('content.submit') then raise exception 'permission denied: content.submit required'; end if;
      elsif old_status = 'in_review' and new_status = 'draft' then null;
      elsif old_status = 'in_review' and new_status = 'approved' then
        if not private.has_permission('content.approve') then raise exception 'permission denied: content.approve required'; end if;
      elsif old_status = 'approved' and new_status = 'draft' then
        if not (private.has_permission('content.edit_any') or (private.has_permission('content.edit_own') and old.created_by = (select auth.uid()))) then raise exception 'permission denied: edit permission required'; end if;
      elsif old_status = 'approved' and new_status = 'scheduled' then
        if not private.has_permission('content.schedule') then raise exception 'permission denied: content.schedule required'; end if;
        if new.publish_at is null or new.publish_at <= now() then raise exception 'publish_at must be in the future for scheduled content'; end if;
      elsif old_status = 'scheduled' and new_status = 'approved' then
        if not private.has_permission('content.schedule') then raise exception 'permission denied: content.schedule required'; end if;
      elsif old_status in ('approved','scheduled') and new_status = 'published' then
        if not private.has_permission('content.publish') then raise exception 'permission denied: content.publish required'; end if;
        if old_status = 'scheduled' and (old.publish_at is null or old.publish_at > now()) then raise exception 'scheduled content is not due yet'; end if;
        new.published_at := now(); new.archived_at := null;
      elsif old_status = 'published' and new_status = 'draft' then
        if not (private.has_permission('content.edit_any') or (private.has_permission('content.edit_own') and old.created_by = (select auth.uid()))) then raise exception 'permission denied: edit permission required'; end if;
      elsif old_status = 'published' and new_status = 'archived' then
        if not private.has_permission('content.archive') then raise exception 'permission denied: content.archive required'; end if;
        new.archived_at := now();
      elsif old_status = 'archived' and new_status = 'approved' then
        if not private.has_permission('content.restore') then raise exception 'permission denied: content.restore required'; end if;
        new.archived_at := null;
      else raise exception 'invalid editorial status transition: % -> %', old_status, new_status;
      end if;
    end if;
  end if;
  new.revision := old.revision + 1; new.updated_at := now(); return new;
end;
$$;
revoke execute on function private.enforce_content_workflow() from public, anon, authenticated, service_role;

create or replace function public.transition_content(p_content_id uuid, p_expected_revision bigint, p_target_status text, p_publish_at timestamptz default null)
returns public.contents language plpgsql security invoker set search_path = '' as $$
declare v_current public.contents%rowtype; v_updated public.contents%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  if p_target_status not in ('draft','in_review','approved','scheduled','published','archived') then raise exception 'invalid target status'; end if;
  select * into v_current from public.contents where id = p_content_id for update;
  if not found then raise exception 'content not found or not accessible'; end if;
  if v_current.revision <> p_expected_revision then raise exception 'revision conflict: expected %, current %', p_expected_revision, v_current.revision; end if;
  perform set_config('cbta.workflow_rpc', 'on', true);
  update public.contents set status=p_target_status, publish_at=case when p_target_status='scheduled' then p_publish_at when p_target_status in ('draft','approved') then null else publish_at end where id=p_content_id returning * into v_updated;
  if p_target_status='published' then
    insert into public.content_publications(content_id,revision,content_type,title,slug,summary,body,seo,priority,publish_at,expires_at,published_at,archived_at,published_by,created_at,updated_at)
    values(v_updated.id,v_updated.revision,v_updated.content_type,v_updated.title,v_updated.slug,v_updated.summary,v_updated.body,v_updated.seo,v_updated.priority,v_updated.publish_at,v_updated.expires_at,v_updated.published_at,null,(select auth.uid()),now(),now())
    on conflict(content_id) do update set revision=excluded.revision,content_type=excluded.content_type,title=excluded.title,slug=excluded.slug,summary=excluded.summary,body=excluded.body,seo=excluded.seo,priority=excluded.priority,publish_at=excluded.publish_at,expires_at=excluded.expires_at,published_at=excluded.published_at,archived_at=null,published_by=excluded.published_by,updated_at=now();
  elsif p_target_status='archived' then
    update public.content_publications set archived_at=now(),updated_at=now() where content_id=p_content_id;
  end if;
  return v_updated;
end;
$$;
revoke execute on function public.transition_content(uuid,bigint,text,timestamptz) from public,anon,service_role;
grant execute on function public.transition_content(uuid,bigint,text,timestamptz) to authenticated;

create trigger content_publications_audit after insert or update or delete on public.content_publications for each row execute function private.audit_row_change();

insert into public.content_publications(content_id,revision,content_type,title,slug,summary,body,seo,priority,publish_at,expires_at,published_at,archived_at,published_by,created_at,updated_at)
select c.id,c.revision,c.content_type,c.title,c.slug,c.summary,c.body,c.seo,c.priority,c.publish_at,c.expires_at,c.published_at,null,c.updated_by,now(),now()
from public.contents c where c.deleted_at is null and c.status='published' and c.published_at is not null and not exists(select 1 from public.content_publications p where p.content_id=c.id);
