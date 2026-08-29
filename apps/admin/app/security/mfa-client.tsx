'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

const MFA_FRIENDLY_NAME = 'CBTA 241 Centro de Operaciones'

type Mode = 'loading' | 'enroll' | 'challenge' | 'error'

export function MfaClient() {
  const [mode, setMode] = useState<Mode>('loading')
  const [factorId, setFactorId] = useState('')
  const [qr, setQr] = useState('')
  const [secret, setSecret] = useState('')
  const [code, setCode] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    let active = true
    ;(async () => {
      const supabase = createClient()
      const aal = await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
      if (!active) return
      if (aal.error) {
        setError(aal.error.message)
        setMode('error')
        return
      }
      if (aal.data.currentLevel === 'aal2') {
        window.location.replace('/dashboard')
        return
      }

      const factors = await supabase.auth.mfa.listFactors()
      if (!active) return
      if (factors.error) {
        setError(factors.error.message)
        setMode('error')
        return
      }

      const verified = factors.data.totp[0]
      if (verified) {
        setFactorId(verified.id)
        setMode('challenge')
        return
      }

      // listFactors().totp contains only verified factors. The `all` collection
      // also exposes unverified enrollments, so use it to clean only stale factors
      // created by this exact CBTA enrollment flow before generating a new QR.
      const staleFactors = factors.data.all.filter(
        (factor) =>
          factor.factor_type === 'totp' &&
          factor.status === 'unverified' &&
          factor.friendly_name === MFA_FRIENDLY_NAME,
      )

      for (const pending of staleFactors) {
        const cleanup = await supabase.auth.mfa.unenroll({ factorId: pending.id })
        if (!active) return
        if (cleanup.error) {
          setError('No fue posible limpiar una configuración MFA incompleta. Cierra sesión e inténtalo nuevamente.')
          setMode('error')
          return
        }
      }

      const enrollment = await supabase.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: MFA_FRIENDLY_NAME,
      })
      if (!active) return
      if (enrollment.error) {
        setError(enrollment.error.message)
        setMode('error')
        return
      }

      setFactorId(enrollment.data.id)
      setQr(enrollment.data.totp.qr_code)
      setSecret(enrollment.data.totp.secret)
      setMode('enroll')
    })()

    return () => { active = false }
  }, [])

  async function verify() {
    if (!/^\d{6}$/.test(code)) {
      setError('Introduce el código de 6 dígitos del autenticador.')
      return
    }

    setBusy(true)
    setError('')
    try {
      const supabase = createClient()
      const challenge = await supabase.auth.mfa.challenge({ factorId })
      if (challenge.error) throw challenge.error

      const verification = await supabase.auth.mfa.verify({
        factorId,
        challengeId: challenge.data.id,
        code,
      })
      if (verification.error) throw verification.error

      await supabase.auth.refreshSession()
      window.location.replace('/dashboard')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No fue posible verificar el segundo factor.')
    } finally {
      setBusy(false)
    }
  }

  async function signOut() {
    const supabase = createClient()
    await supabase.auth.signOut()
    window.location.replace('/login')
  }

  return (
    <section className="mfa-panel" aria-live="polite">
      <div className="mfa-index">MFA / 02</div>
      {mode === 'loading' ? <p>Comprobando estado de seguridad…</p> : null}
      {mode === 'error' ? <div className="notice danger" role="alert">{error || 'Error de seguridad.'}</div> : null}

      {mode === 'enroll' ? (
        <>
          <h2>Vincular autenticador</h2>
          <p>Escanea este QR con Google Authenticator, Microsoft Authenticator, 1Password u otra app TOTP.</p>
          {qr ? <img className="mfa-qr" src={qr} alt="Código QR para configurar MFA" /> : null}
          <details>
            <summary>No puedo escanear el QR</summary>
            <code className="secret-code">{secret}</code>
          </details>
        </>
      ) : null}

      {mode === 'challenge' ? (
        <>
          <h2>Verificar segundo factor</h2>
          <p>Introduce el código actual de tu aplicación autenticadora.</p>
        </>
      ) : null}

      {mode === 'enroll' || mode === 'challenge' ? (
        <div className="form-stack compact">
          {error ? <div className="notice danger" role="alert">{error}</div> : null}
          <label>
            <span>Código TOTP</span>
            <input inputMode="numeric" pattern="[0-9]{6}" maxLength={6} autoComplete="one-time-code" value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))} />
          </label>
          <button className="primary-action" type="button" onClick={verify} disabled={busy}>{busy ? 'Verificando…' : 'Verificar y continuar'}</button>
        </div>
      ) : null}

      <button className="text-action" type="button" onClick={signOut}>Cerrar sesión</button>
    </section>
  )
}
