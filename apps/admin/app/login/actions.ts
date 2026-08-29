'use server'

import { redirect } from 'next/navigation'
import { z } from 'zod'
import { parseAdminContext } from '@/lib/admin-context-schema'
import { createClient } from '@/lib/supabase/server'

const loginSchema = z.object({
  email: z.string().email().max(254),
  password: z.string().min(1).max(256),
})

export async function login(formData: FormData) {
  const parsed = loginSchema.safeParse({
    email: formData.get('email'),
    password: formData.get('password'),
  })

  if (!parsed.success) redirect('/login?error=invalid')

  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword(parsed.data)
  if (error) redirect('/login?error=credentials')

  const { data: userData, error: userError } = await supabase.auth.getUser()
  if (userError || !userData.user) {
    await supabase.auth.signOut()
    redirect('/access-denied')
  }

  const { data, error: contextError } = await supabase.rpc('get_my_admin_context')
  if (contextError) {
    await supabase.auth.signOut()
    redirect('/access-denied')
  }

  let context
  try {
    context = parseAdminContext(data, userData.user.id)
  } catch {
    await supabase.auth.signOut()
    redirect('/access-denied')
  }

  if (!context.has_admin_access || !context.is_active) {
    await supabase.auth.signOut()
    redirect('/access-denied')
  }

  if (context.mfa_required && !context.mfa_satisfied) redirect('/security')
  redirect('/dashboard')
}
