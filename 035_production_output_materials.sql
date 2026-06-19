-- Production output materials.
-- Run after:
--   034_recipe_costing_flow.sql

USE panaderia_db;

CREATE TABLE IF NOT EXISTS production_output_materials (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  production_batch_id BIGINT UNSIGNED NOT NULL,
  production_batch_output_id BIGINT UNSIGNED NOT NULL,
  product_id BIGINT UNSIGNED NOT NULL,
  raw_material_id BIGINT UNSIGNED NOT NULL,
  concept VARCHAR(60) NOT NULL DEFAULT 'RELLENO',
  quantity DECIMAL(14,4) NOT NULL,
  notes VARCHAR(255) NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_production_output_materials_batch (production_batch_id),
  KEY idx_production_output_materials_output (production_batch_output_id),
  KEY idx_production_output_materials_product (product_id),
  KEY idx_production_output_materials_material (raw_material_id),
  CONSTRAINT fk_production_output_materials_batch
    FOREIGN KEY (production_batch_id) REFERENCES production_batches (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_output_materials_output
    FOREIGN KEY (production_batch_output_id) REFERENCES production_batch_outputs (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_output_materials_product
    FOREIGN KEY (product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_output_materials_material
    FOREIGN KEY (raw_material_id) REFERENCES raw_materials (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_output_materials_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_production_output_materials_qty CHECK (quantity > 0)
) ENGINE=InnoDB;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_packing_pending_list $$
CREATE PROCEDURE sp_packing_pending_list(
  IN p_branch_id BIGINT UNSIGNED,
  IN p_search VARCHAR(120),
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  SET o_code = 1;
  SET o_message = 'pendientes por empacar listados';

  SELECT COALESCE(JSON_ARRAYAGG(
    JSON_OBJECT(
      'production_batch_id', x.production_batch_id,
      'branch_id', x.branch_id,
      'branch_name', x.branch_name,
      'recipe_id', x.recipe_id,
      'recipe_name', x.recipe_name,
      'baker_employee_id', x.baker_employee_id,
      'baker_name', x.baker_name,
      'produced_date', x.produced_date,
      'status', x.status,
      'items', x.items
    )
  ), JSON_ARRAY())
  INTO o_data_json
  FROM (
    SELECT
      pb.id AS production_batch_id,
      pb.branch_id,
      b.name AS branch_name,
      pb.recipe_id,
      COALESCE(NULLIF(SUBSTRING_INDEX(r.notes, ' - ', 1), ''), p.name, CONCAT('Receta #', r.id)) AS recipe_name,
      pb.baker_employee_id,
      u.full_name AS baker_name,
      pb.produced_date,
      pb.status,
      JSON_ARRAYAGG(
        JSON_OBJECT(
          'production_batch_output_id', pbo.id,
          'product_id', pbo.product_id,
          'product_name', po.name,
          'product_sku', po.sku,
          'produced_quantity', pbo.produced_quantity,
          'packed_quantity', pbo.packed_quantity,
          'damaged_quantity', pbo.damaged_quantity,
          'missing_quantity', pbo.missing_quantity,
          'pending_quantity', GREATEST(pbo.produced_quantity - pbo.packed_quantity - pbo.damaged_quantity - pbo.missing_quantity, 0),
          'packing_note', pbo.packing_note
        )
      ) AS items
    FROM production_batches pb
    INNER JOIN branches b ON b.id = pb.branch_id
    INNER JOIN recipes r ON r.id = pb.recipe_id
    LEFT JOIN products p ON p.id = r.product_id
    INNER JOIN employees e ON e.id = pb.baker_employee_id
    INNER JOIN users u ON u.id = e.user_id
    INNER JOIN production_batch_outputs pbo ON pbo.production_batch_id = pb.id
    INNER JOIN products po ON po.id = pbo.product_id
    WHERE pb.status IN ('pending_packaging','partially_packed')
      AND (p_branch_id IS NULL OR pb.branch_id = p_branch_id)
      AND (
        p_search IS NULL OR p_search = ''
        OR po.name LIKE CONCAT('%', p_search, '%')
        OR u.full_name LIKE CONCAT('%', p_search, '%')
        OR p.name LIKE CONCAT('%', p_search, '%')
        OR r.notes LIKE CONCAT('%', p_search, '%')
      )
    GROUP BY
      pb.id,
      pb.branch_id,
      b.name,
      pb.recipe_id,
      r.notes,
      p.name,
      pb.baker_employee_id,
      u.full_name,
      pb.produced_date,
      pb.status
    ORDER BY pb.produced_date DESC, pb.id DESC
  ) x;
END $$

DROP PROCEDURE IF EXISTS sp_production_batch_register_selected $$
CREATE PROCEDURE sp_production_batch_register_selected(
  IN p_branch_id BIGINT UNSIGNED,
  IN p_recipe_id BIGINT UNSIGNED,
  IN p_baker_employee_id BIGINT UNSIGNED,
  IN p_produced_date DATE,
  IN p_batch_quantity DECIMAL(14,3),
  IN p_outputs_json JSON,
  IN p_notes VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_batch_id BIGINT UNSIGNED;
  DECLARE v_batch_qty DECIMAL(14,3) DEFAULT 1;
  DECLARE v_output_count INT DEFAULT 0;

  DECLARE v_raw_material_id BIGINT UNSIGNED;
  DECLARE v_base_qty DECIMAL(12,4);
  DECLARE v_wastage DECIMAL(5,2);
  DECLARE v_required_qty DECIMAL(14,3);
  DECLARE v_stock_qty DECIMAL(14,3);
  DECLARE v_signal_msg VARCHAR(255);

  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

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
    DROP TEMPORARY TABLE IF EXISTS tmp_selected_outputs;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  SET v_batch_qty = COALESCE(p_batch_quantity, 1);

  IF v_batch_qty <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cantidad de mojes debe ser mayor que 0';
  END IF;

  DROP TEMPORARY TABLE IF EXISTS tmp_selected_outputs;
  CREATE TEMPORARY TABLE tmp_selected_outputs (
    product_id BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (product_id)
  ) ENGINE=Memory;

  INSERT IGNORE INTO tmp_selected_outputs (product_id)
  SELECT jt.product_id
  FROM JSON_TABLE(
    COALESCE(p_outputs_json, JSON_ARRAY()),
    '$[*]' COLUMNS (
      product_id BIGINT UNSIGNED PATH '$.product_id'
    )
  ) jt
  WHERE jt.product_id IS NOT NULL;

  SELECT COUNT(*) INTO v_output_count
  FROM tmp_selected_outputs;

  IF v_output_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'selecciona al menos un producto final para realizar';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tmp_selected_outputs t
    LEFT JOIN recipe_outputs ro
      ON ro.recipe_id = p_recipe_id
     AND ro.product_id = t.product_id
    WHERE ro.id IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'un producto final no pertenece a la receta seleccionada';
  END IF;

  START TRANSACTION;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND is_active = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sucursal no encontrada o inactiva';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM recipes WHERE id = p_recipe_id AND is_active = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'receta no encontrada o inactiva';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM employees
    WHERE id = p_baker_employee_id
      AND job_type = 'baker'
      AND status = 'active'
      AND deleted_at IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'panadero no encontrado o inactivo';
  END IF;

  INSERT INTO production_batches (
    branch_id,
    recipe_id,
    baker_employee_id,
    produced_date,
    batch_quantity,
    status,
    notes,
    created_by
  )
  VALUES (
    p_branch_id,
    p_recipe_id,
    p_baker_employee_id,
    COALESCE(p_produced_date, CURRENT_DATE),
    v_batch_qty,
    'pending_packaging',
    p_notes,
    p_actor_user_id
  );

  SET v_batch_id = LAST_INSERT_ID();

  OPEN cur_recipe;

  read_loop: LOOP
    FETCH cur_recipe INTO v_raw_material_id, v_base_qty, v_wastage;
    IF done = 1 THEN
      LEAVE read_loop;
    END IF;

    SET v_required_qty = ROUND((v_base_qty * v_batch_qty) * (1 + (v_wastage / 100)), 3);

    INSERT IGNORE INTO stock_raw_materials (branch_id, raw_material_id, quantity_on_hand, min_stock)
    VALUES (p_branch_id, v_raw_material_id, 0, 0);

    SELECT quantity_on_hand
      INTO v_stock_qty
    FROM stock_raw_materials
    WHERE branch_id = p_branch_id
      AND raw_material_id = v_raw_material_id
    FOR UPDATE;

    IF v_stock_qty < v_required_qty THEN
      SET v_signal_msg = CONCAT('stock insuficiente para materia prima ', v_raw_material_id);
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
      v_required_qty, NULL, 'production_batch', v_batch_id, p_notes, p_actor_user_id
    );
  END LOOP;

  CLOSE cur_recipe;

  INSERT INTO production_batch_outputs (
    production_batch_id,
    product_id,
    expected_quantity,
    produced_quantity,
    packing_note
  )
  SELECT
    v_batch_id,
    ro.product_id,
    ro.expected_quantity,
    ROUND(ro.expected_quantity * v_batch_qty, 3),
    ro.packing_note
  FROM recipe_outputs ro
  INNER JOIN tmp_selected_outputs t ON t.product_id = ro.product_id
  WHERE ro.recipe_id = p_recipe_id;

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_actor_user_id,
    'production_batch.register_selected',
    'production_batches',
    CAST(v_batch_id AS CHAR),
    JSON_OBJECT('branch_id', p_branch_id, 'recipe_id', p_recipe_id, 'baker_employee_id', p_baker_employee_id, 'batch_quantity', v_batch_qty, 'outputs', v_output_count)
  );

  COMMIT;

  DROP TEMPORARY TABLE IF EXISTS tmp_selected_outputs;

  SET o_code = 1;
  SET o_message = 'produccion registrada con productos seleccionados y pendiente por empacar';
  SET o_data_json = JSON_OBJECT('production_batch_id', v_batch_id);
END $$

DROP PROCEDURE IF EXISTS sp_production_output_material_add $$
CREATE PROCEDURE sp_production_output_material_add(
  IN p_production_batch_id BIGINT UNSIGNED,
  IN p_production_batch_output_id BIGINT UNSIGNED,
  IN p_raw_material_id BIGINT UNSIGNED,
  IN p_concept VARCHAR(60),
  IN p_quantity DECIMAL(14,4),
  IN p_notes VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_material_entry_id BIGINT UNSIGNED;
  DECLARE v_branch_id BIGINT UNSIGNED;
  DECLARE v_product_id BIGINT UNSIGNED;
  DECLARE v_stock_qty DECIMAL(14,3);
  DECLARE v_concept VARCHAR(60);
  DECLARE v_signal_msg VARCHAR(255);

  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  SET v_concept = COALESCE(NULLIF(TRIM(p_concept), ''), 'RELLENO');

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    SET o_code = 0;
    SET o_message = 'la cantidad debe ser mayor que 0';
    SET o_data_json = NULL;
  ELSE
    START TRANSACTION;

    SELECT
      pb.branch_id,
      pbo.product_id
    INTO
      v_branch_id,
      v_product_id
    FROM production_batch_outputs pbo
    INNER JOIN production_batches pb ON pb.id = pbo.production_batch_id
    WHERE pb.id = p_production_batch_id
      AND pbo.id = p_production_batch_output_id
      AND pb.status IN ('pending_packaging','partially_packed')
    FOR UPDATE;

    IF v_branch_id IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'producto de produccion no encontrado o no pendiente por conteo';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM raw_materials
      WHERE id = p_raw_material_id
        AND is_active = 1
        AND deleted_at IS NULL
    ) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'materia prima no encontrada o inactiva';
    END IF;

    INSERT IGNORE INTO stock_raw_materials (branch_id, raw_material_id, quantity_on_hand, min_stock)
    VALUES (v_branch_id, p_raw_material_id, 0, 0);

    SELECT quantity_on_hand
      INTO v_stock_qty
    FROM stock_raw_materials
    WHERE branch_id = v_branch_id
      AND raw_material_id = p_raw_material_id
    FOR UPDATE;

    IF v_stock_qty < p_quantity THEN
      SET v_signal_msg = CONCAT('stock insuficiente para materia prima ', p_raw_material_id);
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_signal_msg;
    END IF;

    UPDATE stock_raw_materials
    SET quantity_on_hand = quantity_on_hand - p_quantity
    WHERE branch_id = v_branch_id
      AND raw_material_id = p_raw_material_id;

    INSERT INTO production_output_materials (
      production_batch_id,
      production_batch_output_id,
      product_id,
      raw_material_id,
      concept,
      quantity,
      notes,
      created_by
    )
    VALUES (
      p_production_batch_id,
      p_production_batch_output_id,
      v_product_id,
      p_raw_material_id,
      v_concept,
      p_quantity,
      p_notes,
      p_actor_user_id
    );

    SET v_material_entry_id = LAST_INSERT_ID();

    INSERT INTO inventory_movements (
      branch_id, item_type, raw_material_id, product_id, movement_type,
      quantity, unit_cost, reference_type, reference_id, notes, created_by
    )
    VALUES (
      v_branch_id, 'raw_material', p_raw_material_id, NULL, 'production_out',
      p_quantity, NULL, 'production_output_material', v_material_entry_id, p_notes, p_actor_user_id
    );

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'production.output_material.add',
      'production_output_materials',
      CAST(v_material_entry_id AS CHAR),
      JSON_OBJECT(
        'production_batch_id', p_production_batch_id,
        'production_batch_output_id', p_production_batch_output_id,
        'raw_material_id', p_raw_material_id,
        'quantity', p_quantity
      )
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'ingrediente posterior registrado';
    SET o_data_json = JSON_OBJECT('production_output_material_id', v_material_entry_id);
  END IF;
END $$

DROP PROCEDURE IF EXISTS sp_production_output_materials_list $$
CREATE PROCEDURE sp_production_output_materials_list(
  IN p_production_batch_id BIGINT UNSIGNED,
  IN p_production_batch_output_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  SET o_code = 1;
  SET o_message = 'ingredientes posteriores listados';

  SELECT COALESCE(JSON_ARRAYAGG(
    JSON_OBJECT(
      'id', x.id,
      'production_batch_id', x.production_batch_id,
      'production_batch_output_id', x.production_batch_output_id,
      'product_id', x.product_id,
      'product_name', x.product_name,
      'raw_material_id', x.raw_material_id,
      'raw_material_name', x.raw_material_name,
      'raw_material_unit', x.raw_material_unit,
      'concept', x.concept,
      'quantity', x.quantity,
      'notes', x.notes,
      'created_at', x.created_at
    )
  ), JSON_ARRAY())
  INTO o_data_json
  FROM (
    SELECT
      pom.id,
      pom.production_batch_id,
      pom.production_batch_output_id,
      pom.product_id,
      p.name AS product_name,
      pom.raw_material_id,
      rm.name AS raw_material_name,
      rm.unit AS raw_material_unit,
      pom.concept,
      pom.quantity,
      pom.notes,
      pom.created_at
    FROM production_output_materials pom
    INNER JOIN products p ON p.id = pom.product_id
    INNER JOIN raw_materials rm ON rm.id = pom.raw_material_id
    WHERE (p_production_batch_id IS NULL OR pom.production_batch_id = p_production_batch_id)
      AND (p_production_batch_output_id IS NULL OR pom.production_batch_output_id = p_production_batch_output_id)
    ORDER BY pom.created_at DESC, pom.id DESC
  ) x;
END $$

DELIMITER ;
