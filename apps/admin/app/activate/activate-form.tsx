import Link from 'next/link'
import { requestInitialActivation } from './actions'

type Props = {
  status: 'sent' | 'unavailable' | undefined
}

export function ActivateForm({ status }: Props) {
  if (status === 'sent') {
    return (
      <section className="activation-card" aria-live="polite">
        <div className="status-mark">02</div>
        <h2>Revisa el correo administrativo autorizado</h2>
        <p>
          Se procesó la solicitud de activación. Si la identidad inicial aún no existía, Supabase Auth enviará una invitación únicamente al buzón previamente aprobado.
        </p>
        <p className="muted">
          La dirección privilegiada no se publica en esta interfaz ni en el código del portal. El enlace del correo debe validar la identidad antes de crear credenciales.
        </p>
        <Link className="primary-action link-button" href="/login">Ir al acceso</Link>
      </section>
    )
  }

  return (
    <section className="activation-card">
      <div className="status-mark">01</div>
      <h2>Solicitar invitación protegida</h2>
      <p className="account-lock">Identidad administrativa inicial protegida</p>
      {status === 'unavailable' ? (
        <div className="notice danger" role="alert">
          La activación todavía no está habilitada para este entorno. El sistema permanece cerrado hasta contar con una URL HTTPS de administración y la identidad de bootstrap configuradas como secretos del entorno.
        </div>
      ) : null}
      <p className="muted">
        El destinatario no puede ser elegido por el visitante. La función de bootstrap acepta únicamente la identidad cuya huella fue autorizada previamente y no crea contraseñas antes de comprobar el buzón.
      </p>
      <form action={requestInitialActivation} className="form-stack">
        <button className="primary-action" type="submit">Enviar invitación de activación</button>
      </form>
    </section>
  )
}
