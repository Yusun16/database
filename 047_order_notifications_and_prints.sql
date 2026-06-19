-- New order notifications and confirmed print history.
-- Run after:
--   046_seller_customer_assignment_guards.sql

USE panaderia_db;

SET @orders_print_count_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'orders'
    AND COLUMN_NAME = 'print_count'
);

SET @orders_print_fields_sql = IF(
  @orders_print_count_exists = 0,
  'ALTER TABLE orders
     ADD COLUMN print_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER commission_total,
     ADD COLUMN last_printed_at TIMESTAMP NULL AFTER print_count,
     ADD COLUMN last_printed_by BIGINT UNSIGNED NULL AFTER last_printed_at,
     ADD KEY idx_orders_last_printed_by (last_printed_by),
     ADD CONSTRAINT fk_orders_last_printed_by
       FOREIGN KEY (last_printed_by) REFERENCES users (id)
       ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);

PREPARE orders_print_fields_stmt FROM @orders_print_fields_sql;
EXECUTE orders_print_fields_stmt;
DEALLOCATE PREPARE orders_print_fields_stmt;

CREATE TABLE IF NOT EXISTS order_print_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id BIGINT UNSIGNED NOT NULL,
  print_number INT UNSIGNED NOT NULL,
  printed_by BIGINT UNSIGNED NULL,
  confirmed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_order_print_number (order_id, print_number),
  KEY idx_order_print_logs_user_date (printed_by, confirmed_at),
  KEY idx_order_print_logs_date (confirmed_at),
  CONSTRAINT fk_order_print_logs_order
    FOREIGN KEY (order_id) REFERENCES orders (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_order_print_logs_printed_by
    FOREIGN KEY (printed_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_order_print_logs_number CHECK (print_number > 0)
) ENGINE=InnoDB;
