-- Pidomi Panaderia - Business stored procedures (MySQL 8)
-- Pattern:
--   - Backend sends params via CALL
--   - DB executes validation + transaction
--   - DB returns standardized output through OUT params

/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Module            :- Core Business (Legacy foundation)
 * File              :- 002_business_procedures.sql
 * Standard          :- 025_mysql_sp_architecture_standard.md
 * ---------------------------------------------------------------------------
 * Comment:
 *   Base transaccional inicial de pedidos, compras, produccion e inventario.
 *
 * Output Contract:
 *   General          : o_code, o_message, o_data_json
 *   Legacy exception : sp_create_order mantiene o_order_id (retrocompatibilidad)
 *
 * Notes:
 *   - No se cambia firma legacy sin coordinacion con backend.
 *   - Nuevos SP de este dominio deben usar contrato estandar completo.
 * --------------------------------------------------------------------------- */

USE panaderia_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_create_order $$
CREATE PROCEDURE sp_create_order(
  IN p_branch_id BIGINT UNSIGNED,
  IN p_customer_id BIGINT UNSIGNED,
  IN p_route_id BIGINT UNSIGNED,
  IN p_order_date DATE,
  IN p_delivery_date DATE,
  IN p_notes VARCHAR(255),
  IN p_created_by BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_order_id BIGINT UNSIGNED
)
BEGIN
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_order_id = NULL;
  END;

  SET o_code = 0;
  SET o_message = 'operacion completada';
  SET o_order_id = NULL;

  IF p_order_date IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la fecha de pedido (order_date) es obligatoria';
  END IF;

  START TRANSACTION;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND is_active = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sede no encontrada o inactiva';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM customers WHERE id = p_customer_id AND status = 'active' AND deleted_at IS NULL) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'cliente no encontrado o inactivo';
  END IF;

  IF p_route_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM delivery_routes WHERE id = p_route_id AND is_active = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ruta no encontrada o inactiva';
  END IF;

  INSERT INTO orders (
    branch_id, customer_id, route_id, order_date, delivery_date, status,
    subtotal, tax_total, grand_total, notes, created_by
  )
  VALUES (
    p_branch_id, p_customer_id, p_route_id, p_order_date, p_delivery_date, 'draft',
    0, 0, 0, p_notes, p_created_by
  );

  SET o_order_id = LAST_INSERT_ID();

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_created_by,
    'order.create',
    'orders',
    CAST(o_order_id AS CHAR),
    JSON_OBJECT('branch_id', p_branch_id, 'customer_id', p_customer_id)
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'pedido creado';
END $$


