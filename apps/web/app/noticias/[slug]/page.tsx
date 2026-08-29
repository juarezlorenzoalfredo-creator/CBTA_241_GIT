import Link from 'next/link'
import { notFound } from 'next/navigation'
import { getNewsBySlug, paragraphBlocks } from '@/lib/public-content'
import styles from './article.module.css'

type Props = { params: Promise<{ slug: string }> }

export default async function NewsArticlePage({ params }: Props) {
  const { slug } = await params
  const item = await getNewsBySlug(slug)
  if (!item) notFound()
  const paragraphs = paragraphBlocks(item.body)
  const date = new Intl.DateTimeFormat('es-MX', { dateStyle: 'long' }).format(new Date(item.published_at))

  return (
    <main className={styles.shell}>
      <header className={styles.header}>
        <Link className={styles.back} href="/#ahora">← Volver al portal</Link>
        <span className="coordinate">CBTA / NOTICIA — PUBLICADA</span>
        <h1 className={styles.title}>{item.title}</h1>
        {item.summary ? <p className={styles.summary}>{item.summary}</p> : null}
        <div className={styles.meta}><span>{date}</span><span>Versión pública R{item.revision}</span></div>
      </header>
      <article className={styles.body}>
        <div className={styles.index}>241</div>
        <div className={styles.prose}>{paragraphs.length ? paragraphs.map((text,index)=><p key={index}>{text}</p>) : <p className={styles.empty}>Esta publicación no contiene bloques de texto visibles.</p>}</div>
      </article>
    </main>
  )
}
