import Link from 'next/link'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin-context'
import { createClient } from '@/lib/supabase/server'
import styles from './content.module.css'

type ContentRow = {
  id: string
  title: string
  content_type: string
  status: string
  revision: number
  updated_at: string
}

const statusLabels: Record<string, string> = {
  draft: 'Borrador',
  in_review: 'En revisión',
  approved: 'Aprobado',
  scheduled: 'Programado',
  published: 'Publicado',
  archived: 'Archivado',
}

export default async function ContentPage() {
  const context = await getAdminContext()
  if (!context) redirect('/login')
  if (!context.has_admin_access) redirect('/access-denied')
  if (context.mfa_required && !context.mfa_satisfied) redirect('/security')

  const supabase = await createClient()
  const { data, error } = await supabase
    .from('contents')
    .select('id,title,content_type,status,revision,updated_at')
    .order('updated_at', { ascending: false })
    .limit(60)

  if (error) throw new Error('Unable to load editorial content')
  const items = (data ?? []) as ContentRow[]

  return (
    <main className={styles.shell}>
      <header className={styles.topline}>
        <div>
          <Link className={styles.back} href="/dashboard">← Centro de Operaciones</Link>
          <div className="coordinate dark">CBTA / CONTENT — 01</div>
          <h1 className={styles.title}>Contenido</h1>
          <p className={styles.lead}>Mesa editorial con versiones, revisión y publicación controlada. La copia pública permanece separada del borrador de trabajo.</p>
        </div>
        {context.permissions.includes('content.create') ? <Link className={styles.action} href="/content/new">Nuevo contenido</Link> : null}
      </header>

      <section className={styles.index} aria-label="Contenido editorial">
        {items.length === 0 ? <p className={styles.empty}>Todavía no existe contenido editorial. No se crearán noticias de demostración ni datos institucionales ficticios.</p> : null}
        {items.map((item, position) => (
          <Link className={styles.row} href={`/content/${item.id}`} key={item.id}>
            <span className={styles.number}>{String(position + 1).padStart(2, '0')}</span>
            <strong className={styles.rowTitle}>{item.title}</strong>
            <span className={styles.meta}>{item.content_type}</span>
            <span className={styles.meta}>R{item.revision}</span>
            <span className={styles.status}>{statusLabels[item.status] ?? item.status}</span>
          </Link>
        ))}
      </section>
    </main>
  )
}
