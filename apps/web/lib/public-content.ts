export type PublicContent = {
  content_id: string
  revision: number
  content_type: string
  title: string
  slug: string
  summary: string | null
  body: unknown
  priority: string
  published_at: string
}

function configuration() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
  return url && key ? { url, key } : null
}

async function queryPublicContent(search: URLSearchParams): Promise<PublicContent[]> {
  const config = configuration()
  if (!config) return []
  try {
    const response = await fetch(`${config.url}/rest/v1/content_publications?${search.toString()}`, {
      headers: { apikey: config.key },
      cache: 'no-store',
    })
    if (!response.ok) return []
    const value: unknown = await response.json()
    if (!Array.isArray(value)) return []
    return value.filter((row): row is PublicContent => Boolean(row && typeof row === 'object' && typeof (row as PublicContent).title === 'string' && typeof (row as PublicContent).slug === 'string'))
  } catch {
    return []
  }
}

const PUBLIC_COLUMNS = 'content_id,revision,content_type,title,slug,summary,body,priority,published_at'

export async function getLatestNews(limit = 3) {
  const search = new URLSearchParams({
    select: PUBLIC_COLUMNS,
    content_type: 'eq.news',
    order: 'published_at.desc',
    limit: String(Math.max(1, Math.min(limit, 12))),
  })
  return queryPublicContent(search)
}

export async function getNewsBySlug(slug: string) {
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) return null
  const search = new URLSearchParams({
    select: PUBLIC_COLUMNS,
    content_type: 'eq.news',
    slug: `eq.${slug}`,
    limit: '1',
  })
  const rows = await queryPublicContent(search)
  return rows[0] ?? null
}

export function paragraphBlocks(body: unknown) {
  if (!body || typeof body !== 'object') return []
  const blocks = (body as { blocks?: unknown }).blocks
  if (!Array.isArray(blocks)) return []
  return blocks.flatMap((block) => {
    if (!block || typeof block !== 'object') return []
    const candidate = block as { type?: unknown; text?: unknown }
    return candidate.type === 'paragraph' && typeof candidate.text === 'string' ? [candidate.text] : []
  })
}
