import { ActivateForm } from './activate-form'

export default async function ActivatePage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>
}) {
  const params = await searchParams
  const status = params.status === 'sent' || params.status === 'unavailable' ? params.status : undefined

  return (
    <main className="activation-shell">
      <div className="coordinate dark">CBTA / SECURITY — BOOTSTRAP</div>
      <section className="activation-copy">
        <span className="eyebrow">Activación inicial protegida</span>
        <h1>Demostrar identidad antes de crear credenciales.</h1>
        <p>
          La primera cuenta administrativa se invita únicamente al correo previamente autorizado. El enlace del buzón confirma la identidad antes de permitir definir contraseña y enrolar MFA.
        </p>
        <div className="security-sequence" aria-label="Secuencia de activación">
          <span>01 Invitación</span><i />
          <span>02 Correo</span><i />
          <span>03 Credenciales</span><i />
          <span>04 MFA</span>
        </div>
      </section>
      <ActivateForm status={status} />
    </main>
  )
}
