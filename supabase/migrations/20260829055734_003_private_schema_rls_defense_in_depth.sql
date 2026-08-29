-- CBTA 241 Portal Institucional
-- Migration 003: defense-in-depth RLS for private security and audit tables

alter table private.roles enable row level security;
alter table private.permissions enable row level security;
alter table private.role_permissions enable row level security;
alter table private.user_roles enable row level security;
alter table private.user_access enable row level security;
alter table private.audit_events enable row level security;
