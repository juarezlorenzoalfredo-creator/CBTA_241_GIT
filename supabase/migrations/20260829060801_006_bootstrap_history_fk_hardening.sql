-- Preserve the immutable bootstrap UUID as historical evidence even if the Auth user
-- is later removed through a controlled offboarding process. A FK with ON DELETE SET NULL
-- conflicted with the invariant that a consumed bootstrap must retain its actor identifier.

alter table private.superadmin_bootstrap_identity
  drop constraint if exists superadmin_bootstrap_identity_consumed_by_fkey;

comment on column private.superadmin_bootstrap_identity.consumed_by is
  'Historical UUID of the Auth user that consumed the one-time SUPERADMIN bootstrap. Intentionally not a foreign key so audit evidence survives controlled account deletion.';
