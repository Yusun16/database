-- Justified shortages found during packaging.
-- Run after:
--   039_packed_product_inventory_guard.sql

USE panaderia_db;

SET @production_outputs_missing_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'production_batch_outputs'
    AND COLUMN_NAME = 'missing_quantity'
);

SET @production_outputs_missing_sql = IF(
  @production_outputs_missing_exists = 0,
  'ALTER TABLE production_batch_outputs
     ADD COLUMN missing_quantity DECIMAL(14,3) NOT NULL DEFAULT 0 AFTER damaged_quantity',
  'SELECT 1'
);

PREPARE production_outputs_missing_stmt FROM @production_outputs_missing_sql;
EXECUTE production_outputs_missing_stmt;
DEALLOCATE PREPARE production_outputs_missing_stmt;

SET @packing_items_missing_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'packing_report_items'
    AND COLUMN_NAME = 'missing_quantity'
);

SET @packing_items_missing_sql = IF(
  @packing_items_missing_exists = 0,
  'ALTER TABLE packing_report_items
     ADD COLUMN missing_quantity DECIMAL(14,3) NOT NULL DEFAULT 0 AFTER damaged_quantity',
  'SELECT 1'
);

PREPARE packing_items_missing_stmt FROM @packing_items_missing_sql;
EXECUTE packing_items_missing_stmt;
DEALLOCATE PREPARE packing_items_missing_stmt;

SET @packing_items_missing_reason_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'packing_report_items'
    AND COLUMN_NAME = 'missing_reason'
);

SET @packing_items_missing_reason_sql = IF(
  @packing_items_missing_reason_exists = 0,
  'ALTER TABLE packing_report_items
     ADD COLUMN missing_reason ENUM(''count_difference'',''handling_loss'',''suspected_theft'',''other'') NULL AFTER damage_reason',
  'SELECT 1'
);

PREPARE packing_items_missing_reason_stmt FROM @packing_items_missing_reason_sql;
EXECUTE packing_items_missing_reason_stmt;
DEALLOCATE PREPARE packing_items_missing_reason_stmt;

SET @production_output_balance_check_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'production_batch_outputs'
    AND CONSTRAINT_NAME = 'chk_production_batch_outputs_balance'
);

SET @production_output_balance_drop_sql = IF(
  @production_output_balance_check_exists > 0,
  'ALTER TABLE production_batch_outputs DROP CHECK chk_production_batch_outputs_balance',
  'SELECT 1'
);

PREPARE production_output_balance_drop_stmt FROM @production_output_balance_drop_sql;
EXECUTE production_output_balance_drop_stmt;
DEALLOCATE PREPARE production_output_balance_drop_stmt;

ALTER TABLE production_batch_outputs
  ADD CONSTRAINT chk_production_batch_outputs_balance
  CHECK (packed_quantity + damaged_quantity + missing_quantity <= produced_quantity);

SET @packing_items_quantity_check_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'packing_report_items'
    AND CONSTRAINT_NAME = 'chk_packing_items_qty'
);

SET @packing_items_quantity_drop_sql = IF(
  @packing_items_quantity_check_exists > 0,
  'ALTER TABLE packing_report_items DROP CHECK chk_packing_items_qty',
  'SELECT 1'
);

PREPARE packing_items_quantity_drop_stmt FROM @packing_items_quantity_drop_sql;
EXECUTE packing_items_quantity_drop_stmt;
DEALLOCATE PREPARE packing_items_quantity_drop_stmt;

ALTER TABLE packing_report_items
  ADD CONSTRAINT chk_packing_items_qty
  CHECK (
    packed_quantity >= 0
    AND damaged_quantity >= 0
    AND missing_quantity >= 0
  );

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
          'pending_quantity', GREATEST(
            pbo.produced_quantity - pbo.packed_quantity - pbo.damaged_quantity - pbo.missing_quantity,
            0
          ),
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
      pb.id, pb.branch_id, b.name, pb.recipe_id, r.notes, p.name,
      pb.baker_employee_id, u.full_name, pb.produced_date, pb.status
    ORDER BY pb.produced_date DESC, pb.id DESC
  ) x;
END $$

