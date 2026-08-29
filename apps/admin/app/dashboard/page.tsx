import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin-context'
import styles from './dashboard.module.css'

const modules = [
  ['01', 'Contenido', 'Crear, revisar y versionar información institucional.', '/content', 'ACTIVO'],
  ['02', 'Publicaciones', 'Aprobaciones, programación y estado editorial.', null, 'SIGUIENTE FASE'],
  ['03', 'Convocatorias', 'Vigencias, prioridad y rutas para aspirantes.', null, 'SIGUIENTE FASE'],
  ['04', 'Documentos', 'Fuente oficial, versiones y caducidad.', null, 'SIGUIENTE FASE'],
  ['05', 'Calidad digital', 'Accesibilidad, enlaces y contenido desactualizado.', null, 'SIGUIENTE FASE'],
  ['06', 'Auditoría', 'Trazabilidad de cambios y operaciones sensibles.', null, 'SIGUIENTE FASE'],
] as const

export default async function DashboardPage() {
  const context = await getAdminContext()
  if (!context) redirect('/login')
  if (!context.has_admin_access) redirect('/access-denied')
  if (context.mfa_required && !context.mfa_satisfied) redirect('/security')

  return (
    <main className="ops-shell">
      <aside className="ops-rail"><div className="ops-monogram">241</div><div className="rail-word">OPERACIONES</div></aside>
      <section className="ops-main">
        <header className="ops-header">
          <div><div className="coordinate dark">CBTA / OPS — CONTROL</div><span className="eyebrow">Centro de Operaciones</span><h1>¿Qué necesita atención?</h1></div>
          <div className="session-state"><span className="status-dot" /><div><strong>Sesión protegida</strong><small>{context.aal.toUpperCase()} · {context.roles.join(' / ')}</small></div></div>
        </header>
        <section className="attention-strip"><span>VERTICAL SLICE 01</span><p>El módulo Contenido ya conecta borrador, revisión, aprobación y snapshot público de última versión válida. Los demás dominios se incorporarán por etapas auditadas.</p></section>
        <section className="module-list" aria-label="Módulos del Centro de Operaciones">
          {modules.map(([index, title, description, href, state]) => {
            const inner = <><span className="module-index">{index}</span><h2>{title}</h2><p>{description}</p><span className={`module-state ${state === 'ACTIVO' ? styles.active : ''}`}>{state}</span></>
            return href ? <Link className={`module-row ${styles.moduleLink}`} href={href} key={index}>{inner}</Link> : <article className="module-row" key={index}>{inner}</article>
          })}
        </section>
        <footer className="ops-footer"><form action="/auth/signout" method="post"><button className="text-action" type="submit">Cerrar sesión</button></form><span>CBTA 241 · AgroTech Territorial</span></footer>
      </section>
    </main>
  )
}
