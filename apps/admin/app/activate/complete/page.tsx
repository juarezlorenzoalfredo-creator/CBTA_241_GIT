import { redirect } from 'next/navigation'
import { getInitialActivationContext } from '@/lib/initial-activation'
import { completeInitialActivation } from './actions'

type Props = {
  searchParams: Promise<{ error?: string }>
}

export default async function CompleteActivationPage({ searchParams }: Props) {
  const context = await getInitialActivationContext()
  if (!context) redirect('/auth/error')

  const params = await searchParams
  const error = params.error === 'password' || params.error === 'update' ? params.error : undefined

  return (
    <main className="activation-shell">
      <div className="coordinate dark">CBTA / SECURITY — CREDENTIALS</div>
      <section className="activation-copy">
        <span className="eyebrow">Identidad de correo confirmada</span>
        <h1>Ahora sí: define las credenciales de operación.</h1>
        <p>
          Esta etapa solo está disponible para la sesión creada por la invitación administrativa confirmada. Después de establecer la contraseña, el Centro de Operaciones exigirá MFA/TOTP antes de habilitar acciones privilegiadas.
        </p>
      </section>

      <section className="activation-card">
        <div className="status-mark">03</div>
        <h2>Definir contraseña</h2>
        <p className="account-lock">Identidad SUPERADMIN verificada</p>

        {error === 'password' ? (
          <div className="notice danger" role="alert">
            La contraseña debe tener al menos 14 caracteres e incluir mayúscula, minúscula, número y símbolo. Ambos campos deben coincidir.
          </div>
        ) : null}

        {error === 'update' ? (
          <div className="notice danger" role="alert">
            No fue posible establecer las credenciales con esta sesión. Vuelve a intentarlo; si el enlace dejó de ser válido, inicia nuevamente la activación.
          </div>
        ) : null}

        <form className="form-stack" action={completeInitialActivation}>
          <label>
            <span>Nueva contraseña</span>
            <input
              name="password"
              type="password"
              autoComplete="new-password"
              minLength={14}
              maxLength={256}
              required
            />
          </label>

          <label>
            <span>Confirmar contraseña</span>
            <input
              name="confirm"
              type="password"
              autoComplete="new-password"
              minLength={14}
              maxLength={256}
              required
            />
          </label>

          <p className="field-help">14+ caracteres · mayúscula · minúscula · número · símbolo</p>
          <button className="primary-action" type="submit">Guardar contraseña y configurar MFA</button>
        </form>
      </section>
    </main>
  )
}
