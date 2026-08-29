import { z } from 'zod'

export const editorialStatusSchema = z.enum([
  'draft',
  'in_review',
  'approved',
  'scheduled',
  'published',
  'archived',
])

export const prioritySchema = z.enum(['normal', 'featured', 'priority', 'critical'])

const baseContentSchema = z.object({
  title: z.string().trim().min(3).max(220),
  slug: z.string().trim().max(180),
  summary: z.string().trim().max(500),
  bodyText: z.string().trim().max(20000),
  priority: prioritySchema,
})

export const createContentSchema = baseContentSchema

export const saveContentSchema = baseContentSchema.extend({
  id: z.string().uuid(),
  expectedRevision: z.coerce.number().int().positive(),
})

export const transitionContentSchema = z.object({
  id: z.string().uuid(),
  expectedRevision: z.coerce.number().int().positive(),
  targetStatus: editorialStatusSchema,
})

export function slugify(value: string) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 180)
}

export function structuredBody(bodyText: string) {
  return {
    schema_version: 1,
    blocks: bodyText.length > 0 ? [{ type: 'paragraph', text: bodyText }] : [],
  }
}

export function bodyTextFromUnknown(value: unknown) {
  if (!value || typeof value !== 'object') return ''
  const blocks = (value as { blocks?: unknown }).blocks
  if (!Array.isArray(blocks)) return ''
  return blocks
    .filter((block): block is { type: string; text: string } => {
      return Boolean(block && typeof block === 'object' && (block as { type?: unknown }).type === 'paragraph' && typeof (block as { text?: unknown }).text === 'string')
    })
    .map((block) => block.text)
    .join('\n\n')
}
