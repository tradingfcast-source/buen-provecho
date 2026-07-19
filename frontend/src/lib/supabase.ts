import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL  as string
const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string

if (!supabaseUrl || !supabaseKey) {
  throw new Error('Faltan VITE_SUPABASE_URL o VITE_SUPABASE_ANON_KEY en el .env')
}

// Sin generic Database: las páginas anotan los tipos manualmente en los resultados.
// Para agregar tipado fuerte, ejecutar: supabase gen types typescript --project-id <id>
export const supabase = createClient(supabaseUrl, supabaseKey)
