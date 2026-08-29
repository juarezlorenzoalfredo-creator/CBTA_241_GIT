-- CBTA 241 Portal Institucional
-- Migration 013: preserve identity for audited tables whose primary identifier is not id/key.

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
  row_json jsonb;
begin
  begin
    headers := coalesce(nullif(current_setting('request.headers', true), '')::jsonb, '{}'::jsonb);
  exception when others then
    headers := '{}'::jsonb;
  end;
  rid := headers->>'x-request-id';

  row_json := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  entity := coalesce(
    row_json->>'id', row_json->>'key', row_json->>'content_id',
    row_json->>'source_content_id', row_json->>'user_id'
  );

  if tg_op = 'DELETE' then
    insert into private.audit_events(actor_id,action,entity_schema,entity_table,entity_id,old_data,result,request_id)
    values ((select auth.uid()),'DELETE',tg_table_schema,tg_table_name,entity,to_jsonb(old),'success',rid);
    return old;
  elsif tg_op = 'INSERT' then
    insert into private.audit_events(actor_id,action,entity_schema,entity_table,entity_id,new_data,result,request_id)
    values ((select auth.uid()),'INSERT',tg_table_schema,tg_table_name,entity,to_jsonb(new),'success',rid);
    return new;
  else
    insert into private.audit_events(actor_id,action,entity_schema,entity_table,entity_id,old_data,new_data,result,request_id)
    values ((select auth.uid()),'UPDATE',tg_table_schema,tg_table_name,entity,to_jsonb(old),to_jsonb(new),'success',rid);
    return new;
  end if;
end;
$$;

revoke execute on function private.audit_row_change() from public,anon,authenticated,service_role;