DROP PROCEDURE IF EXISTS sp_order_upsert_item $$
CREATE PROCEDURE sp_order_upsert_item(
  IN p_order_id BIGINT UNSIGNED,
  IN p_product_id BIGINT UNSIGNED,
  IN p_quantity DECIMAL(12,3),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255)
)
BEGIN
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE v_status VARCHAR(30);
  DECLARE v_unit_price DECIMAL(12,2);
  DECLARE v_tax_percent DECIMAL(5,2);
  DECLARE v_subtotal DECIMAL(12,2);
  DECLARE v_tax DECIMAL(12,2);
  DECLARE v_total DECIMAL(12,2);

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
  END;

  SET o_code = 0;
  SET o_message = 'operacion completada';

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cantidad (quantity) debe ser mayor que 0';
  END IF;

  START TRANSACTION;

  SELECT status
    INTO v_status
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'pedido no encontrado';
  END IF;

  IF v_status NOT IN ('draft', 'confirmed') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el estado del pedido no permite cambios de items';
  END IF;

  SELECT p.base_price, t.rate_percent
    INTO v_unit_price, v_tax_percent
  FROM products p
  INNER JOIN tax_rates t ON t.id = p.tax_rate_id
  WHERE p.id = p_product_id
    AND p.is_active = 1
    AND p.deleted_at IS NULL
    AND t.is_active = 1;

  IF v_unit_price IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'producto no encontrado o inactivo';
  END IF;

  SET v_subtotal = ROUND(p_quantity * v_unit_price, 2);
  SET v_tax = ROUND(v_subtotal * (v_tax_percent / 100), 2);
  SET v_total = ROUND(v_subtotal + v_tax, 2);

  INSERT INTO order_items (
    order_id, product_id, quantity, unit_price, tax_percent,
    line_subtotal, line_tax, line_total
  )
  VALUES (
    p_order_id, p_product_id, p_quantity, v_unit_price, v_tax_percent,
    v_subtotal, v_tax, v_total
  )
  ON DUPLICATE KEY UPDATE
    quantity = VALUES(quantity),
    unit_price = VALUES(unit_price),
    tax_percent = VALUES(tax_percent),
    line_subtotal = VALUES(line_subtotal),
    line_tax = VALUES(line_tax),
    line_total = VALUES(line_total);

  UPDATE orders o
  INNER JOIN (
    SELECT
      order_id,
      ROUND(SUM(line_subtotal), 2) AS subtotal,
      ROUND(SUM(line_tax), 2) AS tax_total,
      ROUND(SUM(line_total), 2) AS grand_total
    FROM order_items
    WHERE order_id = p_order_id
    GROUP BY order_id
  ) x ON x.order_id = o.id
  SET
    o.subtotal = x.subtotal,
    o.tax_total = x.tax_total,
    o.grand_total = x.grand_total,
    o.updated_at = CURRENT_TIMESTAMP;

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_actor_user_id,
    'order.item.upsert',
    'orders',
    CAST(p_order_id AS CHAR),
    JSON_OBJECT('product_id', p_product_id, 'quantity', p_quantity)
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'item de pedido insertado o actualizado';
END $$


