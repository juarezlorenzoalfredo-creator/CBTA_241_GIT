-- CBTA 241 Portal Institucional
-- Migration 009: restore compatibility with Supabase Auth invitation internals.
-- Supabase creates the auth.users row before it stamps invited_at, so a BEFORE
-- INSERT guard on invited_at would incorrectly reject legitimate admin invitations.
-- Keep the bootstrap assignment itself invitation-bound (migration 008), while
-- the Edge Function safely re-invites an existing unconfirmed identity.

drop trigger if exists cbta241_require_invited_auth_user on auth.users;
drop function if exists private.enforce_invitation_only_auth_user_creation();
