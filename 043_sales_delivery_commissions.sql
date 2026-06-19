-- Delivered sales commissions and immutable dispatch boundary.
-- Run after:
--   042_sales_rules_model.sql

USE panaderia_db;

SET @orders_delivery_fields_exist = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'actual_delivered_at'
);

SET @orders_delivery_fields_sql = IF(
  @orders_delivery_fields_exist = 0,
  'ALTER TABLE orders
     ADD COLUMN actual_delivered_at TIMESTAMP NULL AFTER delivery_date,
     ADD COLUMN delivered_by BIGINT UNSIGNED NULL AFTER actual_delivered_at,
     ADD COLUMN commission_base DECIMAL(12,2) NOT NULL DEFAULT 0 AFTER exchange_total,
     ADD COLUMN commission_total DECIMAL(12,2) NOT NULL DEFAULT 0 AFTER commission_base,
     ADD KEY idx_orders_actual_delivery (actual_delivered_at),
     ADD KEY idx_orders_delivered_by (delivered_by),
     ADD CONSTRAINT fk_orders_delivered_by
       FOREIGN KEY (delivered_by) REFERENCES users (id)
       ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);

PREPARE orders_delivery_fields_stmt FROM @orders_delivery_fields_sql;
EXECUTE orders_delivery_fields_stmt;
DEALLOCATE PREPARE orders_delivery_fields_stmt;

CREATE TABLE IF NOT EXISTS sales_commissions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id BIGINT UNSIGNED NOT NULL,
  sales_agent_user_id BIGINT UNSIGNED NOT NULL,
  delivered_sales_total DECIMAL(12,2) NOT NULL,
  returned_sales_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  excluded_bonus_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  excluded_gift_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  excluded_exchange_total DECIMAL(12,2) NOT NULL DEFAULT 0,
  commission_base DECIMAL(12,2) NOT NULL,
  commission_percent DECIMAL(5,2) NOT NULL,
  commission_amount DECIMAL(12,2) NOT NULL,
  status ENUM('accrued','adjusted','cancelled') NOT NULL DEFAULT 'accrued',
  delivered_at TIMESTAMP NOT NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_sales_commissions_order (order_id),
  KEY idx_sales_commissions_agent_date (sales_agent_user_id, delivered_at),
  KEY idx_sales_commissions_status (status),
  CONSTRAINT fk_sales_commissions_order
    FOREIGN KEY (order_id) REFERENCES orders (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_sales_commissions_agent
    FOREIGN KEY (sales_agent_user_id) REFERENCES users (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_sales_commissions_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_sales_commissions_amounts CHECK (
    delivered_sales_total >= 0
    AND returned_sales_total >= 0
    AND excluded_bonus_total >= 0
    AND excluded_gift_total >= 0
    AND excluded_exchange_total >= 0
    AND commission_base >= 0
    AND commission_percent >= 0
    AND commission_percent <= 100
    AND commission_amount >= 0
  )
) ENGINE=InnoDB;
