import { parseAdminContext, type AdminContext } from '@/lib/admin-context-schema'
import { createClient } from '@/lib/supabase/server'

export type { AdminContext } from '@/lib/admin-context-schema'

export async function getAdminContext(): Promise<AdminContext | null> {
  const supabase = await createClient()
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims()

  const userId = claimsData?.claims?.sub
  if (claimsError || typeof userId !== 'string' || userId.length === 0) return null

  const { data, error } = await supabase.rpc('get_my_admin_context')
  if (error) throw new Error('Unable to resolve administrative authorization context')

  return parseAdminContext(data, userId)
}