DROP PROCEDURE IF EXISTS sp_confirm_order $$
CREATE PROCEDURE sp_confirm_order(
  IN p_order_id BIGINT UNSIGNED,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255)
)
BEGIN
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE v_status VARCHAR(30);
  DECLARE v_item_count INT DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
  END;

  SET o_code = 0;
  SET o_message = 'operacion completada';

  START TRANSACTION;

  SELECT status INTO v_status
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'pedido no encontrado';
  END IF;

  IF v_status <> 'draft' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'solo un pedido en borrador puede confirmarse';
  END IF;

  SELECT COUNT(*) INTO v_item_count
  FROM order_items
  WHERE order_id = p_order_id;

  IF v_item_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el pedido no tiene items';
  END IF;

  UPDATE orders
  SET status = 'confirmed', updated_at = CURRENT_TIMESTAMP
  WHERE id = p_order_id;

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
  VALUES (
    p_actor_user_id,
    'order.confirm',
    'orders',
    CAST(p_order_id AS CHAR)
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'pedido confirmado';
END $$


DROP PROCEDURE IF EXISTS sp_apply_inventory_movement $$
CREATE PROCEDURE sp_apply_inventory_movement(
  IN p_branch_id BIGINT UNSIGNED,
  IN p_item_type VARCHAR(20),
  IN p_item_id BIGINT UNSIGNED,
  IN p_movement_type VARCHAR(30),
  IN p_quantity DECIMAL(14,3),
  IN p_unit_cost DECIMAL(12,4),
  IN p_reference_type VARCHAR(50),
  IN p_reference_id BIGINT UNSIGNED,
  IN p_notes VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_movement_id BIGINT UNSIGNED
)
BEGIN
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE v_current_qty DECIMAL(14,3) DEFAULT 0;
  DECLARE v_new_qty DECIMAL(14,3) DEFAULT 0;
  DECLARE v_is_out TINYINT(1) DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_movement_id = NULL;
  END;

  SET o_code = 0;
  SET o_message = 'operacion completada';
  SET o_movement_id = NULL;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la cantidad (quantity) debe ser mayor que 0';
  END IF;

  SET v_is_out = CASE
    WHEN p_movement_type IN ('production_out', 'sale_out', 'adjustment_out', 'waste_out') THEN 1
    ELSE 0
  END;

  START TRANSACTION;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND is_active = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sede no encontrada o inactiva';
  END IF;

  IF p_item_type = 'raw_material' THEN
    IF NOT EXISTS (
      SELECT 1 FROM raw_materials
      WHERE id = p_item_id AND is_active = 1 AND deleted_at IS NULL
    ) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'materia prima no encontrada o inactiva';
    END IF;

    INSERT IGNORE INTO stock_raw_materials (branch_id, raw_material_id, quantity_on_hand, min_stock)
    VALUES (p_branch_id, p_item_id, 0, 0);

    SELECT quantity_on_hand
      INTO v_current_qty
    FROM stock_raw_materials
    WHERE branch_id = p_branch_id
      AND raw_material_id = p_item_id
    FOR UPDATE;

    IF v_is_out = 1 AND v_current_qty < p_quantity THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'stock de materia prima insuficiente';
    END IF;

    SET v_new_qty = CASE WHEN v_is_out = 1 THEN v_current_qty - p_quantity ELSE v_current_qty + p_quantity END;

    UPDATE stock_raw_materials
    SET quantity_on_hand = v_new_qty
    WHERE branch_id = p_branch_id
      AND raw_material_id = p_item_id;

    INSERT INTO inventory_movements (
      branch_id, item_type, raw_material_id, product_id, movement_type,
      quantity, unit_cost, reference_type, reference_id, notes, created_by
    )
    VALUES (
      p_branch_id, 'raw_material', p_item_id, NULL, p_movement_type,
      p_quantity, p_unit_cost, p_reference_type, p_reference_id, p_notes, p_actor_user_id
    );

  ELSEIF p_item_type = 'product' THEN
    IF NOT EXISTS (
      SELECT 1 FROM products
      WHERE id = p_item_id AND is_active = 1 AND deleted_at IS NULL
    ) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'producto no encontrado o inactivo';
    END IF;

    INSERT IGNORE INTO stock_products (branch_id, product_id, quantity_on_hand, min_stock)
    VALUES (p_branch_id, p_item_id, 0, 0);

    SELECT quantity_on_hand
      INTO v_current_qty
    FROM stock_products
    WHERE branch_id = p_branch_id
      AND product_id = p_item_id
    FOR UPDATE;

    IF v_is_out = 1 AND v_current_qty < p_quantity THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'stock de producto insuficiente';
    END IF;

    SET v_new_qty = CASE WHEN v_is_out = 1 THEN v_current_qty - p_quantity ELSE v_current_qty + p_quantity END;

    UPDATE stock_products
    SET quantity_on_hand = v_new_qty
    WHERE branch_id = p_branch_id
      AND product_id = p_item_id;

    INSERT INTO inventory_movements (
      branch_id, item_type, raw_material_id, product_id, movement_type,
      quantity, unit_cost, reference_type, reference_id, notes, created_by
    )
    VALUES (
      p_branch_id, 'product', NULL, p_item_id, p_movement_type,
      p_quantity, p_unit_cost, p_reference_type, p_reference_id, p_notes, p_actor_user_id
    );

  ELSE
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el tipo de item (item_type) es invalido';
  END IF;

  SET o_movement_id = LAST_INSERT_ID();

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_actor_user_id,
    'inventory.movement.apply',
    'inventory_movements',
    CAST(o_movement_id AS CHAR),
    JSON_OBJECT('branch_id', p_branch_id, 'item_type', p_item_type, 'item_id', p_item_id, 'qty', p_quantity)
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'movimiento de inventario aplicado';
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

  SELECT output_quantity
    INTO v_recipe_output_qty
  FROM recipes
  WHERE id = p_recipe_id
    AND product_id = p_product_id
    AND is_active = 1
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
