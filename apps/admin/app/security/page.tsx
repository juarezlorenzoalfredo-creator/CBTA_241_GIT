import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin-context'
import { MfaClient } from './mfa-client'

export default async function SecurityPage() {
  const context = await getAdminContext()
  if (!context) redirect('/login')
  if (!context.has_admin_access) redirect('/access-denied')
  if (!context.mfa_required || context.mfa_satisfied) redirect('/dashboard')

  return (
    <main className="security-shell">
      <section className="security-intro">
        <div className="coordinate">CBTA / SECURITY — AAL2</div>
        <span className="eyebrow">Segundo factor obligatorio</span>
        <h1>La contraseña abre la puerta. MFA autoriza la operación.</h1>
        <p>Configura o verifica un autenticador TOTP. Las operaciones privilegiadas permanecen bloqueadas en Postgres hasta que la sesión alcance AAL2.</p>
      </section>
      <MfaClient />
    </main>
  )
}
