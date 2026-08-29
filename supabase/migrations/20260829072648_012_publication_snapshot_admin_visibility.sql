-- CBTA 241 Portal Institucional
-- Migration 012: split public snapshot visibility from authorized administrative history visibility.

drop policy if exists content_publications_public_read on public.content_publications;

create policy content_publications_public_read_anon
on public.content_publications for select
to anon
using (
  archived_at is null
  and published_at <= now()
  and (publish_at is null or publish_at <= now())
  and (expires_at is null or expires_at > now())
);

create policy content_publications_read_authenticated
on public.content_publications for select
to authenticated
using (
  (
    archived_at is null
    and published_at <= now()
    and (publish_at is null or publish_at <= now())
    and (expires_at is null or expires_at > now())
  )
  or (select private.can_read_content(content_id))
);
