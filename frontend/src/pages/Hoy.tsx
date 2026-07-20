import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useFamilyStore } from '../store/familyStore'
import { toast } from '../components/ui/Toast'
import type { DishAssignment, MealSlot, Recipe } from '../types/database'

interface SlotWithDish {
  slot:       MealSlot
  recipe:     Recipe | null
  assignment: DishAssignment | null
  consumed:   boolean
}

const HOY_LABEL = new Intl.DateTimeFormat('es-PE', {
  weekday: 'long', day: 'numeric', month: 'long',
})

export default function Hoy() {
  const { currentFamily } = useFamilyStore()
  const [slots,   setSlots]   = useState<SlotWithDish[]>([])
  const [loading, setLoading] = useState(true)
  const [consuming, setConsuming] = useState<string | null>(null)

  const today = new Date().toISOString().slice(0, 10)

  useEffect(() => {
    if (!currentFamily) { setLoading(false); return }
    load()
  }, [currentFamily])

  async function load() {
    setLoading(true)

    const { data: rawSlots } = await supabase
      .from('meal_slots').select('*')
      .eq('family_id', currentFamily!.id).order('sort_order')
    const mealSlots = (rawSlots ?? []) as MealSlot[]

    const { data: rawPlans } = await supabase
      .from('weekly_plans').select('id, week_start_date')
      .eq('family_id', currentFamily!.id)
      .in('status', ['planned', 'active'])
    const plans = (rawPlans ?? []) as { id: string; week_start_date: string }[]
    const planIds = plans.map(p => p.id)

    const assignBySlot: Record<string, { recipe: Recipe; assignment: DishAssignment }> = {}

    if (planIds.length > 0) {
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
          const d = new Date(weekStart)
          d.setDate(d.getDate() + offset)
          if (d.toISOString().slice(0, 10) === today && mealSlotId) {
            assignBySlot[mealSlotId] = { recipe, assignment: a as unknown as DishAssignment }
          }
        }
      })
    }

    const { data: rawAdhoc } = await supabase
      .from('dish_assignments').select('*, recipes(*)')
      .eq('family_id', currentFamily!.id)
      .eq('is_adhoc', true).eq('adhoc_date', today)
    ;(rawAdhoc ?? []).forEach((a: any) => {
      if (a.adhoc_meal_slot_id && a.recipes) {
        assignBySlot[a.adhoc_meal_slot_id] = { recipe: a.recipes, assignment: a }
      }
    })

    // Consumos de hoy
    const { data: rawLogs } = await supabase
      .from('consumption_logs').select('meal_slot_id')
      .eq('family_id', currentFamily!.id)
      .eq('consumed_date', today)
    const consumedSlots = new Set((rawLogs ?? []).map((l: any) => l.meal_slot_id))

    setSlots(mealSlots.map(slot => ({
      slot,
      recipe:     assignBySlot[slot.id]?.recipe     ?? null,
      assignment: assignBySlot[slot.id]?.assignment ?? null,
      consumed:   consumedSlots.has(slot.id),
    })))
    setLoading(false)
  }

  async function markConsumed(slotWithDish: SlotWithDish) {
    if (!currentFamily || consuming) return
    const { slot, recipe, consumed } = slotWithDish

    if (consumed) {
      // Desmarcar
      await supabase.from('consumption_logs').delete()
        .eq('family_id', currentFamily.id)
        .eq('meal_slot_id', slot.id)
        .eq('consumed_date', today)
      setSlots(prev => prev.map(s =>
        s.slot.id === slot.id ? { ...s, consumed: false } : s
      ))
      toast.info(`${slot.name} desmarcado`)
      return
    }

    setConsuming(slot.id)
    const { error } = await supabase.from('consumption_logs').insert({
      family_id:     currentFamily.id,
      meal_slot_id:  slot.id,
      recipe_id:     slotWithDish.assignment?.recipe_id ?? null,
      consumed_date: today,
      notes:         null,
    })
    setConsuming(null)

    if (error) {
      toast.err('Error al registrar consumo')
    } else {
      setSlots(prev => prev.map(s =>
        s.slot.id === slot.id ? { ...s, consumed: true } : s
      ))
      toast.ok(`${recipe?.name ?? slot.name} registrado ✓`)
    }
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
          {slots.map((item) => (
            <div
              key={item.slot.id}
              className={`flex items-center gap-3 p-4 rounded-xl border bg-white shadow-sm transition-colors ${
                item.consumed ? 'border-green-200 bg-green-50' : 'border-gray-100'
              }`}
            >
              <div className="flex-1 min-w-0">
                <p className={`text-xs font-medium uppercase tracking-wide ${
                  item.consumed ? 'text-green-500' : 'text-gray-400'
                }`}>
                  {item.slot.name}
                  {item.slot.default_time && (
                    <span className="ml-1 normal-case">· {item.slot.default_time.slice(0, 5)}</span>
                  )}
                </p>
                {item.recipe ? (
                  <p className={`font-semibold truncate ${item.consumed ? 'text-green-700 line-through' : 'text-gray-800'}`}>
                    {item.recipe.name}
                  </p>
                ) : (
                  <p className="text-gray-400 italic text-sm">Sin plato asignado</p>
                )}
              </div>

              {item.recipe ? (
                <button
                  disabled={consuming === item.slot.id}
                  onClick={() => markConsumed(item)}
                  className={`w-9 h-9 rounded-full border-2 flex items-center justify-center transition-colors shrink-0 ${
                    item.consumed
                      ? 'border-green-500 bg-green-500 text-white'
                      : 'border-[var(--color-brand)] text-[var(--color-brand)] hover:bg-[var(--color-brand-pale)]'
                  } ${consuming === item.slot.id ? 'opacity-50' : ''}`}
                  title={item.consumed ? 'Desmarcar' : 'Marcar como consumido'}
                >
                  ✓
                </button>
              ) : (
                <button
                  className="text-xs px-2 py-1 rounded-lg bg-[var(--color-brand-pale)] text-[var(--color-brand)] font-medium"
                  onClick={() => toast.info('Próximamente: agregar plato a demanda')}
                >
                  + Plato
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      <button
        className="fixed bottom-20 right-4 w-12 h-12 rounded-full bg-[var(--color-brand)] text-white shadow-lg text-xl flex items-center justify-center hover:opacity-90 transition"
        onClick={() => toast.info('Próximamente: agregar plato a demanda')}
        title="Agregar plato a demanda"
      >
        +
      </button>
    </div>
  )
}
