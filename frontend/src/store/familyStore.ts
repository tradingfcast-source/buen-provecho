import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import { supabase } from '../lib/supabase'
import type { Family, FamilyMember, WeeklyPlan } from '../types/database'

interface FamilyState {
  currentFamily:  Family | null
  members:        FamilyMember[]
  activePlan:     WeeklyPlan | null

  setFamily:     (family: Family) => void
  setMembers:    (members: FamilyMember[]) => void
  setActivePlan: (plan: WeeklyPlan | null) => void
  loadFamily:    () => Promise<void>
  reset:         () => void
}

export const useFamilyStore = create<FamilyState>()(
  persist(
    (set) => ({
      currentFamily: null,
      members:       [],
      activePlan:    null,

      setFamily:     (family)  => set({ currentFamily: family }),
      setMembers:    (members) => set({ members }),
      setActivePlan: (plan)    => set({ activePlan: plan }),
      reset:         ()        => set({ currentFamily: null, members: [], activePlan: null }),

      loadFamily: async () => {
        // 1. Primera membresía del usuario autenticado
        const { data: membership } = await supabase
          .from('family_members')
          .select('family_id')
          .limit(1)
          .maybeSingle()

        if (!membership) return

        const familyId = membership.family_id

        // 2. Datos de la familia, miembros y plan activo en paralelo
        const [familyRes, membersRes, plansRes] = await Promise.all([
          supabase.from('families').select('*').eq('id', familyId).single(),
          supabase.from('family_members').select('*').eq('family_id', familyId).order('created_at'),
          supabase.from('weekly_plans').select('*')
            .eq('family_id', familyId)
            .in('status', ['active', 'planned'])
            .order('week_start_date', { ascending: false })
            .limit(1),
        ])

        if (familyRes.data) set({ currentFamily: familyRes.data as Family })
        if (membersRes.data) set({ members: membersRes.data as FamilyMember[] })
        set({ activePlan: ((plansRes.data ?? [])[0] ?? null) as WeeklyPlan | null })
      },
    }),
    { name: 'bp-family' },
  ),
)
