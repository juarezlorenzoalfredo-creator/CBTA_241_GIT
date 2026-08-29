-- CBTA 241 Portal Institucional
-- Migration 015: database-backed editorial preflight.

create or replace function private.content_preflight_errors(p_content public.contents)
returns text[]
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  errors text[] := array[]::text[];
  has_meaningful_paragraph boolean := false;
  searchable_text text;
begin
  if p_content.expires_at is not null and p_content.expires_at <= now() then
    errors := array_append(errors, 'expiration_in_past');
  end if;

  if p_content.content_type = 'news' then
    if p_content.summary is null or char_length(btrim(p_content.summary)) < 20 then
      errors := array_append(errors, 'news_summary_required');
    end if;

    if coalesce((p_content.body->>'schema_version')::int, 0) <> 1 then
      errors := array_append(errors, 'body_schema_invalid');
    end if;

    if jsonb_typeof(p_content.body->'blocks') <> 'array' then
      errors := array_append(errors, 'body_blocks_required');
    else
      select exists (
        select 1 from jsonb_array_elements(p_content.body->'blocks') block
        where block->>'type' = 'paragraph'
          and char_length(btrim(coalesce(block->>'text', ''))) >= 40
      ) into has_meaningful_paragraph;
      if not has_meaningful_paragraph then errors := array_append(errors, 'news_body_required'); end if;
    end if;

    searchable_text := lower(coalesce(p_content.title,'') || ' ' || coalesce(p_content.summary,'') || ' ' || coalesce(p_content.body::text,''));
    if searchable_text like '%dato institucional pendiente de validación%'
       or searchable_text like '%dato institucional pendiente de validacion%' then
      errors := array_append(errors, 'institutional_placeholder_detected');
    end if;
  end if;

  return errors;
exception when invalid_text_representation then
  return array_append(errors, 'body_schema_invalid');
end;
$$;
revoke execute on function private.content_preflight_errors(public.contents) from public,anon,service_role;
grant execute on function private.content_preflight_errors(public.contents) to authenticated;

create or replace function private.enforce_content_preflight()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare errors text[];
begin
  if new.status in ('in_review','approved','scheduled','published') then
    errors := private.content_preflight_errors(new);
    if cardinality(errors) > 0 then raise exception 'content preflight failed: %', array_to_string(errors, ','); end if;
  end if;
  return new;
end;
$$;
revoke execute on function private.enforce_content_preflight() from public,anon,authenticated,service_role;

drop trigger if exists contents_preflight_guard on public.contents;
create trigger contents_preflight_guard before insert or update on public.contents for each row execute function private.enforce_content_preflight();

create or replace function public.get_content_preflight(p_content_id uuid)
returns text[]
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare content_row public.contents%rowtype;
begin
  select * into content_row from public.contents where id=p_content_id;
  if not found then raise exception 'content not found or not accessible'; end if;
  return private.content_preflight_errors(content_row);
end;
$$;
revoke execute on function public.get_content_preflight(uuid) from public,anon,service_role;
grant execute on function public.get_content_preflight(uuid) to authenticated;
