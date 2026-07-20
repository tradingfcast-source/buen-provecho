import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useFamilyStore } from '../store/familyStore'
import { toast } from '../components/ui/Toast'
import type { DishSlot, DishAssignment, Recipe, WeeklyPlan } from '../types/database'

interface SlotRow {
  slot:       DishSlot
  assignment: (DishAssignment & { recipe: Recipe }) | null
}

const DOW_NAMES = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb']

export default function Planificacion() {
  const { currentFamily, activePlan, setActivePlan } = useFamilyStore()
  const [rows,    setRows]    = useState<SlotRow[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!currentFamily) { setLoading(false); return }
    loadPlanAndSlots()
  }, [currentFamily])

  async function loadPlanAndSlots() {
    setLoading(true)

    const { data: rawPlans } = await supabase
      .from('weekly_plans').select('*')
      .eq('family_id', currentFamily!.id)
      .in('status', ['active', 'planned', 'voting', 'draft'])
      .order('week_start_date', { ascending: false }).limit(1)
    const plan = ((rawPlans ?? []) as WeeklyPlan[])[0] ?? null
    setActivePlan(plan)

    if (!plan) { setLoading(false); return }

    const { data: rawSlots } = await supabase
      .from('dish_slots').select('*')
      .eq('family_id', currentFamily!.id).order('sort_order')
    const dishSlots = (rawSlots ?? []) as DishSlot[]

    const { data: rawAssign } = await supabase
      .from('dish_assignments').select('*, recipes(*)')
      .eq('weekly_plan_id', plan.id).eq('is_adhoc', false)
    const assignments = (rawAssign ?? []) as Array<DishAssignment & { recipes: Recipe }>

    const bySlot: Record<string, DishAssignment & { recipe: Recipe }> = {}
    assignments.forEach(a => {
      if (a.dish_slot_id) bySlot[a.dish_slot_id] = { ...a, recipe: a.recipes }
    })

    setRows(dishSlots.map(slot => ({
      slot,
      assignment: bySlot[slot.id] ?? null,
    })))
    setLoading(false)
  }

  function slotLabel(slot: DishSlot, weekStart: string): string {
    return slot.day_offsets.map(offset => {
      const d = new Date(weekStart + 'T12:00:00')
      d.setDate(d.getDate() + offset)
      return DOW_NAMES[d.getDay()]
    }).join(' · ')
  }

  if (!currentFamily) {
    return (
      <div className="flex flex-col items-center justify-center h-64 gap-4 text-gray-500">
        <span className="text-4xl">📅</span>
        <p>Configura tu familia primero.</p>
      </div>
    )
  }

  return (
    <div className="px-4 pt-4">
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-lg font-semibold text-gray-800">Menú semanal</h1>
        {activePlan && (
          <span className="text-xs px-2 py-1 rounded-full bg-[var(--color-brand-pale)] text-[var(--color-brand)] font-medium capitalize">
            {activePlan.status}
          </span>
        )}
      </div>

      {activePlan && (
        <p className="text-sm text-gray-400 mb-4">
          Semana del {new Date(activePlan.week_start_date + 'T12:00:00')
            .toLocaleDateString('es-PE', { day: 'numeric', month: 'short' })}
        </p>
      )}

      {loading ? (
        <div className="space-y-3">
          {[1, 2, 3, 4].map(i => (
            <div key={i} className="h-24 rounded-xl bg-gray-100 animate-pulse" />
          ))}
        </div>
      ) : !activePlan ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">📋</p>
          <p>No hay plan activo esta semana.</p>
          <button
            className="mt-4 px-4 py-2 rounded-xl bg-[var(--color-brand)] text-white text-sm font-medium"
            onClick={() => toast.info('Crear plan — próximamente')}
          >
            Crear plan
          </button>
        </div>
      ) : (
        <div className="space-y-3">
          {rows.map(({ slot, assignment }) => (
            <div
              key={slot.id}
              className="p-4 rounded-xl border border-gray-100 bg-white shadow-sm"
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-medium text-gray-400 uppercase tracking-wide mb-1">
                    {slotLabel(slot, activePlan.week_start_date)}
                  </p>
                  {assignment ? (
                    <p className="font-semibold text-gray-800">{assignment.recipe.name}</p>
                  ) : (
                    <p className="text-gray-400 italic text-sm">Sin asignar</p>
                  )}
                </div>
                <button
                  className="shrink-0 text-xs px-3 py-1.5 rounded-lg border border-[var(--color-brand)] text-[var(--color-brand)] hover:bg-[var(--color-brand-pale)] transition-colors"
                  onClick={() => toast.info(`Asignación de recetas — próximamente`)}
                >
                  {assignment ? 'Cambiar' : 'Asignar'}
                </button>
              </div>

              {activePlan.status === 'voting' && (
                <button
                  className="mt-2 text-xs text-[var(--color-brand)] underline"
                  onClick={() => toast.info('Votación — próximamente')}
                >
                  Ver votos
                </button>
              )}
            </div>
          ))}

          <button
            className="w-full mt-2 py-3 rounded-xl border-2 border-dashed border-gray-200 text-sm text-gray-400 hover:border-[var(--color-brand)] hover:text-[var(--color-brand)] transition-colors"
            onClick={() => toast.info('Plato a demanda — próximamente')}
          >
            + Plato a demanda
          </button>
        </div>
      )}
    </div>
  )
}
