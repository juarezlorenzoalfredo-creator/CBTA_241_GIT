import { z } from 'zod'
import { parseAdminContext, type AdminContext } from '@/lib/admin-context-schema'
import { createClient } from '@/lib/supabase/server'

const authClaimsSchema = z.object({
  sub: z.string().uuid(),
  amr: z.array(z.object({
    method: z.string().min(1).max(64),
    timestamp: z.number().int().nonnegative(),
  }).passthrough()).min(1),
}).passthrough()

export async function getInitialActivationContext(): Promise<AdminContext | null> {
  const supabase = await createClient()
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims()
  if (claimsError) return null

  const claims = authClaimsSchema.safeParse(claimsData?.claims)
  if (!claims.success) return null

  // Supabase orders AMR entries newest first. Only the session created from the
  // invitation may enter the one-time credential bootstrap flow.
  if (claims.data.amr[0]?.method !== 'invite') return null

  const { data, error } = await supabase.rpc('get_my_admin_context')
  if (error) return null

  try {
    const context = parseAdminContext(data, claims.data.sub)
    if (!context.is_active || !context.has_admin_access || !context.is_superadministrator) {
      return null
    }
    return context
  } catch {
    return null
  }
}
