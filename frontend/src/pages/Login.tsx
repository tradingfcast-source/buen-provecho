import { useState } from 'react'
import { supabase } from '../lib/supabase'

type Step = 'form' | 'sending' | 'sent' | 'error'

export default function Login() {
  const [email, setEmail] = useState('')
  const [step,  setStep]  = useState<Step>('form')
  const [errMsg, setErrMsg] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!email.trim()) return
    setStep('sending')

    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: window.location.origin },
    })

    if (error) {
      setErrMsg(error.message)
      setStep('error')
    } else {
      setStep('sent')
    }
  }

  return (
    <div className="min-h-screen flex flex-col items-center justify-center px-6 bg-[var(--color-bg)]">
      {/* Logo / Marca */}
      <div className="mb-8 text-center">
        <div className="w-16 h-16 rounded-2xl bg-[var(--color-brand)] flex items-center justify-center mx-auto mb-4 text-3xl">
          🍽️
        </div>
        <h1 className="text-2xl font-bold text-gray-900">Buen Provecho</h1>
        <p className="text-sm text-gray-500 mt-1">Planificación familiar de comidas</p>
      </div>

      {step === 'sent' ? (
        /* Confirmación */
        <div className="w-full max-w-sm text-center">
          <div className="text-5xl mb-4">📬</div>
          <h2 className="text-lg font-semibold text-gray-800 mb-2">Revisa tu correo</h2>
          <p className="text-sm text-gray-500">
            Enviamos un enlace mágico a <strong>{email}</strong>.
            Haz clic en él para ingresar.
          </p>
          <button
            className="mt-6 text-sm text-[var(--color-brand)] underline"
            onClick={() => setStep('form')}
          >
            Usar otro correo
          </button>
        </div>
      ) : (
        /* Formulario */
        <form onSubmit={handleSubmit} className="w-full max-w-sm space-y-4">
          <div>
            <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
              Correo electrónico
            </label>
            <input
              id="email"
              type="email"
              required
              autoFocus
              value={email}
              onChange={e => setEmail(e.target.value)}
              placeholder="tu@correo.com"
              className="w-full px-4 py-3 rounded-xl border border-gray-200 bg-white text-gray-900
                         placeholder-gray-400 focus:outline-none focus:ring-2
                         focus:ring-[var(--color-brand-light)] focus:border-transparent text-base"
            />
          </div>

          {step === 'error' && (
            <p className="text-sm text-red-500 px-1">{errMsg}</p>
          )}

          <button
            type="submit"
            disabled={step === 'sending'}
            className="w-full py-3 rounded-xl bg-[var(--color-brand)] text-white font-semibold
                       text-base shadow-sm hover:opacity-90 transition disabled:opacity-50"
          >
            {step === 'sending' ? 'Enviando…' : 'Enviar enlace mágico'}
          </button>

          <p className="text-xs text-center text-gray-400">
            Sin contraseñas. Recibirás un enlace de acceso en tu correo.
          </p>
        </form>
      )}
    </div>
  )
}
