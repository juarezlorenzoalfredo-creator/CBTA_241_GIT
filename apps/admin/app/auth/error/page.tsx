import Link from 'next/link'

export default function AuthErrorPage() {
  return (
    <main className="center-message">
      <div className="coordinate dark">CBTA / SECURITY — LINK</div>
      <h1>No fue posible validar este enlace.</h1>
      <p>
        La invitación puede haber expirado, haber sido utilizada o no corresponder al flujo administrativo autorizado.
      </p>
      <p className="muted">
        Por seguridad no mostramos el estado interno de la cuenta. Vuelve al inicio de activación para solicitar el flujo permitido.
      </p>
      <Link className="primary-action link-button" href="/activate">Volver a activación</Link>
    </main>
  )
}
