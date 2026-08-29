import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin-context'
import { createContent } from '../actions'
import styles from '../content.module.css'

type Props = { searchParams: Promise<{ error?: string }> }

export default async function NewContentPage({ searchParams }: Props) {
  const context = await getAdminContext()
  if (!context) redirect('/login')
  if (!context.has_admin_access || !context.permissions.includes('content.create')) redirect('/access-denied')
  if (context.mfa_required && !context.mfa_satisfied) redirect('/security')
  const params = await searchParams

  return (
    <main className={styles.shell}>
      <header className={styles.topline}>
        <div>
          <Link className={styles.back} href="/content">← Contenido</Link>
          <div className="coordinate dark">CBTA / CONTENT — NEW</div>
          <h1 className={styles.title}>Nueva noticia</h1>
          <p className={styles.lead}>Empieza como borrador. Nada de lo escrito aquí será público hasta completar revisión, aprobación y publicación.</p>
        </div>
      </header>

      {params.error ? <div className={`${styles.notice} ${styles.noticeError}`} role="alert">No fue posible crear el borrador. Revisa los campos y que la URL editorial no esté repetida.</div> : null}

      <form action={createContent} className={styles.formGrid}>
        <section className={styles.fields}>
          <label className={styles.field}><span>Título</span><input name="title" minLength={3} maxLength={220} required /></label>
          <label className={styles.field}><span>URL editorial</span><input name="slug" maxLength={180} placeholder="Se genera desde el título si se deja vacío" /></label>
          <label className={styles.field}><span>Resumen</span><textarea name="summary" maxLength={500} /></label>
          <label className={styles.field}><span>Cuerpo</span><textarea name="bodyText" maxLength={20000} /></label>
          <div className={styles.saveBar}><button className="primary-action" type="submit">Crear borrador</button><span className={styles.hint}>Sin HTML libre. El cuerpo se guarda como contenido estructurado.</span></div>
        </section>
        <aside className={styles.side}>
          <label className={styles.field}><span>Prioridad editorial</span><select name="priority" defaultValue="normal"><option value="normal">Normal</option><option value="featured">Destacado</option><option value="priority">Prioritario</option><option value="critical">Crítico</option></select></label>
          <div className={styles.fact}><small>Estado inicial</small><strong>Borrador</strong></div>
          <div className={styles.fact}><small>Tipo</small><strong>Noticia</strong></div>
        </aside>
      </form>
    </main>
  )
}
