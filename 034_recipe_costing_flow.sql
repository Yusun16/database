-- Recipe costing flow.
-- Run after:
--   033_production_packaging_flow.sql

USE panaderia_db;

SET @recipe_items_concept_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'recipe_items'
    AND COLUMN_NAME = 'concept'
);
SET @recipe_items_concept_sql = IF(
  @recipe_items_concept_exists = 0,
  'ALTER TABLE recipe_items ADD COLUMN concept VARCHAR(60) NOT NULL DEFAULT ''MOJE'' AFTER raw_material_id',
  'SELECT 1'
);
PREPARE recipe_items_concept_stmt FROM @recipe_items_concept_sql;
EXECUTE recipe_items_concept_stmt;
DEALLOCATE PREPARE recipe_items_concept_stmt;

SET @recipe_outputs_unit_weight_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'recipe_outputs'
    AND COLUMN_NAME = 'unit_weight_grams'
);
SET @recipe_outputs_unit_weight_sql = IF(
  @recipe_outputs_unit_weight_exists = 0,
  'ALTER TABLE recipe_outputs ADD COLUMN unit_weight_grams DECIMAL(14,3) NULL AFTER expected_quantity',
  'SELECT 1'
);
PREPARE recipe_outputs_unit_weight_stmt FROM @recipe_outputs_unit_weight_sql;
EXECUTE recipe_outputs_unit_weight_stmt;
DEALLOCATE PREPARE recipe_outputs_unit_weight_stmt;

SET @recipe_outputs_sale_price_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'recipe_outputs'
    AND COLUMN_NAME = 'sale_price'
);
SET @recipe_outputs_sale_price_sql = IF(
  @recipe_outputs_sale_price_exists = 0,
  'ALTER TABLE recipe_outputs ADD COLUMN sale_price DECIMAL(14,2) NULL AFTER unit_weight_grams',
  'SELECT 1'
);
PREPARE recipe_outputs_sale_price_stmt FROM @recipe_outputs_sale_price_sql;
EXECUTE recipe_outputs_sale_price_stmt;
DEALLOCATE PREPARE recipe_outputs_sale_price_stmt;

SET @recipes_product_nullable = (
  SELECT IS_NULLABLE
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'recipes'
    AND COLUMN_NAME = 'product_id'
);
SET @recipes_product_nullable_sql = IF(
  @recipes_product_nullable = 'NO',
  'ALTER TABLE recipes MODIFY COLUMN product_id BIGINT UNSIGNED NULL',
  'SELECT 1'
);
PREPARE recipes_product_nullable_stmt FROM @recipes_product_nullable_sql;
EXECUTE recipes_product_nullable_stmt;
DEALLOCATE PREPARE recipes_product_nullable_stmt;

