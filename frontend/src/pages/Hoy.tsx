import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useFamilyStore } from '../store/familyStore'
import type { DishAssignment, MealSlot, Recipe } from '../types/database'

interface SlotWithDish {
  slot:       MealSlot
  recipe:     Recipe | null
  assignment: DishAssignment | null
}

const HOY_LABEL = new Intl.DateTimeFormat('es-PE', {
  weekday: 'long', day: 'numeric', month: 'long',
})

export default function Hoy() {
  const { currentFamily } = useFamilyStore()
  const [slots,   setSlots]   = useState<SlotWithDish[]>([])
  const [loading, setLoading] = useState(true)

  const today = new Date().toISOString().slice(0, 10)

  useEffect(() => {
    if (!currentFamily) { setLoading(false); return }
    load()
  }, [currentFamily])

  async function load() {
    setLoading(true)

    // 1. Meal slots de la familia
    const { data: rawSlots } = await supabase
      .from('meal_slots').select('*')
      .eq('family_id', currentFamily!.id).order('sort_order')
    const mealSlots = (rawSlots ?? []) as MealSlot[]

    // 2. Plan activo o planificado
    const { data: rawPlans } = await supabase
      .from('weekly_plans').select('id, week_start_date')
      .eq('family_id', currentFamily!.id)
      .in('status', ['planned', 'active'])
    const plans = (rawPlans ?? []) as { id: string; week_start_date: string }[]
    const planIds = plans.map(p => p.id)

    const assignBySlot: Record<string, { recipe: Recipe; assignment: DishAssignment }> = {}

    if (planIds.length > 0) {
      // 3a. Asignaciones de bloque que incluyan hoy
      const { data: rawBlock } = await supabase
        .from('dish_assignments')
        .select('*, recipes(*), dish_slots(meal_slot_id, day_offsets), weekly_plans(week_start_date)')
        .eq('family_id', currentFamily!.id)
        .eq('is_adhoc', false)
        .in('weekly_plan_id', planIds)
      const blockAssignments = (rawBlock ?? []) as Array<Record<string, unknown>>

      blockAssignments.forEach(a => {
        const weekStart  = new Date(((a.weekly_plans as Record<string,string>)?.week_start_date ?? '') + 'T12:00:00')
        const offsets    = ((a.dish_slots as Record<string, number[]>)?.day_offsets ?? []) as number[]
        const mealSlotId = (a.dish_slots as Record<string, string>)?.meal_slot_id as string
        const recipe     = a.recipes as Recipe

        for (const offset of offsets) {
          const blockDate = new Date(weekStart)
          blockDate.setDate(blockDate.getDate() + offset)
          if (blockDate.toISOString().slice(0, 10) === today && mealSlotId) {
            assignBySlot[mealSlotId] = { recipe, assignment: a as unknown as DishAssignment }
          }
        }
      })
    }

    // 3b. Ad-hoc de hoy (sobreescriben bloque)
    const { data: rawAdhoc } = await supabase
      .from('dish_assignments').select('*, recipes(*)')
      .eq('family_id', currentFamily!.id)
      .eq('is_adhoc', true).eq('adhoc_date', today)
    const adhocAssignments = (rawAdhoc ?? []) as Array<DishAssignment & { recipes: Recipe }>

    adhocAssignments.forEach(a => {
      if (a.adhoc_meal_slot_id && a.recipes) {
        assignBySlot[a.adhoc_meal_slot_id] = { recipe: a.recipes, assignment: a }
      }
    })

    setSlots(mealSlots.map(slot => ({
      slot,
      recipe:     assignBySlot[slot.id]?.recipe     ?? null,
      assignment: assignBySlot[slot.id]?.assignment ?? null,
    })))
    setLoading(false)
  }

  if (!currentFamily) {
    return (
      <div className="flex flex-col items-center justify-center h-64 gap-4 text-gray-500">
        <span className="text-4xl">🏠</span>
        <p>Crea o únete a una familia primero.</p>
      </div>
    )
  }

  return (
    <div className="px-4 pt-4">
      <h1 className="text-lg font-semibold text-gray-800 capitalize mb-4">
        {HOY_LABEL.format(new Date())}
      </h1>

      {loading ? (
        <div className="space-y-3">
          {[1, 2, 3].map(i => (
            <div key={i} className="h-20 rounded-xl bg-gray-100 animate-pulse" />
          ))}
        </div>
      ) : (
        <div className="space-y-3">
          {slots.map(({ slot, recipe, assignment }) => (
            <div
              key={slot.id}
              className="flex items-center gap-3 p-4 rounded-xl border border-gray-100 bg-white shadow-sm"
            >
              <div className="flex-1 min-w-0">
                <p className="text-xs font-medium text-gray-400 uppercase tracking-wide">
                  {slot.name}
                  {slot.default_time && (
                    <span className="ml-1 normal-case">· {slot.default_time.slice(0, 5)}</span>
                  )}
                </p>
                {recipe ? (
                  <p className="font-semibold text-gray-800 truncate">{recipe.name}</p>
                ) : (
                  <p className="text-gray-400 italic text-sm">Sin plato asignado</p>
                )}
              </div>

              {recipe && assignment ? (
                <button
                  className="w-8 h-8 rounded-full border-2 border-[var(--color-brand)] flex items-center justify-center text-[var(--color-brand)] hover:bg-[var(--color-brand-pale)] transition-colors"
                  title="Marcar como consumido"
                  onClick={() => alert('TODO: registrar consumo')}
                >
                  ✓
                </button>
              ) : (
                <button
                  className="text-xs px-2 py-1 rounded-lg bg-[var(--color-brand-pale)] text-[var(--color-brand)] font-medium"
                  onClick={() => alert('TODO: agregar plato a demanda')}
                >
                  + Plato
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {/* FAB: agregar plato a demanda */}
      <button
        className="fixed bottom-20 right-4 w-12 h-12 rounded-full bg-[var(--color-brand)] text-white shadow-lg text-xl flex items-center justify-center hover:opacity-90 transition"
        onClick={() => alert('TODO: modal plato a demanda')}
        title="Agregar plato a demanda"
      >
        +
      </button>
    </div>
  )
}
