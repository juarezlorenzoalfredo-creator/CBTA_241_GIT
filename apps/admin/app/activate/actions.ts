'use server'

import { redirect } from 'next/navigation'

export async function requestInitialActivation() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!supabaseUrl) redirect('/activate?status=unavailable')

  let response: Response
  try {
    response = await fetch(`${supabaseUrl}/functions/v1/bootstrap-superadmin-invite`, {
      method: 'POST',
      cache: 'no-store',
      headers: {
        'Content-Type': 'application/json',
      },
      body: '{}',
    })
  } catch {
    redirect('/activate?status=unavailable')
  }

  if (!response.ok) redirect('/activate?status=unavailable')
  redirect('/activate?status=sent')
}
