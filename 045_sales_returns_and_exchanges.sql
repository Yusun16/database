-- Authorized sales returns and product exchanges.
-- Run after:
--   044_seller_customer_assignments.sql

USE panaderia_db;

ALTER TABLE inventory_movements
  MODIFY COLUMN movement_type ENUM(
    'purchase_in',
    'production_in',
    'production_out',
    'sale_out',
    'adjustment_in',
    'adjustment_out',
    'waste_out',
    'return_in',
    'exchange_out'
  ) NOT NULL;

CREATE TABLE IF NOT EXISTS sales_returns (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id BIGINT UNSIGNED NOT NULL,
  sales_agent_user_id BIGINT UNSIGNED NOT NULL,
  status ENUM('pending_authorization','completed','rejected')
    NOT NULL DEFAULT 'pending_authorization',
  reported_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  product_expires_at DATETIME NOT NULL,
  report_deadline_at DATETIME NOT NULL,
  notes VARCHAR(255) NULL,
  authorized_by BIGINT UNSIGNED NULL,
  authorized_at TIMESTAMP NULL,
  rejected_by BIGINT UNSIGNED NULL,
  rejected_at TIMESTAMP NULL,
  rejection_reason VARCHAR(255) NULL,
  created_by BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_sales_returns_order (order_id, status),
  KEY idx_sales_returns_agent (sales_agent_user_id, status, reported_at),
  KEY idx_sales_returns_deadline (report_deadline_at, status),
  CONSTRAINT fk_sales_returns_order
    FOREIGN KEY (order_id) REFERENCES orders (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_sales_returns_agent
    FOREIGN KEY (sales_agent_user_id) REFERENCES users (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_sales_returns_authorized_by
    FOREIGN KEY (authorized_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_sales_returns_rejected_by
    FOREIGN KEY (rejected_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT fk_sales_returns_created_by
    FOREIGN KEY (created_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT chk_sales_returns_dates CHECK (
    report_deadline_at >= product_expires_at
  )
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS sales_return_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sales_return_id BIGINT UNSIGNED NOT NULL,
  order_item_id BIGINT UNSIGNED NOT NULL,
  returned_product_id BIGINT UNSIGNED NOT NULL,
  replacement_product_id BIGINT UNSIGNED NOT NULL,
  reason ENUM('expired','mold','wet','malformed','other') NOT NULL,
  quantity DECIMAL(14,3) NOT NULL,
  returned_sale_value DECIMAL(12,2) NOT NULL DEFAULT 0,
  returned_commercial_value DECIMAL(12,2) NOT NULL DEFAULT 0,
  replacement_commercial_value DECIMAL(12,2) NOT NULL DEFAULT 0,
  notes VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_sales_return_item (
    sales_return_id,
    order_item_id,
    replacement_product_id
  ),
  KEY idx_sales_return_items_order_item (order_item_id),
  KEY idx_sales_return_items_returned_product (returned_product_id),
  KEY idx_sales_return_items_replacement_product (replacement_product_id),
  CONSTRAINT fk_sales_return_items_return
    FOREIGN KEY (sales_return_id) REFERENCES sales_returns (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_sales_return_items_order_item
    FOREIGN KEY (order_item_id) REFERENCES order_items (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_sales_return_items_returned_product
    FOREIGN KEY (returned_product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT fk_sales_return_items_replacement_product
    FOREIGN KEY (replacement_product_id) REFERENCES products (id)
    ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT chk_sales_return_items_values CHECK (
    quantity > 0
    AND returned_sale_value >= 0
    AND returned_commercial_value >= 0
    AND replacement_commercial_value >= 0
  )
) ENGINE=InnoDB;
