-- =============================================================
-- Buen Provecho — Migración 002: Row Level Security
-- =============================================================
-- IMPORTANTE: Las funciones helper usan SECURITY DEFINER para
-- consultar family_members sin activar RLS recursivo.
-- =============================================================


-- =============================================================
-- FUNCIONES HELPER (SECURITY DEFINER bypass RLS)
-- =============================================================

-- Devuelve los IDs de familia a las que pertenece el usuario actual.
CREATE OR REPLACE FUNCTION get_user_family_ids()
RETURNS UUID[]
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(ARRAY_AGG(DISTINCT family_id), '{}')
  FROM public.family_members
  WHERE user_id = auth.uid();
$$;

-- Devuelve el rol del usuario en una familia específica. NULL si no es miembro.
CREATE OR REPLACE FUNCTION get_family_role(p_family_id UUID)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role
  FROM public.family_members
  WHERE family_id = p_family_id
    AND user_id = auth.uid()
  LIMIT 1;
$$;

-- Verifica si el usuario actual es miembro de la familia dada.
CREATE OR REPLACE FUNCTION is_family_member(p_family_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.family_members
    WHERE family_id = p_family_id AND user_id = auth.uid()
  );
$$;


-- =============================================================
-- ACTIVAR RLS EN TODAS LAS TABLAS
-- =============================================================

ALTER TABLE profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE families             ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_members       ENABLE ROW LEVEL SECURITY;
ALTER TABLE member_body_data     ENABLE ROW LEVEL SECURITY;
ALTER TABLE dietary_patterns     ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_restrictions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_slots           ENABLE ROW LEVEL SECURITY;
ALTER TABLE dish_slots           ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_rules     ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingredients          ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingredient_country_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipes              ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipe_ingredients   ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_ingredient_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE weekly_plans         ENABLE ROW LEVEL SECURITY;
ALTER TABLE dish_assignments     ENABLE ROW LEVEL SECURITY;
ALTER TABLE vote_polls           ENABLE ROW LEVEL SECURITY;
ALTER TABLE vote_options         ENABLE ROW LEVEL SECURITY;
ALTER TABLE votes                ENABLE ROW LEVEL SECURITY;
ALTER TABLE consumption_log      ENABLE ROW LEVEL SECURITY;
ALTER TABLE pantry_inventory     ENABLE ROW LEVEL SECURITY;
ALTER TABLE shopping_lists       ENABLE ROW LEVEL SECURITY;
ALTER TABLE shopping_list_items  ENABLE ROW LEVEL SECURITY;


-- =============================================================
-- POLÍTICAS: profiles
-- =============================================================

CREATE POLICY "profiles_own_read"   ON profiles FOR SELECT  USING (id = auth.uid());
CREATE POLICY "profiles_own_insert" ON profiles FOR INSERT  WITH CHECK (id = auth.uid());
CREATE POLICY "profiles_own_update" ON profiles FOR UPDATE  USING (id = auth.uid());
CREATE POLICY "profiles_own_delete" ON profiles FOR DELETE  USING (id = auth.uid());


-- =============================================================
-- POLÍTICAS: families
-- =============================================================

-- Leer: solo miembros de la familia
CREATE POLICY "families_member_read" ON families
  FOR SELECT USING (id = ANY(get_user_family_ids()));

-- Crear: cualquier usuario autenticado puede crear una familia
CREATE POLICY "families_auth_insert" ON families
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Actualizar: solo el owner
CREATE POLICY "families_owner_update" ON families
  FOR UPDATE USING (get_family_role(id) = 'owner');

-- Eliminar: solo el owner (cascade borra todo el tenant)
CREATE POLICY "families_owner_delete" ON families
  FOR DELETE USING (get_family_role(id) = 'owner');


-- =============================================================
-- POLÍTICAS: family_members
-- =============================================================

-- Leer: miembros de la misma familia. Usa ARRAY para evitar recursión.
CREATE POLICY "fm_member_read" ON family_members
  FOR SELECT USING (family_id = ANY(get_user_family_ids()));

-- Insertar: solo el owner puede agregar miembros
CREATE POLICY "fm_owner_insert" ON family_members
  FOR INSERT WITH CHECK (get_family_role(family_id) = 'owner');

