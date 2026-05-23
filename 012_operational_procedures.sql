-- Pidomi Panaderia - Operational procedures (Phase D)
-- MySQL 8+

/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Module            :- Operations (Phase D)
 * File              :- 012_operational_procedures.sql
 * Standard          :- 025_mysql_sp_architecture_standard.md
 * ---------------------------------------------------------------------------
 * Comment:
 *   SP de operacion diaria: cancelacion de pedidos, recepcion de compras,
 *   despacho y cierre de produccion.
 *
 * Output Contract:
 *   o_code      : 1 success | 0 business validation | -1 sql exception
 *   o_message   : summary text
 *   o_data_json : json payload
 * --------------------------------------------------------------------------- */

USE panaderia_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_cancel_order $$
CREATE PROCEDURE sp_cancel_order(
  IN p_order_id BIGINT UNSIGNED,
  IN p_reason VARCHAR(255),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_status VARCHAR(30);
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

  START TRANSACTION;

  SELECT status
    INTO v_status
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'pedido no encontrado';
    SET o_data_json = NULL;
  ELSEIF v_status NOT IN ('draft', 'confirmed') THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = CONCAT('el pedido no se puede cancelar desde el estado ', v_status);
    SET o_data_json = NULL;
  ELSE
    UPDATE orders
    SET status = 'cancelled',
        notes = CONCAT(IFNULL(notes, ''), ' | CANCEL_REASON: ', IFNULL(p_reason, 'not provided')),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_order_id;

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'order.cancel',
      'orders',
      CAST(p_order_id AS CHAR),
      JSON_OBJECT('reason', IFNULL(p_reason, 'not provided'))
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'pedido cancelado';
    SET o_data_json = JSON_OBJECT('order_id', p_order_id, 'status', 'cancelled');
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_receive_purchase_order $$
CREATE PROCEDURE sp_receive_purchase_order(
  IN p_purchase_order_id BIGINT UNSIGNED,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_status VARCHAR(30);
  DECLARE v_branch_id BIGINT UNSIGNED;
  DECLARE v_items_count INT DEFAULT 0;
  DECLARE v_received_rows INT DEFAULT 0;

  DECLARE v_item_id BIGINT UNSIGNED;
  DECLARE v_raw_material_id BIGINT UNSIGNED;
  DECLARE v_qty DECIMAL(12,3);
  DECLARE v_unit_cost DECIMAL(12,4);
  DECLARE done INT DEFAULT 0;

  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE cur_items CURSOR FOR
    SELECT id, raw_material_id, quantity, unit_cost
    FROM purchase_order_items
    WHERE purchase_order_id = p_purchase_order_id;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = 'orden de compra no encontrada';
    SET o_data_json = NULL;
  END;

    SET o_message = CONCAT('la orden de compra no se puede recibir desde el estado ', v_status);

  SELECT status, branch_id
    INTO v_status, v_branch_id
  FROM purchase_orders
  WHERE id = p_purchase_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'orden de compra no encontrada';
    SET o_data_json = NULL;
  ELSEIF v_status NOT IN ('sent', 'partially_received', 'draft') THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = CONCAT('la orden de compra no se puede recibir desde el estado ', v_status);
    SET o_data_json = NULL;
  ELSE
    SELECT COUNT(*)
      INTO v_items_count
    FROM purchase_order_items
    WHERE purchase_order_id = p_purchase_order_id;

    IF v_items_count = 0 THEN
      ROLLBACK;
      SET o_code = 0;
      SET o_message = 'la orden de compra no tiene items';
      SET o_data_json = NULL;
    ELSE
      OPEN cur_items;

      read_loop: LOOP
        FETCH cur_items INTO v_item_id, v_raw_material_id, v_qty, v_unit_cost;
        IF done = 1 THEN
          LEAVE read_loop;
        END IF;

        INSERT IGNORE INTO stock_raw_materials (branch_id, raw_material_id, quantity_on_hand, min_stock)
        VALUES (v_branch_id, v_raw_material_id, 0, 0);

        UPDATE stock_raw_materials
        SET quantity_on_hand = quantity_on_hand + v_qty,
            updated_at = CURRENT_TIMESTAMP
        WHERE branch_id = v_branch_id
          AND raw_material_id = v_raw_material_id;

        INSERT INTO inventory_movements (
          branch_id,
          item_type,
          raw_material_id,
          product_id,
          movement_type,
          quantity,
          unit_cost,
          reference_type,
          reference_id,
          notes,
          created_by
        ) VALUES (
          v_branch_id,
          'raw_material',
          v_raw_material_id,
          NULL,
          'purchase_in',
          v_qty,
          v_unit_cost,
          'purchase_order',
          p_purchase_order_id,
          CONCAT('received from purchase_order_item ', v_item_id),
          p_actor_user_id
        );

        SET v_received_rows = v_received_rows + 1;
      END LOOP;

      CLOSE cur_items;

      UPDATE purchase_orders
      SET status = 'received',
          updated_at = CURRENT_TIMESTAMP
      WHERE id = p_purchase_order_id;

      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        p_actor_user_id,
        'purchase_order.receive',
        'purchase_orders',
        CAST(p_purchase_order_id AS CHAR),
        JSON_OBJECT('received_items', v_received_rows)
      );

      COMMIT;

      SET o_code = 1;
      SET o_message = 'orden de compra recibida';
      SET o_data_json = JSON_OBJECT('purchase_order_id', p_purchase_order_id, 'received_items', v_received_rows);
    END IF;
   END IF;
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

  DECLARE v_item_id BIGINT UNSIGNED;
  DECLARE v_product_id BIGINT UNSIGNED;
  DECLARE v_qty DECIMAL(12,3);
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
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  START TRANSACTION;

  SELECT status, branch_id
    INTO v_status, v_branch_id
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'pedido no encontrado';
    SET o_data_json = NULL;
  ELSEIF v_status NOT IN ('confirmed', 'ready') THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = CONCAT('el pedido no se puede despachar desde el estado ', v_status);
    SET o_data_json = NULL;
  ELSE
    SELECT COUNT(*)
      INTO v_items_count
    FROM order_items
    WHERE order_id = p_order_id;

    IF v_items_count = 0 THEN
      ROLLBACK;
      SET o_code = 0;
      SET o_message = 'el pedido no tiene items';
      SET o_data_json = NULL;
    ELSE
      OPEN cur_items;

      read_loop: LOOP
        FETCH cur_items INTO v_item_id, v_product_id, v_qty;
        IF done = 1 THEN
          LEAVE read_loop;
        END IF;

        INSERT IGNORE INTO stock_products (branch_id, product_id, quantity_on_hand, min_stock)
        VALUES (v_branch_id, v_product_id, 0, 0);

        SELECT quantity_on_hand
          INTO v_stock_qty
        FROM stock_products
        WHERE branch_id = v_branch_id
          AND product_id = v_product_id
        FOR UPDATE;

        IF v_stock_qty < v_qty THEN
          SET v_signal_msg = CONCAT('insufficient stock for product_id=', v_product_id);
          SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_signal_msg;
        END IF;

        UPDATE stock_products
        SET quantity_on_hand = quantity_on_hand - v_qty,
            updated_at = CURRENT_TIMESTAMP
        WHERE branch_id = v_branch_id
          AND product_id = v_product_id;

        INSERT INTO inventory_movements (
          branch_id,
          item_type,
          raw_material_id,
          product_id,
          movement_type,
          quantity,
          unit_cost,
          reference_type,
          reference_id,
          notes,
          created_by
        ) VALUES (
          v_branch_id,
          'product',
          NULL,
          v_product_id,
          'sale_out',
          v_qty,
          NULL,
          'order',
          p_order_id,
          CONCAT('dispatched from order_item ', v_item_id),
          p_actor_user_id
        );

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
    END IF;
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_close_production_order $$
CREATE PROCEDURE sp_close_production_order(
  IN p_production_order_id BIGINT UNSIGNED,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_status VARCHAR(30);
  DECLARE v_pending_items INT DEFAULT 0;

  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = 'orden de produccion no encontrada';
    SET o_data_json = NULL;
  END;

    SET o_message = CONCAT('la orden de produccion ya se encuentra en estado ', v_status);

  SELECT status
    INTO v_status
  FROM production_orders
  WHERE id = p_production_order_id
  FOR UPDATE;

  IF v_status IS NULL THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'orden de produccion no encontrada';
    SET o_data_json = NULL;
  ELSEIF v_status IN ('completed', 'cancelled') THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = CONCAT('la orden de produccion ya se encuentra en estado ', v_status);
    SET o_data_json = NULL;
  ELSE
    SELECT COUNT(*)
      INTO v_pending_items
    FROM production_order_items
    WHERE production_order_id = p_production_order_id
      AND status NOT IN ('done', 'cancelled');

    IF v_pending_items > 0 THEN
      ROLLBACK;
      SET o_code = 0;
      SET o_message = 'la orden de produccion tiene items pendientes';
      SET o_data_json = JSON_OBJECT('pending_items', v_pending_items);
    ELSE
      UPDATE production_orders
      SET status = 'completed',
          updated_at = CURRENT_TIMESTAMP
      WHERE id = p_production_order_id;

      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
      VALUES (
        p_actor_user_id,
        'production_order.close',
        'production_orders',
        CAST(p_production_order_id AS CHAR)
      );

      COMMIT;

      SET o_code = 1;
      SET o_message = 'orden de produccion cerrada';
      SET o_data_json = JSON_OBJECT('production_order_id', p_production_order_id, 'status', 'completed');
    END IF;
  END IF;
END $$

DELIMITER ;
