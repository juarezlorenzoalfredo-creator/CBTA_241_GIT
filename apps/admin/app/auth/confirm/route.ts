import { type EmailOtpType } from '@supabase/supabase-js'
import { type NextRequest, NextResponse } from 'next/server'
import { parseAdminContext } from '@/lib/admin-context-schema'
import { createClient } from '@/lib/supabase/server'

const COMPLETE_ACTIVATION_PATH = '/activate/complete'
const AUTH_ERROR_PATH = '/auth/error'

function redirectWithoutAuthParams(request: NextRequest, pathname: string) {
  const target = request.nextUrl.clone()
  target.pathname = pathname
  target.search = ''
  target.hash = ''
  return NextResponse.redirect(target, { status: 303 })
}

export async function GET(request: NextRequest) {
  const tokenHash = request.nextUrl.searchParams.get('token_hash')
  const rawType = request.nextUrl.searchParams.get('type')

  // This endpoint exists only for the initial administrative invitation.
  // Reject every other email flow instead of turning it into a generic redirector.
  if (!tokenHash || tokenHash.length > 2048 || rawType !== 'invite') {
    return redirectWithoutAuthParams(request, AUTH_ERROR_PATH)
  }

  const supabase = await createClient()
  const type: EmailOtpType = 'invite'
  const { error: verifyError } = await supabase.auth.verifyOtp({
    token_hash: tokenHash,
    type,
  })

  if (verifyError) {
    return redirectWithoutAuthParams(request, AUTH_ERROR_PATH)
  }

  const { data: userData, error: userError } = await supabase.auth.getUser()
  if (userError || !userData.user) {
    await supabase.auth.signOut()
    return redirectWithoutAuthParams(request, AUTH_ERROR_PATH)
  }

  const { data, error: contextError } = await supabase.rpc('get_my_admin_context')

  try {
    if (contextError) throw new Error('admin_context_unavailable')
    const context = parseAdminContext(data, userData.user.id)
    if (!context.is_active || !context.has_admin_access || !context.is_superadministrator) {
      throw new Error('admin_context_denied')
    }
  } catch {
    await supabase.auth.signOut()
    return redirectWithoutAuthParams(request, AUTH_ERROR_PATH)
  }

  return redirectWithoutAuthParams(request, COMPLETE_ACTIVATION_PATH)
}
