'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { getAdminContext } from '@/lib/admin-context'
import {
  createContentSchema,
  saveContentSchema,
  slugify,
  structuredBody,
  transitionContentSchema,
} from '@/lib/content-schema'
import { createClient } from '@/lib/supabase/server'

async function requireAdmin() {
  const context = await getAdminContext()
  if (!context) redirect('/login')
  if (!context.has_admin_access) redirect('/access-denied')
  if (context.mfa_required && !context.mfa_satisfied) redirect('/security')
  return context
}

function contentInput(formData: FormData) {
  return {
    title: String(formData.get('title') ?? ''),
    slug: String(formData.get('slug') ?? ''),
    summary: String(formData.get('summary') ?? ''),
    bodyText: String(formData.get('bodyText') ?? ''),
    priority: String(formData.get('priority') ?? 'normal'),
  }
}

export async function createContent(formData: FormData) {
  const context = await requireAdmin()
  if (!context.permissions.includes('content.create')) redirect('/access-denied')

  const parsed = createContentSchema.safeParse(contentInput(formData))
  if (!parsed.success) redirect('/content/new?error=validation')

  const slug = slugify(parsed.data.slug || parsed.data.title)
  if (!slug) redirect('/content/new?error=validation')

  const supabase = await createClient()
  const { data, error } = await supabase
    .from('contents')
    .insert({
      content_type: 'news',
      title: parsed.data.title,
      slug,
      summary: parsed.data.summary || null,
      body: structuredBody(parsed.data.bodyText),
      seo: {
        title: parsed.data.title,
        description: parsed.data.summary || null,
      },
      priority: parsed.data.priority,
      created_by: context.user_id,
    })
    .select('id')
    .single()

  if (error?.code === '23505') redirect('/content/new?error=slug')
  if (error || !data?.id) redirect('/content/new?error=write')

  redirect(`/content/${data.id}?status=created`)
}

export async function saveContent(formData: FormData) {
  await requireAdmin()

  const parsed = saveContentSchema.safeParse({
    ...contentInput(formData),
    id: formData.get('id'),
    expectedRevision: formData.get('expectedRevision'),
  })
  if (!parsed.success) redirect(`/content/${String(formData.get('id') ?? '')}?error=validation`)

  const slug = slugify(parsed.data.slug || parsed.data.title)
  if (!slug) redirect(`/content/${parsed.data.id}?error=validation`)

  const supabase = await createClient()
  const { data, error } = await supabase
    .from('contents')
    .update({
      title: parsed.data.title,
      slug,
      summary: parsed.data.summary || null,
      body: structuredBody(parsed.data.bodyText),
      seo: {
        title: parsed.data.title,
        description: parsed.data.summary || null,
      },
      priority: parsed.data.priority,
    })
    .eq('id', parsed.data.id)
    .eq('revision', parsed.data.expectedRevision)
    .select('id,revision')
    .maybeSingle()

  if (error?.code === '23505') redirect(`/content/${parsed.data.id}?error=slug`)
  if (error) redirect(`/content/${parsed.data.id}?error=write`)
  if (!data) redirect(`/content/${parsed.data.id}?error=conflict`)

  revalidatePath('/content')
  revalidatePath(`/content/${parsed.data.id}`)
  redirect(`/content/${parsed.data.id}?status=saved`)
}

export async function transitionContent(formData: FormData) {
  await requireAdmin()

  const parsed = transitionContentSchema.safeParse({
    id: formData.get('id'),
    expectedRevision: formData.get('expectedRevision'),
    targetStatus: formData.get('targetStatus'),
  })
  if (!parsed.success) redirect('/content?error=transition')

  const supabase = await createClient()
  const { error } = await supabase.rpc('transition_content', {
    p_content_id: parsed.data.id,
    p_expected_revision: parsed.data.expectedRevision,
    p_target_status: parsed.data.targetStatus,
    p_publish_at: null,
  })

  if (error?.message?.includes('revision conflict')) redirect(`/content/${parsed.data.id}?error=conflict`)
  if (error) redirect(`/content/${parsed.data.id}?error=transition`)

  revalidatePath('/content')
  revalidatePath(`/content/${parsed.data.id}`)
  redirect(`/content/${parsed.data.id}?status=${parsed.data.targetStatus}`)
}
