-- CBTA 241 Portal Institucional
-- Migration 011: explicitly close the workflow capability marker before RPC return.

create or replace function public.transition_content(
  p_content_id uuid,
  p_expected_revision bigint,
  p_target_status text,
  p_publish_at timestamptz default null
)
returns public.contents
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_current public.contents%rowtype;
  v_updated public.contents%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'authentication required'; end if;
  if p_target_status not in ('draft','in_review','approved','scheduled','published','archived') then raise exception 'invalid target status'; end if;

  select * into v_current from public.contents where id = p_content_id for update;
  if not found then raise exception 'content not found or not accessible'; end if;
  if v_current.revision <> p_expected_revision then raise exception 'revision conflict: expected %, current %', p_expected_revision, v_current.revision; end if;

  perform set_config('cbta.workflow_rpc', 'on', true);

  update public.contents
  set status = p_target_status,
      publish_at = case
        when p_target_status = 'scheduled' then p_publish_at
        when p_target_status in ('draft','approved') then null
        else publish_at
      end
  where id = p_content_id
  returning * into v_updated;

  if p_target_status = 'published' then
    insert into public.content_publications(
      content_id, revision, content_type, title, slug, summary, body, seo, priority,
      publish_at, expires_at, published_at, archived_at, published_by, created_at, updated_at
    ) values (
      v_updated.id, v_updated.revision, v_updated.content_type, v_updated.title,
      v_updated.slug, v_updated.summary, v_updated.body, v_updated.seo, v_updated.priority,
      v_updated.publish_at, v_updated.expires_at, v_updated.published_at, null,
      (select auth.uid()), now(), now()
    )
    on conflict (content_id) do update set
      revision=excluded.revision, content_type=excluded.content_type, title=excluded.title,
      slug=excluded.slug, summary=excluded.summary, body=excluded.body, seo=excluded.seo,
      priority=excluded.priority, publish_at=excluded.publish_at, expires_at=excluded.expires_at,
      published_at=excluded.published_at, archived_at=null, published_by=excluded.published_by,
      updated_at=now();
  elsif p_target_status = 'archived' then
    update public.content_publications set archived_at=now(), updated_at=now() where content_id=p_content_id;
  end if;

  perform set_config('cbta.workflow_rpc', 'off', true);
  return v_updated;
end;
$$;

revoke execute on function public.transition_content(uuid,bigint,text,timestamptz) from public,anon,service_role;
grant execute on function public.transition_content(uuid,bigint,text,timestamptz) to authenticated;
