import Link from 'next/link'
import { notFound, redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin-context'
import { bodyTextFromUnknown } from '@/lib/content-schema'
import { createClient } from '@/lib/supabase/server'
import { saveContent, transitionContent } from '../actions'
import styles from '../content.module.css'

type Props = {
  params: Promise<{ id: string }>
  searchParams: Promise<{ error?: string; status?: string }>
}

type ContentRecord = {
  id: string
  title: string
  slug: string
  summary: string | null
  body: unknown
  status: string
  priority: 'normal' | 'featured' | 'priority' | 'critical'
  revision: number
  updated_at: string
  created_by: string | null
}

type PublicationSnapshot = {
  revision: number
  published_at: string
  archived_at: string | null
}

const statusLabels: Record<string, string> = {
  draft: 'Borrador', in_review: 'En revisión', approved: 'Aprobado', scheduled: 'Programado', published: 'Publicado', archived: 'Archivado',
}

const preflightLabels: Record<string, string> = {
  expiration_in_past: 'La fecha de vigencia ya terminó.',
  news_summary_required: 'Agrega un resumen descriptivo de al menos 20 caracteres.',
  body_schema_invalid: 'El cuerpo no utiliza el esquema editorial aprobado.',
  body_blocks_required: 'El cuerpo no contiene bloques editoriales válidos.',
  news_body_required: 'Agrega al menos un párrafo sustantivo de 40 caracteres.',
  institutional_placeholder_detected: 'Hay un marcador institucional pendiente de validación que no puede publicarse.',
}

export default async function ContentDetailPage({ params, searchParams }: Props) {
  const context = await getAdminContext()
  if (!context) redirect('/login')
  if (!context.has_admin_access) redirect('/access-denied')
  if (context.mfa_required && !context.mfa_satisfied) redirect('/security')

  const { id } = await params
  const query = await searchParams
  const supabase = await createClient()
  const [contentResult, preflightResult, publicationResult] = await Promise.all([
    supabase.from('contents').select('id,title,slug,summary,body,status,priority,revision,updated_at,created_by').eq('id', id).maybeSingle(),
    supabase.rpc('get_content_preflight', { p_content_id: id }),
    supabase.from('content_publications').select('revision,published_at,archived_at').eq('content_id', id).maybeSingle(),
  ])

  if (contentResult.error || !contentResult.data) notFound()
  const item = contentResult.data as ContentRecord
  const preflight = !preflightResult.error && Array.isArray(preflightResult.data)
    ? preflightResult.data.filter((value): value is string => typeof value === 'string')
    : []
  const publication = !publicationResult.error && publicationResult.data
    ? publicationResult.data as PublicationSnapshot
    : null
  const editable = item.status === 'draft' || item.status === 'in_review'
  const canEdit = context.permissions.includes('content.edit_any') || (context.permissions.includes('content.edit_own') && item.created_by === context.user_id)
  const bodyText = bodyTextFromUnknown(item.body)
  const publicationIsLive = publication?.archived_at === null

  return (
    <main className={styles.shell}>
      <header className={styles.topline}>
        <div>
          <Link className={styles.back} href="/content">← Contenido</Link>
          <div className="coordinate dark">CBTA / CONTENT — EDIT</div>
          <h1 className={styles.title}>{item.title}</h1>
          <p className={styles.lead}>Revisión de trabajo R{item.revision} · {statusLabels[item.status] ?? item.status}. La versión pública se actualiza únicamente al publicar.</p>
        </div>
      </header>

      {publicationIsLive && publication && publication.revision !== item.revision ? (
        <div className={styles.notice} role="status">
          <strong>Last Known Good · R{publication.revision} sigue pública. </strong>
          <span>Estás trabajando sobre R{item.revision}. Los visitantes no verán estos cambios hasta que esta revisión vuelva a aprobarse y publicarse.</span>
        </div>
      ) : publicationIsLive && publication ? (
        <div className={styles.notice} role="status">
          <strong>Publicación vigente · R{publication.revision}. </strong>
          <span>Esta es la revisión que actualmente recibe el portal público.</span>
        </div>
      ) : null}

      {query.status ? <div className={styles.notice} role="status">Operación editorial completada: {statusLabels[query.status] ?? query.status}.</div> : null}
      {query.error ? <div className={`${styles.notice} ${styles.noticeError}`} role="alert">La operación no se aplicó. {query.error === 'conflict' ? 'Otra sesión modificó este contenido; recarga antes de continuar.' : 'Revisa el estado, el Preflight, tus permisos y los datos capturados.'}</div> : null}

      <div className={styles.formGrid}>
        <section>
          <form action={saveContent} className={styles.fields}>
            <input type="hidden" name="id" value={item.id} />
            <input type="hidden" name="expectedRevision" value={item.revision} />
            <label className={styles.field}><span>Título</span><input name="title" defaultValue={item.title} minLength={3} maxLength={220} disabled={!editable || !canEdit} required /></label>
            <label className={styles.field}><span>URL editorial</span><input name="slug" defaultValue={item.slug} maxLength={180} disabled={!editable || !canEdit} /></label>
            <label className={styles.field}><span>Resumen</span><textarea name="summary" defaultValue={item.summary ?? ''} maxLength={500} disabled={!editable || !canEdit} /></label>
            <label className={styles.field}><span>Cuerpo</span><textarea name="bodyText" defaultValue={bodyText} maxLength={20000} disabled={!editable || !canEdit} /></label>
            <label className={styles.field}><span>Prioridad editorial</span><select name="priority" defaultValue={item.priority} disabled={!editable || !canEdit}><option value="normal">Normal</option><option value="featured">Destacado</option><option value="priority">Prioritario</option><option value="critical">Crítico</option></select></label>
            {editable && canEdit ? <div className={styles.saveBar}><button className="primary-action" type="submit">Guardar cambios</button><span className={styles.hint}>Se usa control de revisión optimista; una edición concurrente no se sobrescribe en silencio.</span></div> : <p className={styles.frozen}>Este estado está congelado o tu rol no permite editarlo. Una revisión nunca reemplaza silenciosamente la copia pública vigente.</p>}
          </form>
        </section>

        <aside className={styles.side}>
          <div className={styles.fact}><small>Estado de trabajo</small><strong>{statusLabels[item.status] ?? item.status}</strong></div>
          <div className={styles.fact}><small>Revisión de trabajo</small><strong>R{item.revision}</strong></div>
          <div className={styles.fact}><small>Snapshot público</small><strong>{publicationIsLive && publication ? `R${publication.revision}` : 'Sin publicación vigente'}</strong></div>
          <div className={styles.fact}><small>Última modificación</small><strong>{new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(item.updated_at))}</strong></div>

          <section className={styles.preflight} aria-labelledby="preflight-heading">
            <h2 id="preflight-heading">Preflight</h2>
            {preflightResult.error ? <p className={styles.qualityError}>No fue posible evaluar la calidad editorial en este momento.</p> : preflight.length === 0 ? <p className={styles.qualityPass}>✓ Sin bloqueos editoriales mínimos.</p> : <ul className={styles.qualityList}>{preflight.map((code) => <li key={code}>{preflightLabels[code] ?? code}</li>)}</ul>}
          </section>

          <section className={styles.workflow}>
            <h2>Flujo editorial</h2>
            {item.status === 'draft' && canEdit && context.permissions.includes('content.submit') ? <TransitionButton id={item.id} revision={item.revision} target="in_review" label="Enviar a revisión" /> : null}
            {item.status === 'in_review' && canEdit ? <TransitionButton id={item.id} revision={item.revision} target="draft" label="Regresar a borrador" /> : null}
            {item.status === 'in_review' && context.permissions.includes('content.approve') ? <TransitionButton id={item.id} revision={item.revision} target="approved" label="Aprobar" /> : null}
            {item.status === 'approved' && canEdit ? <TransitionButton id={item.id} revision={item.revision} target="draft" label="Reabrir borrador" /> : null}
            {item.status === 'approved' && context.permissions.includes('content.publish') ? <TransitionButton id={item.id} revision={item.revision} target="published" label="Publicar ahora" /> : null}
            {item.status === 'scheduled' && context.permissions.includes('content.schedule') ? <TransitionButton id={item.id} revision={item.revision} target="approved" label="Cancelar programación" /> : null}
            {item.status === 'scheduled' && context.permissions.includes('content.publish') ? <TransitionButton id={item.id} revision={item.revision} target="published" label="Publicar si ya corresponde" /> : null}
            {item.status === 'published' && canEdit ? <TransitionButton id={item.id} revision={item.revision} target="draft" label="Iniciar nueva revisión" /> : null}
            {item.status === 'published' && context.permissions.includes('content.archive') ? <TransitionButton id={item.id} revision={item.revision} target="archived" label="Archivar publicación" danger /> : null}
            {item.status === 'archived' && context.permissions.includes('content.restore') ? <TransitionButton id={item.id} revision={item.revision} target="approved" label="Restaurar para republicar" /> : null}
          </section>
        </aside>
      </div>
    </main>
  )
}

function TransitionButton({ id, revision, target, label, danger = false }: { id: string; revision: number; target: string; label: string; danger?: boolean }) {
  return (
    <form action={transitionContent}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="expectedRevision" value={revision} />
      <input type="hidden" name="targetStatus" value={target} />
      <button className={danger ? styles.danger : styles.secondary} type="submit">{label}</button>
    </form>
  )
}