CREATE TABLE IF NOT EXISTS recipe_output_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  recipe_output_id BIGINT UNSIGNED NOT NULL,
  concept VARCHAR(60) NOT NULL DEFAULT 'MOJE',
  raw_material_id BIGINT UNSIGNED NOT NULL,
  quantity DECIMAL(14,4) NOT NULL,
  wastage_percent DECIMAL(5,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_recipe_output_items_material_concept (recipe_output_id, raw_material_id, concept),
  KEY idx_recipe_output_items_material (raw_material_id),
  CONSTRAINT fk_recipe_output_items_output
    FOREIGN KEY (recipe_output_id) REFERENCES recipe_outputs (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_recipe_output_items_material
    FOREIGN KEY (raw_material_id) REFERENCES raw_materials (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_recipe_output_items_quantity CHECK (quantity > 0),
  CONSTRAINT chk_recipe_output_items_wastage CHECK (wastage_percent >= 0 AND wastage_percent <= 100)
) ENGINE=InnoDB;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_recipe_costing_create $$
CREATE PROCEDURE sp_recipe_costing_create(
  IN p_primary_product_id BIGINT UNSIGNED,
  IN p_recipe_name VARCHAR(150),
  IN p_notes VARCHAR(255),
  IN p_base_items_json JSON,
  IN p_outputs_json JSON,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_recipe_id BIGINT UNSIGNED;
  DECLARE v_next_version INT UNSIGNED DEFAULT 1;
  DECLARE v_base_count INT DEFAULT 0;
  DECLARE v_output_count INT DEFAULT 0;
  DECLARE v_output_quantity DECIMAL(12,3) DEFAULT 1;

  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    DROP TEMPORARY TABLE IF EXISTS tmp_recipe_base_items;
    DROP TEMPORARY TABLE IF EXISTS tmp_recipe_outputs;
    DROP TEMPORARY TABLE IF EXISTS tmp_recipe_output_items;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  DROP TEMPORARY TABLE IF EXISTS tmp_recipe_base_items;
  DROP TEMPORARY TABLE IF EXISTS tmp_recipe_outputs;
  DROP TEMPORARY TABLE IF EXISTS tmp_recipe_output_items;

  CREATE TEMPORARY TABLE tmp_recipe_base_items (
    concept VARCHAR(60) NOT NULL,
    raw_material_id BIGINT UNSIGNED NOT NULL,
    quantity DECIMAL(14,4) NOT NULL,
    wastage_percent DECIMAL(5,2) NOT NULL DEFAULT 0
  ) ENGINE=Memory;

  CREATE TEMPORARY TABLE tmp_recipe_outputs (
    row_no INT UNSIGNED NOT NULL,
    product_id BIGINT UNSIGNED NOT NULL,
    expected_quantity DECIMAL(14,3) NOT NULL,
    unit_weight_grams DECIMAL(14,3) NULL,
    sale_price DECIMAL(14,2) NULL,
    packing_note VARCHAR(255) NULL,
    sort_order INT UNSIGNED NOT NULL,
    items_json JSON NULL,
    recipe_output_id BIGINT UNSIGNED NULL
  ) ENGINE=InnoDB;

  CREATE TEMPORARY TABLE tmp_recipe_output_items (
    output_row_no INT UNSIGNED NOT NULL,
    concept VARCHAR(60) NOT NULL,
    raw_material_id BIGINT UNSIGNED NOT NULL,
    quantity DECIMAL(14,4) NOT NULL,
    wastage_percent DECIMAL(5,2) NOT NULL DEFAULT 0
  ) ENGINE=Memory;

  INSERT INTO tmp_recipe_base_items (concept, raw_material_id, quantity, wastage_percent)
  SELECT
    COALESCE(NULLIF(TRIM(jt.concept), ''), 'MOJE'),
    jt.raw_material_id,
    jt.quantity,
    COALESCE(jt.wastage_percent, 0)
  FROM JSON_TABLE(
    COALESCE(p_base_items_json, JSON_ARRAY()),
    '$[*]' COLUMNS (
      concept VARCHAR(60) PATH '$.concept' NULL ON EMPTY,
      raw_material_id BIGINT UNSIGNED PATH '$.raw_material_id',
      quantity DECIMAL(14,4) PATH '$.quantity',
      wastage_percent DECIMAL(5,2) PATH '$.wastage_percent' DEFAULT '0' ON EMPTY
    )
  ) jt;

  INSERT INTO tmp_recipe_outputs (
    row_no,
    product_id,
    expected_quantity,
    unit_weight_grams,
    sale_price,
    packing_note,
    sort_order,
    items_json
  )
  SELECT
    jt.row_no,
    jt.product_id,
    jt.expected_quantity,
    jt.unit_weight_grams,
    jt.sale_price,
    jt.packing_note,
    COALESCE(jt.sort_order, jt.row_no),
    jt.items_json
  FROM JSON_TABLE(
    COALESCE(p_outputs_json, JSON_ARRAY()),
    '$[*]' COLUMNS (
      row_no FOR ORDINALITY,
      product_id BIGINT UNSIGNED PATH '$.product_id',
      expected_quantity DECIMAL(14,3) PATH '$.expected_quantity',
      unit_weight_grams DECIMAL(14,3) PATH '$.unit_weight_grams' NULL ON EMPTY,
      sale_price DECIMAL(14,2) PATH '$.sale_price' NULL ON EMPTY,
      packing_note VARCHAR(255) PATH '$.packing_note' NULL ON EMPTY,
      sort_order INT UNSIGNED PATH '$.sort_order' NULL ON EMPTY,
      items_json JSON PATH '$.items' NULL ON EMPTY
    )
  ) jt;

  INSERT INTO tmp_recipe_output_items (output_row_no, concept, raw_material_id, quantity, wastage_percent)
  SELECT
    o.row_no,
    COALESCE(NULLIF(TRIM(jt.concept), ''), 'MOJE'),
    jt.raw_material_id,
    jt.quantity,
    COALESCE(jt.wastage_percent, 0)
  FROM tmp_recipe_outputs o
  JOIN JSON_TABLE(
    COALESCE(o.items_json, JSON_ARRAY()),
    '$[*]' COLUMNS (
      concept VARCHAR(60) PATH '$.concept' NULL ON EMPTY,
      raw_material_id BIGINT UNSIGNED PATH '$.raw_material_id',
      quantity DECIMAL(14,4) PATH '$.quantity',
      wastage_percent DECIMAL(5,2) PATH '$.wastage_percent' DEFAULT '0' ON EMPTY
    )
  ) jt;

  SELECT COUNT(*) INTO v_base_count FROM tmp_recipe_base_items;
  SELECT COUNT(*) INTO v_output_count FROM tmp_recipe_outputs;

  IF v_base_count = 0 THEN
    SET o_code = 0;
    SET o_message = 'agrega al menos un ingrediente base';
    SET o_data_json = NULL;
  ELSEIF v_output_count = 0 THEN
    SET o_code = 0;
    SET o_message = 'agrega al menos un producto final';
    SET o_data_json = NULL;
  ELSEIF EXISTS (
    SELECT 1 FROM tmp_recipe_base_items
    WHERE raw_material_id IS NULL OR quantity <= 0 OR wastage_percent < 0 OR wastage_percent > 100
  ) THEN
    SET o_code = 0;
    SET o_message = 'revisa los ingredientes base';
    SET o_data_json = NULL;
  ELSEIF EXISTS (
    SELECT 1 FROM tmp_recipe_outputs
    WHERE product_id IS NULL OR expected_quantity <= 0
  ) THEN
    SET o_code = 0;
    SET o_message = 'revisa los productos finales';
    SET o_data_json = NULL;
  ELSEIF EXISTS (
    SELECT 1 FROM tmp_recipe_output_items
    WHERE raw_material_id IS NULL OR quantity <= 0 OR wastage_percent < 0 OR wastage_percent > 100
  ) THEN
    SET o_code = 0;
    SET o_message = 'revisa los ingredientes posteriores';
    SET o_data_json = NULL;
  ELSEIF p_primary_product_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM products WHERE id = p_primary_product_id AND is_active = 1 AND deleted_at IS NULL
  ) THEN
    SET o_code = 0;
    SET o_message = 'producto principal no encontrado o inactivo';
    SET o_data_json = NULL;
  ELSEIF EXISTS (
    SELECT 1
    FROM tmp_recipe_base_items t
    LEFT JOIN raw_materials rm ON rm.id = t.raw_material_id AND rm.is_active = 1 AND rm.deleted_at IS NULL
    WHERE rm.id IS NULL
  ) THEN
    SET o_code = 0;
    SET o_message = 'una materia prima base no existe o esta inactiva';
    SET o_data_json = NULL;
  ELSEIF EXISTS (
    SELECT 1
    FROM tmp_recipe_output_items t
    LEFT JOIN raw_materials rm ON rm.id = t.raw_material_id AND rm.is_active = 1 AND rm.deleted_at IS NULL
    WHERE rm.id IS NULL
  ) THEN
    SET o_code = 0;
    SET o_message = 'una materia prima posterior no existe o esta inactiva';
    SET o_data_json = NULL;
  ELSEIF EXISTS (
    SELECT 1
    FROM tmp_recipe_outputs t
    LEFT JOIN products p ON p.id = t.product_id AND p.is_active = 1 AND p.deleted_at IS NULL
    WHERE p.id IS NULL
  ) THEN
    SET o_code = 0;
    SET o_message = 'un producto final no existe o esta inactivo';
    SET o_data_json = NULL;
  ELSE
    START TRANSACTION;

    SELECT expected_quantity
      INTO v_output_quantity
    FROM tmp_recipe_outputs
    ORDER BY sort_order, row_no
    LIMIT 1;

    IF p_primary_product_id IS NULL THEN
      SET v_next_version = 1;
    ELSE
      SELECT COALESCE(MAX(version_no), 0) + 1
        INTO v_next_version
      FROM recipes
      WHERE product_id = p_primary_product_id
      FOR UPDATE;

      UPDATE recipes
      SET is_active = 0,
          updated_at = CURRENT_TIMESTAMP
      WHERE product_id = p_primary_product_id
        AND is_active = 1;
    END IF;

    INSERT INTO recipes (
      product_id,
      version_no,
      output_quantity,
      notes,
      is_active
    ) VALUES (
      p_primary_product_id,
      v_next_version,
      v_output_quantity,
      LEFT(CONCAT(COALESCE(NULLIF(TRIM(p_recipe_name), ''), 'Receta'), IF(p_notes IS NULL OR p_notes = '', '', CONCAT(' - ', p_notes))), 255),
      1
    );

    SET v_recipe_id = LAST_INSERT_ID();

    INSERT INTO recipe_items (recipe_id, raw_material_id, concept, quantity, wastage_percent)
    SELECT v_recipe_id, raw_material_id, concept, quantity, wastage_percent
    FROM tmp_recipe_base_items;

    INSERT INTO recipe_outputs (
      recipe_id,
      product_id,
      expected_quantity,
      unit_weight_grams,
      sale_price,
      packing_note,
      sort_order
    )
    SELECT
      v_recipe_id,
      product_id,
      expected_quantity,
      unit_weight_grams,
      sale_price,
      packing_note,
      sort_order
    FROM tmp_recipe_outputs
    ORDER BY sort_order, row_no;

    UPDATE tmp_recipe_outputs t
    JOIN recipe_outputs ro
      ON ro.recipe_id = v_recipe_id
     AND ro.product_id = t.product_id
    SET t.recipe_output_id = ro.id;

    INSERT INTO recipe_output_items (
      recipe_output_id,
      concept,
      raw_material_id,
      quantity,
      wastage_percent
    )
    SELECT
      o.recipe_output_id,
      i.concept,
      i.raw_material_id,
      i.quantity,
      i.wastage_percent
    FROM tmp_recipe_output_items i
    JOIN tmp_recipe_outputs o ON o.row_no = i.output_row_no;

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'recipe.costing.create',
      'recipes',
      CAST(v_recipe_id AS CHAR),
      JSON_OBJECT('primary_product_id', p_primary_product_id, 'version_no', v_next_version, 'outputs', v_output_count)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'receta con costeo creada';
    SET o_data_json = JSON_OBJECT('recipe_id', v_recipe_id, 'product_id', p_primary_product_id, 'version_no', v_next_version);
  END IF;

  DROP TEMPORARY TABLE IF EXISTS tmp_recipe_base_items;
  DROP TEMPORARY TABLE IF EXISTS tmp_recipe_outputs;
  DROP TEMPORARY TABLE IF EXISTS tmp_recipe_output_items;
END $$

DROP PROCEDURE IF EXISTS sp_register_production_result $$
CREATE PROCEDURE sp_register_production_result(
  IN p_branch_id BIGINT UNSIGNED,
  IN p_product_id BIGINT UNSIGNED,
  IN p_recipe_id BIGINT UNSIGNED,
  IN p_produced_qty DECIMAL(12,3),
  IN p_actor_user_id BIGINT UNSIGNED,
  IN p_reference_type VARCHAR(50),
  IN p_reference_id BIGINT UNSIGNED,
  IN p_notes VARCHAR(255),
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE v_recipe_output_qty DECIMAL(12,3);
  DECLARE v_factor DECIMAL(18,6);

  DECLARE v_raw_material_id BIGINT UNSIGNED;
  DECLARE v_base_qty DECIMAL(12,4);
  DECLARE v_wastage DECIMAL(5,2);
  DECLARE v_required_qty DECIMAL(14,3);
  DECLARE v_stock_qty DECIMAL(14,3);
  DECLARE v_signal_msg VARCHAR(255);

  DECLARE done INT DEFAULT 0;

  DECLARE cur_recipe CURSOR FOR
    SELECT raw_material_id, quantity, wastage_percent
    FROM recipe_items
    WHERE recipe_id = p_recipe_id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  SET o_code = 0;
  SET o_message = 'operacion completada';
  SET o_data_json = NULL;

  IF p_produced_qty IS NULL OR p_produced_qty <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cantidad producida (produced_qty) debe ser mayor que 0';
  END IF;

  START TRANSACTION;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND is_active = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sede no encontrada o inactiva';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM products
    WHERE id = p_product_id AND is_active = 1 AND deleted_at IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'producto no encontrado o inactivo';
  END IF;

  SELECT COALESCE(ro.expected_quantity, r.output_quantity)
    INTO v_recipe_output_qty
  FROM recipes r
  LEFT JOIN recipe_outputs ro
    ON ro.recipe_id = r.id
   AND ro.product_id = p_product_id
  WHERE r.id = p_recipe_id
    AND r.is_active = 1
    AND COALESCE(ro.product_id, r.product_id) = p_product_id
  LIMIT 1
  FOR UPDATE;

  IF v_recipe_output_qty IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'receta no encontrada, inactiva o no asociada al producto';
  END IF;

  IF v_recipe_output_qty <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'output_quantity de receta debe ser > 0';
  END IF;

  SET v_factor = p_produced_qty / v_recipe_output_qty;

  OPEN cur_recipe;

  read_loop: LOOP
    FETCH cur_recipe INTO v_raw_material_id, v_base_qty, v_wastage;
    IF done = 1 THEN
      LEAVE read_loop;
    END IF;

    SET v_required_qty = ROUND((v_base_qty * v_factor) * (1 + (v_wastage / 100)), 3);

    INSERT IGNORE INTO stock_raw_materials (branch_id, raw_material_id, quantity_on_hand, min_stock)
    VALUES (p_branch_id, v_raw_material_id, 0, 0);

    SELECT quantity_on_hand
      INTO v_stock_qty
    FROM stock_raw_materials
    WHERE branch_id = p_branch_id
      AND raw_material_id = v_raw_material_id
    FOR UPDATE;

    IF v_stock_qty < v_required_qty THEN
      SET v_signal_msg = CONCAT('insufficient raw stock for material_id=', v_raw_material_id);
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_signal_msg;
    END IF;

    UPDATE stock_raw_materials
    SET quantity_on_hand = quantity_on_hand - v_required_qty
    WHERE branch_id = p_branch_id
      AND raw_material_id = v_raw_material_id;

    INSERT INTO inventory_movements (
      branch_id, item_type, raw_material_id, product_id, movement_type,
      quantity, unit_cost, reference_type, reference_id, notes, created_by
    )
    VALUES (
      p_branch_id, 'raw_material', v_raw_material_id, NULL, 'production_out',
      v_required_qty, NULL, p_reference_type, p_reference_id, p_notes, p_actor_user_id
    );
  END LOOP;

  CLOSE cur_recipe;

  INSERT IGNORE INTO stock_products (branch_id, product_id, quantity_on_hand, min_stock)
  VALUES (p_branch_id, p_product_id, 0, 0);

  UPDATE stock_products
  SET quantity_on_hand = quantity_on_hand + p_produced_qty
  WHERE branch_id = p_branch_id
    AND product_id = p_product_id;

  INSERT INTO inventory_movements (
    branch_id, item_type, raw_material_id, product_id, movement_type,
    quantity, unit_cost, reference_type, reference_id, notes, created_by
  )
  VALUES (
    p_branch_id, 'product', NULL, p_product_id, 'production_in',
    p_produced_qty, NULL, p_reference_type, p_reference_id, p_notes, p_actor_user_id
  );

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_actor_user_id,
    'production.register',
    'products',
    CAST(p_product_id AS CHAR),
    JSON_OBJECT(
      'branch_id', p_branch_id,
      'recipe_id', p_recipe_id,
      'produced_qty', p_produced_qty,
      'reference_type', p_reference_type,
      'reference_id', p_reference_id
    )
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'produccion registrada e inventario actualizado';
END $$

DELIMITER ;
