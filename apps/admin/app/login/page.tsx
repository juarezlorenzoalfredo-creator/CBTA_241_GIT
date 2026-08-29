import Link from 'next/link'
import { login } from './actions'

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string; status?: string }>
}) {
  const params = await searchParams
  const hasError = Boolean(params.error)
  const activated = params.status === 'activated'

  return (
    <main className="auth-shell">
      <section className="auth-territory" aria-label="Identidad institucional">
        <div className="coordinate">CBTA / OPS — 01</div>
        <div className="auth-brand">
          <span className="eyebrow">Centro de Operaciones</span>
          <h1>Administración institucional, sin ruido.</h1>
          <p>Contenido, publicación y calidad digital bajo permisos, trazabilidad y MFA.</p>
        </div>
        <div className="terrain-lines" aria-hidden="true" />
      </section>

      <section className="auth-panel">
        <div className="panel-kicker">ACCESO CONTROLADO</div>
        <h2>Ingresar</h2>
        <p className="muted">Usa únicamente una cuenta administrativa autorizada.</p>

        {activated ? (
          <div className="notice" role="status">
            La contraseña quedó establecida. Inicia sesión con ella para completar la configuración obligatoria de MFA.
          </div>
        ) : null}

        {hasError ? (
          <div className="notice danger" role="alert">
            No fue posible iniciar sesión. Verifica tus credenciales e inténtalo nuevamente.
          </div>
        ) : null}

        <form action={login} className="form-stack">
          <label>
            <span>Correo institucional</span>
            <input name="email" type="email" autoComplete="username" required />
          </label>
          <label>
            <span>Contraseña</span>
            <input name="password" type="password" autoComplete="current-password" required />
          </label>
          <button className="primary-action" type="submit">Continuar</button>
        </form>

        <div className="auth-footer">
          <span>Primera configuración:</span>
          <Link href="/activate">activar cuenta SUPERADMIN</Link>
        </div>
      </section>
    </main>
  )
}
