import Link from 'next/link'

export default function AccessDeniedPage() {
  return (
    <main className="center-message">
      <div className="coordinate dark">CBTA / SECURITY — 403</div>
      <h1>Cuenta sin autorización administrativa.</h1>
      <p>La identidad pudo autenticarse, pero no tiene un rol operativo activo en el Portal Institucional.</p>
      <Link className="primary-action link-button" href="/login">Volver al acceso</Link>
    </main>
  )
}
