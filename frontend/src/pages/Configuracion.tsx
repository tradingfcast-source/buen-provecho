import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useFamilyStore } from '../store/familyStore'
import type { DietaryPattern, FoodRestriction } from '../types/database'

const ROLE_LABEL: Record<string, string> = {
  owner:         'Propietario',
  adult:         'Adulto',
  member:        'Miembro',
  support_staff: 'Personal de apoyo',
  guest:         'Invitado',
}

export default function Configuracion() {
  const { currentFamily, members, setMembers } = useFamilyStore()
  const [patterns,     setPatterns]     = useState<DietaryPattern[]>([])
  const [restrictions, setRestrictions] = useState<FoodRestriction[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!currentFamily) { setLoading(false); return }
    loadData()
  }, [currentFamily])

  async function loadData() {
    setLoading(true)
    const [membersRes, patternsRes, restrictionsRes] = await Promise.all([
      supabase.from('family_members').select('*').eq('family_id', currentFamily!.id).order('created_at'),
      supabase.from('dietary_patterns').select('*').eq('family_id', currentFamily!.id).eq('active', true),
      supabase.from('food_restrictions').select('*').eq('family_id', currentFamily!.id),
    ])
    setMembers((membersRes.data ?? []) as any)
    setPatterns((patternsRes.data ?? []) as DietaryPattern[])
    setRestrictions((restrictionsRes.data ?? []) as FoodRestriction[])
    setLoading(false)
  }

  if (!currentFamily) {
    return (
      <div className="flex flex-col items-center justify-center h-64 gap-4">
        <span className="text-4xl">⚙️</span>
        <p className="text-gray-500">No perteneces a ninguna familia aún.</p>
        <button
          className="px-4 py-2 rounded-xl bg-[var(--color-brand)] text-white text-sm font-medium"
          onClick={() => alert('TODO: crear familia')}
        >
          Crear familia
        </button>
      </div>
    )
  }

  return (
    <div className="px-4 pt-4 space-y-6 pb-8">
      {/* Datos de la familia */}
      <section>
        <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide mb-2">Familia</h2>
        <div className="p-4 rounded-xl bg-white border border-gray-100 shadow-xs">
          <p className="font-bold text-gray-800">{currentFamily.name}</p>
          <p className="text-sm text-gray-500 mt-1">
            {currentFamily.country_code} · {currentFamily.currency_code} · {currentFamily.timezone}
          </p>
          <button
            className="mt-3 text-xs text-[var(--color-brand)] underline"
            onClick={() => alert('TODO: editar datos de familia')}
          >
            Editar configuración
          </button>
        </div>
      </section>

      {/* Miembros */}
      <section>
        <div className="flex items-center justify-between mb-2">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide">Miembros</h2>
          <button
            className="text-xs px-2 py-1 rounded-lg bg-[var(--color-brand-pale)] text-[var(--color-brand)]"
            onClick={() => alert('TODO: agregar miembro')}
          >
            + Agregar
          </button>
        </div>

        {loading ? (
          <div className="space-y-2">
            {[1, 2].map(i => <div key={i} className="h-16 rounded-xl bg-gray-100 animate-pulse" />)}
          </div>
        ) : (
          <div className="space-y-2">
            {members.map(m => {
              const pattern = patterns.find(p => p.family_member_id === m.id)
              return (
                <div key={m.id} className="p-3 rounded-xl bg-white border border-gray-100 shadow-xs">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-semibold text-gray-800">{m.display_name}</p>
                      <p className="text-xs text-gray-400">
                        {ROLE_LABEL[m.role] ?? m.role}
                        {' · '}Porción ×{m.portion_factor}
                      </p>
                    </div>
                    <button
                      className="text-xs text-gray-400 hover:text-[var(--color-brand)]"
                      onClick={() => alert(`TODO: editar ${m.display_name}`)}
                    >
                      ✏️
                    </button>
                  </div>

                  {pattern && (
                    <div className="mt-2 flex gap-2 flex-wrap">
                      <span className="text-xs px-2 py-0.5 rounded-full bg-blue-50 text-blue-600">
                        {pattern.label}
                      </span>
                      {pattern.carb_multiplier !== 1 && (
                        <span className="text-xs px-2 py-0.5 rounded-full bg-orange-50 text-orange-600">
                          Carbohidratos ×{pattern.carb_multiplier}
                        </span>
                      )}
                      {pattern.portion_multiplier !== 1 && (
                        <span className="text-xs px-2 py-0.5 rounded-full bg-purple-50 text-purple-600">
                          Porción ×{pattern.portion_multiplier}
                        </span>
                      )}
                      {pattern.require_snacks && (
                        <span className="text-xs px-2 py-0.5 rounded-full bg-pink-50 text-pink-600">
                          Snacks obligatorios
                        </span>
                      )}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </section>

      {/* Restricciones alimentarias */}
      <section>
        <div className="flex items-center justify-between mb-2">
          <h2 className="text-sm font-semibold text-gray-500 uppercase tracking-wide">Restricciones</h2>
          <button
            className="text-xs px-2 py-1 rounded-lg bg-[var(--color-brand-pale)] text-[var(--color-brand)]"
            onClick={() => alert('TODO: agregar restricción')}
          >
            + Agregar
          </button>
        </div>

        {restrictions.length === 0 ? (
          <p className="text-sm text-gray-400 italic">Sin restricciones registradas.</p>
        ) : (
          <div className="flex flex-wrap gap-2">
            {restrictions.map(r => (
              <div key={r.id} className="flex items-center gap-1 px-3 py-1.5 rounded-full bg-red-50 border border-red-100">
                <span className="text-xs font-medium text-red-700">
                  {r.restriction_type === 'exclude' ? '🚫' : '⚠️'} {r.tag}
                </span>
                {r.family_member_id && (
                  <span className="text-xs text-red-400">
                    · {members.find(m => m.id === r.family_member_id)?.display_name ?? '?'}
                  </span>
                )}
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Acciones de cuenta */}
      <section className="pt-4 border-t border-gray-100">
        <button
          onClick={async () => {
            await supabase.auth.signOut()
            useFamilyStore.getState().reset()
          }}
          className="w-full py-3 rounded-xl border border-gray-200 text-sm text-gray-500 hover:border-red-200 hover:text-red-500 transition-colors"
        >
          Cerrar sesión
        </button>
      </section>
    </div>
  )
}
