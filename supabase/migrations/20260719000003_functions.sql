-- =============================================================
-- Buen Provecho — Migración 003: Funciones de Lógica de Negocio
-- =============================================================


-- =============================================================
-- get_attending_members(family_id, meal_slot_id, date)
-- Devuelve los IDs de miembros presentes en una comida en una
-- fecha específica, aplicando reglas de asistencia y overrides.
--
-- Lógica de presencia por rol:
--   owner / adult / member  →  presentes por defecto (a menos que override diga ausente)
--   support_staff / guest   →  ausentes por defecto (requieren regla explícita)
-- Los attendance_overrides tienen prioridad absoluta sobre reglas.
-- =============================================================

CREATE OR REPLACE FUNCTION get_attending_members(
  p_family_id    UUID,
  p_meal_slot_id UUID,
  p_date         DATE
)
RETURNS TABLE (family_member_id UUID)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT fm.id
  FROM family_members fm
  WHERE fm.family_id = p_family_id
    AND (
      -- Override presente: siempre incluir
      EXISTS (
        SELECT 1 FROM attendance_overrides ao
        WHERE ao.family_member_id = fm.id
          AND ao.meal_slot_id     = p_meal_slot_id
          AND ao.override_date    = p_date
          AND ao.is_present       = TRUE
      )
      OR (
        -- Sin override para esta fecha+comida
        NOT EXISTS (
          SELECT 1 FROM attendance_overrides ao
          WHERE ao.family_member_id = fm.id
            AND ao.meal_slot_id     = p_meal_slot_id
            AND ao.override_date    = p_date
        )
        AND (
          -- Miembros regulares: presentes por defecto
          (fm.role IN ('owner', 'adult', 'member'))
          OR
          -- Personal y visitantes: presentes solo si hay regla explícita para ese DOW
          (fm.role IN ('support_staff', 'guest') AND EXISTS (
            SELECT 1 FROM attendance_rules ar
            WHERE ar.family_member_id = fm.id
              AND ar.meal_slot_id     = p_meal_slot_id
              AND EXTRACT(DOW FROM p_date)::SMALLINT = ANY(ar.week_days)
          ))
        )
      )
    );
$$;


-- =============================================================
-- compute_portions(recipe_id, family_member_id)
-- Calcula la cantidad de cada ingrediente para un miembro
-- aplicando: portion_factor × portion_multiplier × carb_multiplier (si aplica).
-- Algoritmo: §4.1 del ARCHITECTURE.md
-- =============================================================

