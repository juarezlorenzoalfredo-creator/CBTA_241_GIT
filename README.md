# Portal Institucional CBTA 241

Fundación técnica del Portal Digital Institucional del CBTA 241.

## Dirección de producto

- Identidad visual: **AgroTech Territorial**.
- Portal público y Centro de Operaciones separados.
- Next.js + React + TypeScript.
- Supabase Auth/PostgreSQL/RLS.
- RBAC granular y MFA para operaciones privilegiadas.
- Fuente Institucional de Verdad y flujo editorial versionado.
- Publicación **Last Known Good**: el borrador de trabajo nunca sustituye silenciosamente la última copia pública aprobada.

## Aplicaciones

- `apps/web`: portal público.
- `apps/admin`: Centro de Operaciones.

## Seguridad

Nunca agregues claves `secret`, `service_role`, contraseñas, tokens, direcciones de cuentas privilegiadas ni secretos MFA al repositorio. El frontend usa únicamente la publishable key de Supabase y toda autorización real se valida en Postgres/RLS.

La activación inicial usa una Edge Function de un solo propósito. El destinatario privilegiado se conserva fuera del código y se valida contra la huella aprobada en la base. La función permanece cerrada hasta que el entorno tenga configurados, fuera del repositorio:

- `CBTA_BOOTSTRAP_EMAIL`: identidad inicial autorizada.
- `CBTA_ADMIN_ACTIVATION_URL`: URL HTTPS exacta de `/auth/confirm`, sin query ni fragmento.

La plantilla de invitación está versionada en `supabase/templates/invite.html`. El correo entrega un `token_hash` al endpoint SSR `/auth/confirm`; ese endpoint verifica exclusivamente invitaciones y valida el contexto SUPERADMIN en tiempo de ejecución. `/activate/complete` vuelve a exigir que la sesión provenga del método de autenticación `invite` antes de aceptar la contraseña, y la mutación se ejecuta en una Server Action, no desde el navegador. Al terminar, la sesión de invitación se cierra y el administrador debe iniciar sesión con la nueva contraseña; ese login lo conduce a MFA/TOTP antes de permitir operaciones privilegiadas.

El bootstrap de base de datos exige evidencia persistida de invitación (`auth.users.invited_at`) antes de conceder SUPERADMIN. Las migraciones 008 y 009 documentan una auditoría adversarial adicional: se descartó un guard `BEFORE INSERT` incompatible con el orden interno de Supabase Auth y se conservó la protección en el punto correcto, al otorgar privilegios.

## Flujo editorial

El primer vertical slice funcional ya conecta el Centro de Operaciones con el portal público:

`Borrador → Revisión → Aprobado → Publicado → Snapshot público`

La tabla de trabajo `contents` dejó de ser una fuente pública. `content_publications` conserva la última versión pública válida. Si un contenido publicado entra otra vez a borrador, el visitante sigue recibiendo el snapshot anterior hasta que la nueva revisión vuelva a aprobarse y publicarse.

Las transiciones de estado pasan exclusivamente por `transition_content`, con revisión optimista y permisos RBAC/RLS. El marcador interno de workflow se limita al alcance del RPC y no queda disponible para una sentencia posterior.

El **Content Integrity Gate** de base de datos permite borradores incompletos, pero bloquea el avance de noticias a revisión/aprobación/publicación cuando faltan resumen o cuerpo sustantivo, el esquema estructurado es inválido, la vigencia terminó o aparece el marcador explícito `DATO INSTITUCIONAL PENDIENTE DE VALIDACIÓN`.

El portal público consulta únicamente `content_publications`; no se crean noticias de demostración ni datos institucionales ficticios.

## Base de datos

`supabase/migrations/` contiene las migraciones 001–015 correspondientes a la Foundation aplicada en el proyecto remoto. `supabase/functions/` conserva el código desplegable de funciones Edge.

## Quality Gate

CI rechaza patrones evidentes de secretos versionados, instala desde `package-lock.json`, ejecuta `npm audit --audit-level=high`, TypeScript estricto y build de ambas aplicaciones. Ningún PR debe pasar a integración si este gate falla.

Las pruebas transaccionales de base de datos cubren permisos de Editor/Publicador, AAL2, versionamiento, auditoría, aislamiento de snapshots, Last Known Good, archivo público y Content Integrity Gate. Los usuarios y contenidos sintéticos se ejecutan dentro de transacciones revertidas.

## Estado

Foundation y vertical slice editorial activos en la rama de trabajo. La base remota `CBTA_241` contiene RBAC/RLS, bootstrap protegido, auditoría, contexto administrativo, snapshots de publicación y preflight editorial. La cuenta inicial solo obtiene SUPERADMIN tras validar una identidad invitada y confirmada, y después debe alcanzar AAL2 mediante MFA/TOTP para operaciones privilegiadas.
