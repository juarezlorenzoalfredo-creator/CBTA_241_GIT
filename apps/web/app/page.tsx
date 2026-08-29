import Link from 'next/link'
import { getLatestNews } from '@/lib/public-content'
import styles from './home.module.css'

const tracks = [['01','Producción'],['02','Tecnología'],['03','Ciencia'],['04','Sustentabilidad']] as const

export default async function HomePage() {
  const news = await getLatestNews(3)
  return (
    <main>
      <header className="site-header"><div className="brand-mark">CBTA <strong>241</strong></div><nav aria-label="Navegación principal"><a href="#futuro">Oferta</a><a href="#ahora">Ahora</a><a href="#aspirantes">Aspirantes</a><a href="#territorio">Territorio</a></nav></header>
      <section className="territorial-hero"><div className="hero-copy"><span className="coordinate">CBTA / TERRITORIO — 01</span><p className="kicker">Educación · campo · tecnología</p><h1>Del territorio al conocimiento.</h1><p className="hero-note">Una plataforma institucional diseñada para mostrar evidencia real del aprendizaje, la comunidad y el entorno productivo.</p></div><div className="hero-field" aria-hidden="true"><span>241</span></div></section>

      <section className={styles.now} id="ahora">
        <header className={styles.nowHeader}><div><span className="coordinate">CBTA / AHORA — 02</span><h2>Ahora en el CBTA 241</h2></div><p>Solo aparece contenido que completó el flujo editorial y tiene una versión pública vigente.</p></header>
        {news.length ? <div className={styles.newsList}>{news.map((item,index)=><Link className={styles.newsRow} href={`/noticias/${item.slug}`} key={item.content_id}><span className={styles.newsIndex}>{String(index+1).padStart(2,'0')}</span><strong className={styles.newsTitle}>{item.title}</strong><span className={styles.newsMeta}>Noticia · R{item.revision}</span></Link>)}</div> : <p className={styles.empty}>No hay noticias institucionales publicadas todavía. El portal no mostrará contenido de demostración como si fuera información oficial.</p>}
      </section>

      <section className="future" id="futuro"><div><span className="coordinate dark">CBTA / OFERTA — 03</span><h2>Explora tu futuro</h2></div><div className="track-list">{tracks.map(([n,label])=><div className="track" key={n}><span>{n}</span><strong>{label}</strong><i /></div>)}</div></section>
      <section className="evidence" id="aspirantes"><div className="evidence-number">04</div><div><span className="kicker">Proyectos que nacen aquí</span><h2>Primero evidencia. Después, discurso.</h2><p>Esta sección se conectará al CMS para mostrar proyectos, instalaciones, convocatorias y actividad real verificada por el CBTA 241.</p></div></section>
      <footer id="territorio"><span>CBTA 241</span><span>AgroTech Territorial · Foundation</span></footer>
    </main>
  )
}