-- Actualizar: el owner o el propio miembro (su propia fila)
CREATE POLICY "fm_owner_or_self_update" ON family_members
  FOR UPDATE USING (
    get_family_role(family_id) = 'owner'
    OR user_id = auth.uid()
  );

-- Eliminar: solo el owner
CREATE POLICY "fm_owner_delete" ON family_members
  FOR DELETE USING (get_family_role(family_id) = 'owner');


-- =============================================================
-- POLÍTICAS: member_body_data (PRIVACIDAD ESTRICTA)
-- Solo el propio usuario o el owner de la familia pueden acceder.
-- =============================================================

CREATE POLICY "body_data_restricted" ON member_body_data
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.id = member_body_data.family_member_id
        AND fm.user_id = auth.uid()
    )
    OR get_family_role(family_id) = 'owner'
  );


-- =============================================================
-- POLÍTICAS GENÉRICAS PARA TABLAS SCOPED A FAMILIA
-- Patrón reutilizable: leer si es miembro, escribir según rol.
-- =============================================================

-- dietary_patterns
CREATE POLICY "dp_member_read"    ON dietary_patterns FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "dp_owner_write"    ON dietary_patterns FOR INSERT  WITH CHECK (get_family_role(family_id) = 'owner');
CREATE POLICY "dp_owner_update"   ON dietary_patterns FOR UPDATE  USING (get_family_role(family_id) = 'owner');
CREATE POLICY "dp_owner_delete"   ON dietary_patterns FOR DELETE  USING (get_family_role(family_id) = 'owner');

-- food_restrictions
CREATE POLICY "fr_member_read"    ON food_restrictions FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "fr_owner_write"    ON food_restrictions FOR INSERT  WITH CHECK (get_family_role(family_id) = 'owner');
CREATE POLICY "fr_owner_update"   ON food_restrictions FOR UPDATE  USING (get_family_role(family_id) = 'owner');
CREATE POLICY "fr_owner_delete"   ON food_restrictions FOR DELETE  USING (get_family_role(family_id) = 'owner');

-- meal_slots
CREATE POLICY "ms_member_read"    ON meal_slots FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "ms_owner_write"    ON meal_slots FOR INSERT  WITH CHECK (get_family_role(family_id) = 'owner');
CREATE POLICY "ms_owner_update"   ON meal_slots FOR UPDATE  USING (get_family_role(family_id) = 'owner');
CREATE POLICY "ms_owner_delete"   ON meal_slots FOR DELETE  USING (get_family_role(family_id) = 'owner');

-- dish_slots
CREATE POLICY "ds_member_read"    ON dish_slots FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "ds_owner_write"    ON dish_slots FOR INSERT  WITH CHECK (get_family_role(family_id) = 'owner');
CREATE POLICY "ds_owner_update"   ON dish_slots FOR UPDATE  USING (get_family_role(family_id) = 'owner');
CREATE POLICY "ds_owner_delete"   ON dish_slots FOR DELETE  USING (get_family_role(family_id) = 'owner');

-- attendance_rules
CREATE POLICY "ar_member_read"    ON attendance_rules FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "ar_owner_write"    ON attendance_rules FOR INSERT  WITH CHECK (get_family_role(family_id) = 'owner');
CREATE POLICY "ar_owner_update"   ON attendance_rules FOR UPDATE  USING (get_family_role(family_id) = 'owner');
CREATE POLICY "ar_owner_delete"   ON attendance_rules FOR DELETE  USING (get_family_role(family_id) = 'owner');

-- attendance_overrides (cualquier miembro puede registrar su propia excepción)
CREATE POLICY "ao_member_read"    ON attendance_overrides FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "ao_member_insert"  ON attendance_overrides FOR INSERT  WITH CHECK (family_id = ANY(get_user_family_ids()));
CREATE POLICY "ao_member_update"  ON attendance_overrides FOR UPDATE  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "ao_owner_delete"   ON attendance_overrides FOR DELETE  USING (get_family_role(family_id) = 'owner');