DROP PROCEDURE IF EXISTS sp_packing_report_create $$
CREATE PROCEDURE sp_packing_report_create(
  IN p_production_batch_id BIGINT UNSIGNED,
  IN p_packer_employee_id BIGINT UNSIGNED,
  IN p_packed_date DATE,
  IN p_items_json JSON,
  IN p_notes VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_report_id BIGINT UNSIGNED;
  DECLARE v_branch_id BIGINT UNSIGNED;
  DECLARE v_item_count INT DEFAULT 0;
  DECLARE v_pending_count INT DEFAULT 0;
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1
      v_sqlstate = RETURNED_SQLSTATE,
      v_errno = MYSQL_ERRNO,
      v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    DROP TEMPORARY TABLE IF EXISTS tmp_packing_items;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  START TRANSACTION;

  SELECT branch_id INTO v_branch_id
  FROM production_batches
  WHERE id = p_production_batch_id
    AND status IN ('pending_packaging','partially_packed')
  FOR UPDATE;

  IF v_branch_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'produccion no encontrada o no pendiente por empacar';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM employees
    WHERE id = p_packer_employee_id
      AND job_type = 'packer'
      AND status = 'active'
      AND deleted_at IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'empaquetador no encontrado o inactivo';
  END IF;

  DROP TEMPORARY TABLE IF EXISTS tmp_packing_items;
  CREATE TEMPORARY TABLE tmp_packing_items (
    production_batch_output_id BIGINT UNSIGNED NOT NULL,
    packed_quantity DECIMAL(14,3) NOT NULL,
    damaged_quantity DECIMAL(14,3) NOT NULL,
    missing_quantity DECIMAL(14,3) NOT NULL,
    damage_reason VARCHAR(30) NULL,
    missing_reason VARCHAR(40) NULL,
    notes VARCHAR(255) NULL
  ) ENGINE=Memory;

  INSERT INTO tmp_packing_items (
    production_batch_output_id, packed_quantity, damaged_quantity,
    missing_quantity, damage_reason, missing_reason, notes
  )
  SELECT
    jt.production_batch_output_id,
    COALESCE(jt.packed_quantity, 0),
    COALESCE(jt.damaged_quantity, 0),
    COALESCE(jt.missing_quantity, 0),
    jt.damage_reason,
    jt.missing_reason,
    jt.notes
  FROM JSON_TABLE(
    p_items_json,
    '$[*]' COLUMNS (
      production_batch_output_id BIGINT UNSIGNED PATH '$.production_batch_output_id',
      packed_quantity DECIMAL(14,3) PATH '$.packed_quantity' DEFAULT '0' ON EMPTY,
      damaged_quantity DECIMAL(14,3) PATH '$.damaged_quantity' DEFAULT '0' ON EMPTY,
      missing_quantity DECIMAL(14,3) PATH '$.missing_quantity' DEFAULT '0' ON EMPTY,
      damage_reason VARCHAR(30) PATH '$.damage_reason' NULL ON EMPTY,
      missing_reason VARCHAR(40) PATH '$.missing_reason' NULL ON EMPTY,
      notes VARCHAR(255) PATH '$.notes' NULL ON EMPTY
    )
  ) jt;

  SELECT COUNT(*) INTO v_item_count FROM tmp_packing_items;

  IF v_item_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'agrega al menos un producto empacado, danado o faltante';
  END IF;

  IF EXISTS (
    SELECT 1 FROM tmp_packing_items
    WHERE packed_quantity < 0
      OR damaged_quantity < 0
      OR missing_quantity < 0
      OR (packed_quantity + damaged_quantity + missing_quantity) <= 0
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'las cantidades deben ser validas y al menos una debe ser mayor que 0';
  END IF;

  IF EXISTS (
    SELECT 1 FROM tmp_packing_items
    WHERE missing_quantity > 0
      AND (
        missing_reason IS NULL
        OR missing_reason NOT IN ('count_difference','handling_loss','suspected_theft','other')
        OR notes IS NULL
        OR TRIM(notes) = ''
      )
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'todo faltante debe tener motivo y explicacion';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tmp_packing_items t
    LEFT JOIN production_batch_outputs pbo
      ON pbo.id = t.production_batch_output_id
     AND pbo.production_batch_id = p_production_batch_id
    WHERE pbo.id IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'un producto no pertenece a la produccion seleccionada';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tmp_packing_items t
    INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id
    WHERE (t.packed_quantity + t.damaged_quantity + t.missing_quantity) >
      (pbo.produced_quantity - pbo.packed_quantity - pbo.damaged_quantity - pbo.missing_quantity)
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cantidad registrada supera el pendiente del producto';
  END IF;

  INSERT INTO packing_reports (
    production_batch_id, packer_employee_id, packed_date, notes, created_by
  ) VALUES (
    p_production_batch_id, p_packer_employee_id,
    COALESCE(p_packed_date, CURRENT_DATE), p_notes, p_actor_user_id
  );

  SET v_report_id = LAST_INSERT_ID();

  INSERT INTO packing_report_items (
    packing_report_id, production_batch_output_id, product_id,
    packed_quantity, damaged_quantity, missing_quantity,
    damage_reason, missing_reason, notes
  )
  SELECT
    v_report_id, pbo.id, pbo.product_id,
    t.packed_quantity, t.damaged_quantity, t.missing_quantity,
    CASE WHEN t.damage_reason IN ('cut','packaging') THEN t.damage_reason ELSE NULL END,
    CASE
      WHEN t.missing_reason IN ('count_difference','handling_loss','suspected_theft','other')
      THEN t.missing_reason
      ELSE NULL
    END,
    t.notes
  FROM tmp_packing_items t
  INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id;

  INSERT INTO production_damages (
    production_batch_id, production_batch_output_id, product_id,
    responsible_employee_id, damage_stage, quantity, damaged_date, notes, created_by
  )
  SELECT
    p_production_batch_id, pbo.id, pbo.product_id, p_packer_employee_id,
    CASE WHEN t.damage_reason = 'cut' THEN 'cut' ELSE 'packaging' END,
    t.damaged_quantity, COALESCE(p_packed_date, CURRENT_DATE), t.notes, p_actor_user_id
  FROM tmp_packing_items t
  INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id
  WHERE t.damaged_quantity > 0;

  UPDATE production_batch_outputs pbo
  INNER JOIN tmp_packing_items t ON t.production_batch_output_id = pbo.id
  SET pbo.packed_quantity = pbo.packed_quantity + t.packed_quantity,
      pbo.damaged_quantity = pbo.damaged_quantity + t.damaged_quantity,
      pbo.missing_quantity = pbo.missing_quantity + t.missing_quantity,
      pbo.updated_at = CURRENT_TIMESTAMP;

  INSERT INTO inventory_movements (
    branch_id, item_type, raw_material_id, product_id, movement_type,
    quantity, unit_cost, reference_type, reference_id, notes, created_by
  )
  SELECT
    v_branch_id, 'product', NULL, pbo.product_id, 'production_in',
    t.packed_quantity, NULL, 'packing_report', v_report_id, p_notes, p_actor_user_id
  FROM tmp_packing_items t
  INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id
  WHERE t.packed_quantity > 0;

  INSERT INTO stock_products (branch_id, product_id, quantity_on_hand, min_stock)
  SELECT DISTINCT v_branch_id, pbo.product_id, 0, 0
  FROM tmp_packing_items t
  INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id
  ON DUPLICATE KEY UPDATE quantity_on_hand = quantity_on_hand;

  UPDATE stock_products sp
  INNER JOIN (
    SELECT pbo.product_id, SUM(t.packed_quantity) AS qty
    FROM tmp_packing_items t
    INNER JOIN production_batch_outputs pbo ON pbo.id = t.production_batch_output_id
    GROUP BY pbo.product_id
  ) x ON x.product_id = sp.product_id
  SET sp.quantity_on_hand = sp.quantity_on_hand + x.qty
  WHERE sp.branch_id = v_branch_id;

  SELECT COUNT(*) INTO v_pending_count
  FROM production_batch_outputs
  WHERE production_batch_id = p_production_batch_id
    AND (produced_quantity - packed_quantity - damaged_quantity - missing_quantity) > 0;

  UPDATE production_batches
  SET status = CASE WHEN v_pending_count = 0 THEN 'packed' ELSE 'partially_packed' END,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_production_batch_id;

  DROP TEMPORARY TABLE IF EXISTS tmp_packing_items;

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_actor_user_id,
    'packing.report.create',
    'packing_reports',
    CAST(v_report_id AS CHAR),
    JSON_OBJECT(
      'production_batch_id', p_production_batch_id,
      'packer_employee_id', p_packer_employee_id
    )
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'empaque y novedades registrados';
  SET o_data_json = JSON_OBJECT('packing_report_id', v_report_id);
END $$

DELIMITER ;
