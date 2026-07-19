import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '../lib/supabase'
import { useFamilyStore } from '../store/familyStore'

export function useAuth() {
  // undefined = todavía comprobando; null = sin sesión; Session = autenticado
  const [session, setSession] = useState<Session | null | undefined>(undefined)
  const { loadFamily, reset } = useFamilyStore()

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session: s } }) => {
      setSession(s)
      if (s) loadFamily()
    })

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, s) => {
      setSession(s)
      if (event === 'SIGNED_IN')  loadFamily()
      if (event === 'SIGNED_OUT') reset()
    })

    return () => subscription.unsubscribe()
  }, [])

  return { session, loading: session === undefined }
}