-- =============================================================
-- POLÍTICAS: ingredients (catálogo global + privado)
-- =============================================================

-- Global (family_id NULL) es visible para todos los autenticados.
-- Privado (family_id NOT NULL) solo para miembros de esa familia.
CREATE POLICY "ing_read" ON ingredients
  FOR SELECT USING (
    family_id IS NULL
    OR family_id = ANY(get_user_family_ids())
  );

CREATE POLICY "ing_family_insert" ON ingredients
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL
    AND (family_id IS NULL OR get_family_role(family_id) IN ('owner', 'adult'))
  );

CREATE POLICY "ing_family_update" ON ingredients
  FOR UPDATE USING (
    family_id IS NOT NULL AND get_family_role(family_id) IN ('owner', 'adult')
  );

CREATE POLICY "ing_family_delete" ON ingredients
  FOR DELETE USING (
    family_id IS NOT NULL AND get_family_role(family_id) = 'owner'
  );

-- ingredient_country_map: hereda visibilidad del ingrediente
CREATE POLICY "icm_read" ON ingredient_country_map
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM ingredients i
      WHERE i.id = ingredient_country_map.ingredient_id
        AND (i.family_id IS NULL OR i.family_id = ANY(get_user_family_ids()))
    )
  );

CREATE POLICY "icm_auth_write" ON ingredient_country_map
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "icm_auth_update" ON ingredient_country_map
  FOR UPDATE USING (auth.uid() IS NOT NULL);


-- =============================================================
-- POLÍTICAS: recipes
-- =============================================================

CREATE POLICY "rec_read" ON recipes
  FOR SELECT USING (
    is_public = TRUE
    OR family_id IS NULL
    OR family_id = ANY(get_user_family_ids())
  );

CREATE POLICY "rec_member_insert" ON recipes
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL
    AND (family_id IS NULL OR family_id = ANY(get_user_family_ids()))
  );

CREATE POLICY "rec_creator_update" ON recipes
  FOR UPDATE USING (
    created_by = auth.uid()
    OR get_family_role(family_id) = 'owner'
  );

CREATE POLICY "rec_creator_delete" ON recipes
  FOR DELETE USING (
    created_by = auth.uid()
    OR get_family_role(family_id) = 'owner'
  );

-- recipe_ingredients: hereda visibilidad de la receta
CREATE POLICY "ri_read" ON recipe_ingredients
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM recipes r
      WHERE r.id = recipe_ingredients.recipe_id
        AND (r.is_public OR r.family_id IS NULL OR r.family_id = ANY(get_user_family_ids()))
    )
  );

CREATE POLICY "ri_member_write" ON recipe_ingredients
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM recipes r
      WHERE r.id = recipe_ingredients.recipe_id
        AND (r.created_by = auth.uid() OR get_family_role(r.family_id) = 'owner')
    )
  );

-- family_ingredient_prices
CREATE POLICY "fip_member_read"   ON family_ingredient_prices FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "fip_member_insert" ON family_ingredient_prices FOR INSERT  WITH CHECK (family_id = ANY(get_user_family_ids()));
CREATE POLICY "fip_owner_delete"  ON family_ingredient_prices FOR DELETE  USING (get_family_role(family_id) = 'owner');


-- =============================================================
-- POLÍTICAS: planes, asignaciones, votaciones
-- =============================================================

-- weekly_plans
CREATE POLICY "wp_member_read"   ON weekly_plans FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "wp_member_insert" ON weekly_plans FOR INSERT  WITH CHECK (family_id = ANY(get_user_family_ids()));
CREATE POLICY "wp_member_update" ON weekly_plans FOR UPDATE  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "wp_owner_delete"  ON weekly_plans FOR DELETE  USING (get_family_role(family_id) = 'owner');

-- dish_assignments
CREATE POLICY "da_member_read"   ON dish_assignments FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "da_member_insert" ON dish_assignments FOR INSERT  WITH CHECK (family_id = ANY(get_user_family_ids()));
CREATE POLICY "da_member_update" ON dish_assignments FOR UPDATE  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "da_member_delete" ON dish_assignments FOR DELETE  USING (family_id = ANY(get_user_family_ids()));

