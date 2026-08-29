'use server'

import { redirect } from 'next/navigation'
import { z } from 'zod'
import { getInitialActivationContext } from '@/lib/initial-activation'
import { createClient } from '@/lib/supabase/server'

const passwordSchema = z.object({
  password: z.string()
    .min(14)
    .max(256)
    .regex(/[a-z]/)
    .regex(/[A-Z]/)
    .regex(/\d/)
    .regex(/[^A-Za-z0-9]/),
  confirm: z.string().min(1).max(256),
}).refine((value) => value.password === value.confirm, {
  path: ['confirm'],
  message: 'passwords_do_not_match',
})

export async function completeInitialActivation(formData: FormData) {
  const parsed = passwordSchema.safeParse({
    password: formData.get('password'),
    confirm: formData.get('confirm'),
  })

  if (!parsed.success) {
    redirect('/activate/complete?error=password')
  }

  const context = await getInitialActivationContext()
  if (!context) {
    redirect('/auth/error')
  }

  const supabase = await createClient()
  const { data: userData, error: userError } = await supabase.auth.getUser()
  if (userError || !userData.user || userData.user.id !== context.user_id) {
    await supabase.auth.signOut({ scope: 'local' })
    redirect('/auth/error')
  }

  const { error: updateError } = await supabase.auth.updateUser({
    password: parsed.data.password,
  })

  if (updateError) {
    redirect('/activate/complete?error=update')
  }

  // The invitation session is for credential bootstrap only. End it after the
  // password is established so /activate/complete cannot become a future password
  // management surface. The next login uses the new password and is routed to MFA.
  const { error: signOutError } = await supabase.auth.signOut({ scope: 'global' })
  if (signOutError) {
    await supabase.auth.signOut({ scope: 'local' })
  }

  redirect('/login?status=activated')
}
