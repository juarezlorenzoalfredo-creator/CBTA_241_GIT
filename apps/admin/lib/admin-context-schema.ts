import { z } from 'zod'

export const adminContextSchema = z.object({
  user_id: z.string().uuid(),
  is_active: z.boolean(),
  has_admin_access: z.boolean(),
  roles: z.array(z.string().min(1).max(64)),
  permissions: z.array(z.string().min(1).max(96)),
  is_superadministrator: z.boolean(),
  aal: z.enum(['aal1', 'aal2']),
  mfa_required: z.boolean(),
  mfa_satisfied: z.boolean(),
}).strict()

export type AdminContext = z.infer<typeof adminContextSchema>

export function parseAdminContext(data: unknown, expectedUserId: string): AdminContext {
  const parsed = adminContextSchema.safeParse(data)
  if (!parsed.success || parsed.data.user_id !== expectedUserId) {
    throw new Error('Invalid administrative authorization context')
  }
  return parsed.data
}
