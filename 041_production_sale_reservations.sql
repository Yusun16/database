-- Sales reserved from production in progress and direct delivery.
-- Run after:
--   040_justified_production_shortages.sql

USE panaderia_db;

SET @production_outputs_direct_delivery_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'production_batch_outputs'
    AND COLUMN_NAME = 'direct_delivered_quantity'
);

SET @production_outputs_direct_delivery_sql = IF(
  @production_outputs_direct_delivery_exists = 0,
  'ALTER TABLE production_batch_outputs
     ADD COLUMN direct_delivered_quantity DECIMAL(14,3) NOT NULL DEFAULT 0 AFTER missing_quantity',
  'SELECT 1'
);

PREPARE production_outputs_direct_delivery_stmt FROM @production_outputs_direct_delivery_sql;
EXECUTE production_outputs_direct_delivery_stmt;
DEALLOCATE PREPARE production_outputs_direct_delivery_stmt;

CREATE TABLE IF NOT EXISTS production_sale_reservations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_item_id BIGINT UNSIGNED NOT NULL,
  production_plan_output_id BIGINT UNSIGNED NOT NULL,
  production_batch_output_id BIGINT UNSIGNED NULL,
  quantity DECIMAL(14,3) NOT NULL,
  delivered_quantity DECIMAL(14,3) NOT NULL DEFAULT 0,
  status ENUM('reserved','partially_delivered','delivered','released','cancelled')
    NOT NULL DEFAULT 'reserved',
  notes VARCHAR(255) NULL,
  created_by BIGINT UNSIGNED NULL,
  delivered_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  delivered_at TIMESTAMP NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_production_sale_reservations_order_item (order_item_id, status),
  KEY idx_production_sale_reservations_plan_output (production_plan_output_id, status),
  KEY idx_production_sale_reservations_batch_output (production_batch_output_id, status),
  CONSTRAINT fk_production_sale_reservations_order_item
    FOREIGN KEY (order_item_id) REFERENCES order_items (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_sale_reservations_plan_output
    FOREIGN KEY (production_plan_output_id) REFERENCES production_plan_outputs (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_sale_reservations_batch_output
    FOREIGN KEY (production_batch_output_id) REFERENCES production_batch_outputs (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_production_sale_reservations_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_production_sale_reservations_delivered_by
    FOREIGN KEY (delivered_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_production_sale_reservations_quantity
    CHECK (
      quantity > 0
      AND delivered_quantity >= 0
      AND delivered_quantity <= quantity
    )
) ENGINE=InnoDB;

SET @production_outputs_balance_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'production_batch_outputs'
    AND CONSTRAINT_NAME = 'chk_production_batch_outputs_balance'
);

SET @production_outputs_drop_balance_sql = IF(
  @production_outputs_balance_exists > 0,
  'ALTER TABLE production_batch_outputs DROP CHECK chk_production_batch_outputs_balance',
  'SELECT 1'
);

PREPARE production_outputs_drop_balance_stmt FROM @production_outputs_drop_balance_sql;
EXECUTE production_outputs_drop_balance_stmt;
DEALLOCATE PREPARE production_outputs_drop_balance_stmt;

ALTER TABLE production_batch_outputs
  ADD CONSTRAINT chk_production_batch_outputs_balance
  CHECK (
    packed_quantity
    + damaged_quantity
    + missing_quantity
    + direct_delivered_quantity
    <= produced_quantity
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
          'direct_delivered_quantity', pbo.direct_delivered_quantity,
          'reserved_quantity', COALESCE(res.reserved_quantity, 0),
          'pending_quantity', GREATEST(
            pbo.produced_quantity
            - pbo.packed_quantity
            - pbo.damaged_quantity
            - pbo.missing_quantity
            - pbo.direct_delivered_quantity
            - COALESCE(res.reserved_quantity, 0),
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
    LEFT JOIN (
      SELECT
        production_batch_output_id,
        SUM(quantity - delivered_quantity) AS reserved_quantity
      FROM production_sale_reservations
      WHERE status IN ('reserved','partially_delivered')
      GROUP BY production_batch_output_id
    ) res ON res.production_batch_output_id = pbo.id
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
      (
        pbo.produced_quantity
        - pbo.packed_quantity
        - pbo.damaged_quantity
        - pbo.missing_quantity
        - pbo.direct_delivered_quantity
        - COALESCE((
          SELECT SUM(psr.quantity - psr.delivered_quantity)
          FROM production_sale_reservations psr
          WHERE psr.production_batch_output_id = pbo.id
            AND psr.status IN ('reserved','partially_delivered')
        ), 0)
      )
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
    AND (
      produced_quantity
      - packed_quantity
      - damaged_quantity
      - missing_quantity
      - direct_delivered_quantity
    ) > 0;

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

DROP PROCEDURE IF EXISTS sp_dispatch_order $$
CREATE PROCEDURE sp_dispatch_order(
  IN p_order_id BIGINT UNSIGNED,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_status VARCHAR(30);
  DECLARE v_branch_id BIGINT UNSIGNED;
  DECLARE v_items_count INT DEFAULT 0;
  DECLARE v_dispatched_rows INT DEFAULT 0;
  DECLARE v_pending_reservations INT DEFAULT 0;
  DECLARE v_item_id BIGINT UNSIGNED;
  DECLARE v_product_id BIGINT UNSIGNED;
  DECLARE v_qty DECIMAL(12,3);
  DECLARE v_direct_qty DECIMAL(14,3);
  DECLARE v_stock_dispatch_qty DECIMAL(14,3);
  DECLARE v_stock_qty DECIMAL(14,3);
  DECLARE done INT DEFAULT 0;
  DECLARE v_signal_msg VARCHAR(255);
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE cur_items CURSOR FOR
    SELECT id, product_id, quantity
    FROM order_items
    WHERE order_id = p_order_id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1
      v_sqlstate = RETURNED_SQLSTATE,
      v_errno = MYSQL_ERRNO,
      v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  START TRANSACTION;

  SELECT status, branch_id INTO v_status, v_branch_id
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'pedido no encontrado';
  END IF;

  IF v_status NOT IN ('confirmed', 'ready', 'in_production') THEN
    SET v_signal_msg = CONCAT('el pedido no se puede despachar desde el estado ', v_status);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_signal_msg;
  END IF;

  SELECT COUNT(*) INTO v_items_count
  FROM order_items
  WHERE order_id = p_order_id;

  IF v_items_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el pedido no tiene items';
  END IF;

  SELECT COUNT(*) INTO v_pending_reservations
  FROM production_sale_reservations psr
  INNER JOIN order_items oi ON oi.id = psr.order_item_id
  WHERE oi.order_id = p_order_id
    AND psr.status IN ('reserved','partially_delivered')
    AND psr.delivered_quantity < psr.quantity;

  IF v_pending_reservations > 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'el pedido tiene reservas pendientes; confirma la entrega directa o libera la reserva';
  END IF;

  OPEN cur_items;

  read_loop: LOOP
    FETCH cur_items INTO v_item_id, v_product_id, v_qty;
    IF done = 1 THEN
      LEAVE read_loop;
    END IF;

    SELECT COALESCE(SUM(delivered_quantity), 0)
      INTO v_direct_qty
    FROM production_sale_reservations
    WHERE order_item_id = v_item_id
      AND status = 'delivered';

    SET v_stock_dispatch_qty = GREATEST(v_qty - v_direct_qty, 0);

    IF v_stock_dispatch_qty > 0 THEN
      INSERT IGNORE INTO stock_products (branch_id, product_id, quantity_on_hand, min_stock)
      VALUES (v_branch_id, v_product_id, 0, 0);

      SELECT quantity_on_hand INTO v_stock_qty
      FROM stock_products
      WHERE branch_id = v_branch_id
        AND product_id = v_product_id
      FOR UPDATE;

      IF v_stock_qty < v_stock_dispatch_qty THEN
        SET v_signal_msg = CONCAT('insufficient stock for product_id=', v_product_id);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_signal_msg;
      END IF;

      UPDATE stock_products
      SET quantity_on_hand = quantity_on_hand - v_stock_dispatch_qty,
          updated_at = CURRENT_TIMESTAMP
      WHERE branch_id = v_branch_id
        AND product_id = v_product_id;

      INSERT INTO inventory_movements (
        branch_id, item_type, raw_material_id, product_id, movement_type,
        quantity, unit_cost, reference_type, reference_id, notes, created_by
      ) VALUES (
        v_branch_id, 'product', NULL, v_product_id, 'sale_out',
        v_stock_dispatch_qty, NULL, 'order', p_order_id,
        CONCAT('despacho desde inventario; item ', v_item_id),
        p_actor_user_id
      );
    END IF;

    SET v_dispatched_rows = v_dispatched_rows + 1;
  END LOOP;

  CLOSE cur_items;

  UPDATE orders
  SET status = 'dispatched',
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_order_id;

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_actor_user_id,
    'order.dispatch',
    'orders',
    CAST(p_order_id AS CHAR),
    JSON_OBJECT('dispatched_items', v_dispatched_rows)
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'pedido despachado';
  SET o_data_json = JSON_OBJECT('order_id', p_order_id, 'dispatched_items', v_dispatched_rows);
END $$

DELIMITER ;
