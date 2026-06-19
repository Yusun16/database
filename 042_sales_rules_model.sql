-- Configurable sales rules and value-based order lines.
-- Run after:
--   041_production_sale_reservations.sql

USE panaderia_db;

CREATE TABLE IF NOT EXISTS sales_settings (
  id TINYINT UNSIGNED NOT NULL,
  bonus_percent DECIMAL(5,2) NOT NULL DEFAULT 20.00,
  bonus_minimum_amount DECIMAL(12,2) NOT NULL DEFAULT 2000.00,
  external_seller_commission_percent DECIMAL(5,2) NOT NULL DEFAULT 15.00,
  updated_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_sales_settings_updated_by
    FOREIGN KEY (updated_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_sales_settings_percentages CHECK (
    bonus_percent >= 0
    AND bonus_percent <= 100
    AND external_seller_commission_percent >= 0
    AND external_seller_commission_percent <= 100
  ),
  CONSTRAINT chk_sales_settings_minimum CHECK (bonus_minimum_amount >= 0)
) ENGINE=InnoDB;

INSERT INTO sales_settings (
  id,
  bonus_percent,
  bonus_minimum_amount,
  external_seller_commission_percent
)
VALUES (1, 20.00, 2000.00, 15.00)
ON DUPLICATE KEY UPDATE id = VALUES(id);

SET @orders_sales_agent_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'sales_agent_user_id'
);

SET @orders_sales_agent_sql = IF(
  @orders_sales_agent_exists = 0,
  'ALTER TABLE orders
     ADD COLUMN sales_agent_user_id BIGINT UNSIGNED NULL AFTER customer_id,
     ADD KEY idx_orders_sales_agent (sales_agent_user_id),
     ADD CONSTRAINT fk_orders_sales_agent
       FOREIGN KEY (sales_agent_user_id) REFERENCES users (id)
       ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);

PREPARE orders_sales_agent_stmt FROM @orders_sales_agent_sql;
EXECUTE orders_sales_agent_stmt;
DEALLOCATE PREPARE orders_sales_agent_stmt;

SET @orders_bonus_percent_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'bonus_percent'
);

SET @orders_bonus_percent_sql = IF(
  @orders_bonus_percent_exists = 0,
  'ALTER TABLE orders
     ADD COLUMN bonus_percent DECIMAL(5,2) NOT NULL DEFAULT 20.00 AFTER grand_total,
     ADD COLUMN bonus_minimum_amount DECIMAL(12,2) NOT NULL DEFAULT 2000.00 AFTER bonus_percent,
     ADD COLUMN seller_commission_percent DECIMAL(5,2) NOT NULL DEFAULT 15.00 AFTER bonus_minimum_amount,
     ADD COLUMN bonus_total DECIMAL(12,2) NOT NULL DEFAULT 0 AFTER seller_commission_percent,
     ADD COLUMN gift_total DECIMAL(12,2) NOT NULL DEFAULT 0 AFTER bonus_total,
     ADD COLUMN exchange_total DECIMAL(12,2) NOT NULL DEFAULT 0 AFTER gift_total',
  'SELECT 1'
);

PREPARE orders_bonus_percent_stmt FROM @orders_bonus_percent_sql;
EXECUTE orders_bonus_percent_stmt;
DEALLOCATE PREPARE orders_bonus_percent_stmt;

UPDATE orders o
INNER JOIN sales_settings ss ON ss.id = 1
SET o.sales_agent_user_id = COALESCE(o.sales_agent_user_id, o.created_by),
    o.bonus_percent = COALESCE(o.bonus_percent, ss.bonus_percent),
    o.bonus_minimum_amount = COALESCE(o.bonus_minimum_amount, ss.bonus_minimum_amount),
    o.seller_commission_percent = COALESCE(
      o.seller_commission_percent,
      ss.external_seller_commission_percent
    )
WHERE o.id > 0;

SET @order_items_line_type_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'order_items'
    AND COLUMN_NAME = 'line_type'
);

SET @order_items_line_type_sql = IF(
  @order_items_line_type_exists = 0,
  'ALTER TABLE order_items
     ADD COLUMN line_type ENUM(''sale'',''bonus'',''gift'',''exchange'')
       NOT NULL DEFAULT ''sale'' AFTER product_id,
     ADD COLUMN capture_mode ENUM(''quantity'',''amount'')
       NOT NULL DEFAULT ''quantity'' AFTER line_type,
     ADD COLUMN requested_amount DECIMAL(12,2) NULL AFTER capture_mode,
     ADD COLUMN commercial_value DECIMAL(12,2) NOT NULL DEFAULT 0 AFTER line_total',
  'SELECT 1'
);