-- vote_polls
CREATE POLICY "vp_member_read"   ON vote_polls FOR SELECT  USING (
  EXISTS (SELECT 1 FROM weekly_plans wp WHERE wp.id = vote_polls.weekly_plan_id AND wp.family_id = ANY(get_user_family_ids()))
);
CREATE POLICY "vp_member_insert" ON vote_polls FOR INSERT  WITH CHECK (
  EXISTS (SELECT 1 FROM weekly_plans wp WHERE wp.id = vote_polls.weekly_plan_id AND wp.family_id = ANY(get_user_family_ids()))
);

-- vote_options
CREATE POLICY "vo_member_read"   ON vote_options FOR SELECT  USING (
  EXISTS (SELECT 1 FROM vote_polls vp JOIN weekly_plans wp ON wp.id = vp.weekly_plan_id
          WHERE vp.id = vote_options.poll_id AND wp.family_id = ANY(get_user_family_ids()))
);
CREATE POLICY "vo_member_insert" ON vote_options FOR INSERT  WITH CHECK (
  EXISTS (SELECT 1 FROM vote_polls vp JOIN weekly_plans wp ON wp.id = vp.weekly_plan_id
          WHERE vp.id = vote_options.poll_id AND wp.family_id = ANY(get_user_family_ids()))
);

-- votes
CREATE POLICY "votes_member_read"   ON votes FOR SELECT  USING (
  EXISTS (SELECT 1 FROM vote_polls vp JOIN weekly_plans wp ON wp.id = vp.weekly_plan_id
          WHERE vp.id = votes.poll_id AND wp.family_id = ANY(get_user_family_ids()))
);
CREATE POLICY "votes_member_insert" ON votes FOR INSERT  WITH CHECK (
  EXISTS (SELECT 1 FROM vote_polls vp JOIN weekly_plans wp ON wp.id = vp.weekly_plan_id
          WHERE vp.id = votes.poll_id AND wp.family_id = ANY(get_user_family_ids()))
);

-- consumption_log
CREATE POLICY "cl_member_read"   ON consumption_log FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "cl_member_insert" ON consumption_log FOR INSERT  WITH CHECK (family_id = ANY(get_user_family_ids()));
CREATE POLICY "cl_member_update" ON consumption_log FOR UPDATE  USING (family_id = ANY(get_user_family_ids()));

-- pantry_inventory
CREATE POLICY "pi_member_read"   ON pantry_inventory FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "pi_member_insert" ON pantry_inventory FOR INSERT  WITH CHECK (family_id = ANY(get_user_family_ids()));
CREATE POLICY "pi_member_update" ON pantry_inventory FOR UPDATE  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "pi_owner_delete"  ON pantry_inventory FOR DELETE  USING (get_family_role(family_id) = 'owner');

-- shopping_lists
CREATE POLICY "sl_member_read"   ON shopping_lists FOR SELECT  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "sl_member_insert" ON shopping_lists FOR INSERT  WITH CHECK (family_id = ANY(get_user_family_ids()));
CREATE POLICY "sl_member_update" ON shopping_lists FOR UPDATE  USING (family_id = ANY(get_user_family_ids()));
CREATE POLICY "sl_owner_delete"  ON shopping_lists FOR DELETE  USING (get_family_role(family_id) = 'owner');

-- shopping_list_items (hereda familia de su shopping_list)
CREATE POLICY "sli_member_read" ON shopping_list_items FOR SELECT USING (
  EXISTS (SELECT 1 FROM shopping_lists sl WHERE sl.id = shopping_list_items.shopping_list_id
          AND sl.family_id = ANY(get_user_family_ids()))
);
CREATE POLICY "sli_member_insert" ON shopping_list_items FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM shopping_lists sl WHERE sl.id = shopping_list_items.shopping_list_id
          AND sl.family_id = ANY(get_user_family_ids()))
);
CREATE POLICY "sli_member_update" ON shopping_list_items FOR UPDATE USING (
  EXISTS (SELECT 1 FROM shopping_lists sl WHERE sl.id = shopping_list_items.shopping_list_id
          AND sl.family_id = ANY(get_user_family_ids()))
);
