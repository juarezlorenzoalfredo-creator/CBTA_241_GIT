-- CBTA 241 Portal Institucional
-- Migration 014: cache transaction-local workflow marker once per statement in RLS.

drop policy if exists content_publications_workflow_insert on public.content_publications;
create policy content_publications_workflow_insert
on public.content_publications for insert
to authenticated
with check (
  (select current_setting('cbta.workflow_rpc', true)) = 'on'
  and (select private.has_permission('content.publish'))
);

drop policy if exists content_publications_workflow_update on public.content_publications;
create policy content_publications_workflow_update
on public.content_publications for update
to authenticated
using (
  (select current_setting('cbta.workflow_rpc', true)) = 'on'
  and (
    (select private.has_permission('content.publish'))
    or (select private.has_permission('content.archive'))
    or (select private.has_permission('content.restore'))
  )
)
with check (
  (select current_setting('cbta.workflow_rpc', true)) = 'on'
  and (
    (select private.has_permission('content.publish'))
    or (select private.has_permission('content.archive'))
    or (select private.has_permission('content.restore'))
  )
);