CREATE OR REPLACE FUNCTION compute_portions(
  p_recipe_id        UUID,
  p_family_member_id UUID
)
RETURNS TABLE (
  ingredient_id        UUID,
  ingredient_name      TEXT,
  tags                 TEXT[],
  quantity             NUMERIC,
  unit                 TEXT,
  is_optional          BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_portion_factor    NUMERIC;
  v_carb_mult         NUMERIC;
  v_portion_mult      NUMERIC;
BEGIN
  -- Factor base del miembro
  SELECT fm.portion_factor
  INTO   v_portion_factor
  FROM   family_members fm
  WHERE  fm.id = p_family_member_id;

  -- Patrón dietético activo (el más reciente)
  SELECT
    COALESCE(dp.carb_multiplier,    1.0),
    COALESCE(dp.portion_multiplier, 1.0)
  INTO v_carb_mult, v_portion_mult
  FROM dietary_patterns dp
  WHERE dp.family_member_id = p_family_member_id
    AND dp.active = TRUE
  ORDER BY dp.created_at DESC
  LIMIT 1;

  v_carb_mult    := COALESCE(v_carb_mult,    1.0);
  v_portion_mult := COALESCE(v_portion_mult, 1.0);

  RETURN QUERY
  SELECT
    i.id                                                           AS ingredient_id,
    i.name                                                         AS ingredient_name,
    i.tags,
    ROUND(
      ri.quantity_per_portion
      * v_portion_factor
      * v_portion_mult
      * CASE WHEN 'carb' = ANY(i.tags) THEN v_carb_mult ELSE 1.0 END,
      3
    )                                                              AS quantity,
    ri.unit,
    ri.is_optional
  FROM recipe_ingredients ri
  JOIN ingredients i ON i.id = ri.ingredient_id
  WHERE ri.recipe_id = p_recipe_id;
END;
$$;


-- =============================================================
-- compute_shopping_list(weekly_plan_id, deduction_mode)
-- Motor principal de generación de lista de compras.
-- Algoritmo completo: §4.2 del ARCHITECTURE.md
--
-- Pasos:
--   1. Expande bloques regulares y platos a demanda en fechas concretas.
--   2. Determina asistentes por fecha y comida.
--   3. Calcula porciones individuales (con multiplicadores).
--   4. Consolida por ingrediente.
--   5. Aplica localización/sustitución según país de la familia.
--   6. Descuenta inventario de despensa (según deduction_mode).
--   7. Redondea a unidades comerciales.
--   8. Valoriza con el último precio registrado.
-- =============================================================

CREATE OR REPLACE FUNCTION compute_shopping_list(
  p_weekly_plan_id UUID,
  p_deduction_mode TEXT DEFAULT 'net'
)
RETURNS TABLE (
  ingredient_id         UUID,
  display_ingredient_id UUID,
  display_name          TEXT,
  original_name         TEXT,
  quantity_required     NUMERIC,
  quantity_in_pantry    NUMERIC,
  quantity_net          NUMERIC,
  quantity_to_buy       NUMERIC,
  unit                  TEXT,
  estimated_cost        NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_family_id       UUID;
  v_country_code    CHAR(2);
  v_week_start_date DATE;
BEGIN
  -- Metadatos del plan y la familia
  SELECT wp.family_id, f.country_code, wp.week_start_date
  INTO   v_family_id, v_country_code, v_week_start_date
  FROM   weekly_plans wp
  JOIN   families f ON f.id = wp.family_id
  WHERE  wp.id = p_weekly_plan_id;

  RETURN QUERY
  WITH

  -- ─────────────────────────────────────────────────────────
  -- PASO 1: Expandir asignaciones a tuplas (recipe_id, date, meal_slot_id)
  -- ─────────────────────────────────────────────────────────
  assignment_dates AS (
    -- Bloques regulares: expand day_offsets en fechas reales
    SELECT
      da.recipe_id,
      (v_week_start_date + offset_val::INTEGER)::DATE AS dish_date,
      ds.meal_slot_id
    FROM dish_assignments da
    JOIN dish_slots ds ON ds.id = da.dish_slot_id
    CROSS JOIN LATERAL UNNEST(ds.day_offsets) AS offset_val
    WHERE da.weekly_plan_id = p_weekly_plan_id
      AND da.is_adhoc = FALSE

    UNION ALL

    -- Platos a demanda: fecha y comida explícitas
    SELECT
      da.recipe_id,
      da.adhoc_date           AS dish_date,
      da.adhoc_meal_slot_id   AS meal_slot_id
    FROM dish_assignments da
    WHERE da.weekly_plan_id = p_weekly_plan_id
      AND da.is_adhoc = TRUE
  ),

  -- ─────────────────────────────────────────────────────────
  -- PASO 2: Cruzar con asistentes por fecha y comida
  -- ─────────────────────────────────────────────────────────
  assignment_members AS (
    SELECT
      ad.recipe_id,
      ad.dish_date,
      ad.meal_slot_id,
      gam.family_member_id
    FROM assignment_dates ad
    CROSS JOIN LATERAL get_attending_members(v_family_id, ad.meal_slot_id, ad.dish_date) AS gam(family_member_id)
  ),

  -- ─────────────────────────────────────────────────────────
  -- PASO 3: Calcular porciones individuales por ingrediente
  -- ─────────────────────────────────────────────────────────
  raw_portions AS (
    SELECT
      ri.ingredient_id,
      ri.unit,
      SUM(
        ri.quantity_per_portion
        * fm.portion_factor
        * COALESCE(dp.portion_multiplier, 1.0)
        * CASE WHEN 'carb' = ANY(i.tags) THEN COALESCE(dp.carb_multiplier, 1.0) ELSE 1.0 END
      ) AS total_quantity
    FROM assignment_members am
    JOIN recipe_ingredients ri ON ri.recipe_id = am.recipe_id
    JOIN ingredients i         ON i.id          = ri.ingredient_id
    JOIN family_members fm     ON fm.id          = am.family_member_id
    LEFT JOIN LATERAL (
      SELECT dp2.carb_multiplier, dp2.portion_multiplier
      FROM dietary_patterns dp2
      WHERE dp2.family_member_id = am.family_member_id
        AND dp2.active = TRUE
      ORDER BY dp2.created_at DESC
      LIMIT 1
    ) dp ON TRUE
    GROUP BY ri.ingredient_id, ri.unit
  ),

  -- ─────────────────────────────────────────────────────────
  -- PASO 4 & 5: Localización y sustitución por país
  -- Si requires_substitution=TRUE: reemplazar ingrediente y
  -- multiplicar cantidad × conversion_factor.
  -- Si FALSE: solo traducir el nombre para mostrar.
  -- ─────────────────────────────────────────────────────────
  localized AS (
    SELECT
      rp.ingredient_id                                                    AS orig_ingredient_id,
      COALESCE(
        CASE WHEN icm.requires_substitution THEN icm.substitute_ingredient_id END,
        rp.ingredient_id
      )                                                                   AS resolved_ingredient_id,
      COALESCE(icm.local_name, i.name)                                   AS resolved_name,
      i.name                                                              AS orig_name,
      CASE
        WHEN icm.requires_substitution AND icm.substitute_ingredient_id IS NOT NULL
        THEN ROUND(rp.total_quantity * icm.conversion_factor, 3)
        ELSE rp.total_quantity
      END                                                                 AS resolved_quantity,
      rp.unit
    FROM raw_portions rp
    JOIN ingredients i ON i.id = rp.ingredient_id
    LEFT JOIN ingredient_country_map icm
      ON  icm.ingredient_id = rp.ingredient_id
      AND icm.country_code  = v_country_code
  ),

  -- Re-agregar en caso de que múltiples ingredientes se sustituyan por el mismo
  consolidated AS (
    SELECT
      orig_ingredient_id,
      resolved_ingredient_id,
      resolved_name,
      orig_name,
      SUM(resolved_quantity) AS quantity_required,
      unit
    FROM localized
    GROUP BY orig_ingredient_id, resolved_ingredient_id, resolved_name, orig_name, unit
  ),

  -- ─────────────────────────────────────────────────────────
  -- PASO 6: Descuento de despensa
  -- ─────────────────────────────────────────────────────────
  with_pantry AS (
    SELECT
      c.orig_ingredient_id          AS ingredient_id,
      c.resolved_ingredient_id      AS display_ingredient_id,
      c.resolved_name               AS display_name,
      c.orig_name,
      ROUND(c.quantity_required, 3) AS quantity_required,
      COALESCE(pi.quantity, 0)      AS quantity_in_pantry,
      CASE p_deduction_mode
        WHEN 'net'          THEN GREATEST(ROUND(c.quantity_required - COALESCE(pi.quantity, 0), 3), 0)
        WHEN 'verify_only'  THEN ROUND(c.quantity_required, 3)   -- muestra requerido, marca stock
        ELSE                     ROUND(c.quantity_required, 3)   -- 'none': sin descuento
      END                           AS quantity_net,
      c.unit
    FROM consolidated c
    LEFT JOIN pantry_inventory pi
      ON  pi.ingredient_id = c.resolved_ingredient_id
      AND pi.family_id     = v_family_id
  ),

  -- ─────────────────────────────────────────────────────────
  -- PASO 7 & 8: Redondeo comercial y valorización
  -- Redondear hacia arriba al múltiplo de min_purchase_increment.
  -- ─────────────────────────────────────────────────────────
  final AS (
    SELECT
      wp2.ingredient_id,
      wp2.display_ingredient_id,
      wp2.display_name,
      wp2.orig_name                                              AS original_name,
      wp2.quantity_required,
      wp2.quantity_in_pantry,
      wp2.quantity_net,
      -- Redondeo comercial: CEIL al siguiente múltiplo de min_purchase_increment
      CEIL(wp2.quantity_net / GREATEST(i_disp.min_purchase_increment, 0.001))
        * i_disp.min_purchase_increment                          AS quantity_to_buy,
      wp2.unit,
      -- Costo estimado con el precio más reciente registrado
      CEIL(wp2.quantity_net / GREATEST(i_disp.min_purchase_increment, 0.001))
        * i_disp.min_purchase_increment
        * COALESCE(last_price.price, 0)                          AS estimated_cost
    FROM with_pantry wp2
    JOIN ingredients i_disp ON i_disp.id = wp2.display_ingredient_id
    LEFT JOIN LATERAL (
      SELECT fip.price
      FROM family_ingredient_prices fip
      WHERE fip.family_id     = v_family_id
        AND fip.ingredient_id = wp2.display_ingredient_id
      ORDER BY fip.recorded_at DESC
      LIMIT 1
    ) last_price ON TRUE
    WHERE wp2.quantity_net > 0
  )

  SELECT * FROM final
  ORDER BY original_name;

END;
$$;


-- =============================================================
-- generate_shopping_list_snapshot(weekly_plan_id, deduction_mode)
-- Materializa el resultado de compute_shopping_list en la tabla
-- shopping_list_items, creando la cabecera si no existe.
-- Devuelve el shopping_list_id creado/actualizado.
-- =============================================================

CREATE OR REPLACE FUNCTION generate_shopping_list_snapshot(
  p_weekly_plan_id UUID,
  p_deduction_mode TEXT DEFAULT 'net'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_family_id      UUID;
  v_list_id        UUID;
  v_total_cost     NUMERIC := 0;
BEGIN
  SELECT family_id INTO v_family_id
  FROM weekly_plans WHERE id = p_weekly_plan_id;

  -- Crear o reutilizar cabecera de lista para este plan
  INSERT INTO shopping_lists (family_id, weekly_plan_id, deduction_mode, status)
  VALUES (v_family_id, p_weekly_plan_id, p_deduction_mode, 'pending')
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_list_id;

  IF v_list_id IS NULL THEN
    SELECT id INTO v_list_id FROM shopping_lists
    WHERE weekly_plan_id = p_weekly_plan_id
    LIMIT 1;
  END IF;

  -- Limpiar ítems previos para regenerar
  DELETE FROM shopping_list_items WHERE shopping_list_id = v_list_id;

  -- Insertar ítems calculados
  INSERT INTO shopping_list_items (
    shopping_list_id, ingredient_id, display_ingredient_id,
    display_name, quantity_required, quantity_in_pantry,
    quantity_net, quantity_to_buy, unit, estimated_cost, status
  )
  SELECT
    v_list_id,
    ingredient_id, display_ingredient_id,
    display_name, quantity_required, quantity_in_pantry,
    quantity_net, quantity_to_buy, unit, estimated_cost,
    'pending'
  FROM compute_shopping_list(p_weekly_plan_id, p_deduction_mode);

  -- Actualizar costo total en la cabecera
  SELECT COALESCE(SUM(estimated_cost), 0)
  INTO   v_total_cost
  FROM   shopping_list_items
  WHERE  shopping_list_id = v_list_id;

  UPDATE shopping_lists
  SET total_estimated_cost = v_total_cost,
      updated_at           = NOW()
  WHERE id = v_list_id;

  RETURN v_list_id;
END;
$$;