PREPARE order_items_line_type_stmt FROM @order_items_line_type_sql;
EXECUTE order_items_line_type_stmt;
DEALLOCATE PREPARE order_items_line_type_stmt;

UPDATE order_items
SET line_type = COALESCE(line_type, 'sale'),
    capture_mode = COALESCE(capture_mode, 'quantity'),
    commercial_value = CASE
      WHEN commercial_value > 0 THEN commercial_value
      ELSE line_total
    END
WHERE id > 0;

SET @order_items_type_unique_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'order_items'
    AND INDEX_NAME = 'uq_order_items_order_product_type'
);

SET @order_items_type_unique_sql = IF(
  @order_items_type_unique_exists = 0,
  'ALTER TABLE order_items
     ADD UNIQUE KEY uq_order_items_order_product_type (order_id, product_id, line_type)',
  'SELECT 1'
);

PREPARE order_items_type_unique_stmt FROM @order_items_type_unique_sql;
EXECUTE order_items_type_unique_stmt;
DEALLOCATE PREPARE order_items_type_unique_stmt;

SET @order_items_old_unique_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'order_items'
    AND INDEX_NAME = 'uq_order_items_order_product'
);

SET @order_items_drop_old_unique_sql = IF(
  @order_items_old_unique_exists > 0,
  'ALTER TABLE order_items DROP INDEX uq_order_items_order_product',
  'SELECT 1'
);

PREPARE order_items_drop_old_unique_stmt FROM @order_items_drop_old_unique_sql;
EXECUTE order_items_drop_old_unique_stmt;
DEALLOCATE PREPARE order_items_drop_old_unique_stmt;

DROP PROCEDURE IF EXISTS sp_create_order;

DELIMITER $$

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
  DECLARE v_bonus_percent DECIMAL(5,2) DEFAULT 20.00;
  DECLARE v_bonus_minimum DECIMAL(12,2) DEFAULT 2000.00;
  DECLARE v_commission_percent DECIMAL(5,2) DEFAULT 15.00;
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
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_order_id = NULL;
  END;

  SET o_code = 0;
  SET o_message = 'operacion completada';
  SET o_order_id = NULL;

  IF p_order_date IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'la fecha del pedido es obligatoria';
  END IF;

  START TRANSACTION;

  IF NOT EXISTS (SELECT 1 FROM branches WHERE id = p_branch_id AND is_active = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sucursal no encontrada o inactiva';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM customers
    WHERE id = p_customer_id
      AND status = 'active'
      AND deleted_at IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'cliente no encontrado o inactivo';
  END IF;

  IF p_route_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM delivery_routes
    WHERE id = p_route_id
      AND is_active = 1
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ruta no encontrada o inactiva';
  END IF;

  SELECT
    bonus_percent,
    bonus_minimum_amount,
    external_seller_commission_percent
  INTO
    v_bonus_percent,
    v_bonus_minimum,
    v_commission_percent
  FROM sales_settings
  WHERE id = 1;

  INSERT INTO orders (
    branch_id,
    customer_id,
    sales_agent_user_id,
    route_id,
    order_date,
    delivery_date,
    status,
    subtotal,
    tax_total,
    grand_total,
    bonus_percent,
    bonus_minimum_amount,
    seller_commission_percent,
    bonus_total,
    gift_total,
    exchange_total,
    notes,
    created_by
  )
  VALUES (
    p_branch_id,
    p_customer_id,
    p_created_by,
    p_route_id,
    p_order_date,
    p_delivery_date,
    'draft',
    0,
    0,
    0,
    v_bonus_percent,
    v_bonus_minimum,
    v_commission_percent,
    0,
    0,
    0,
    p_notes,
    p_created_by
  );

  SET o_order_id = LAST_INSERT_ID();

  INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
  VALUES (
    p_created_by,
    'order.create',
    'orders',
    CAST(o_order_id AS CHAR),
    JSON_OBJECT(
      'branch_id', p_branch_id,
      'customer_id', p_customer_id,
      'bonus_percent', v_bonus_percent,
      'bonus_minimum_amount', v_bonus_minimum,
      'seller_commission_percent', v_commission_percent
    )
  );

  COMMIT;

  SET o_code = 1;
  SET o_message = 'pedido creado';
END $$

DELIMITER ;
