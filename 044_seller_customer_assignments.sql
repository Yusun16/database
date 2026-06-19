-- Customers assigned to sales agents.
-- Run after:
--   043_sales_delivery_commissions.sql

USE panaderia_db;

CREATE TABLE IF NOT EXISTS seller_customer_assignments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sales_agent_user_id BIGINT UNSIGNED NOT NULL,
  customer_id BIGINT UNSIGNED NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  assigned_by BIGINT UNSIGNED NULL,
  assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_seller_customer_assignment (sales_agent_user_id, customer_id),
  KEY idx_seller_customer_active (sales_agent_user_id, is_active, customer_id),
  KEY idx_seller_customer_customer (customer_id, is_active),
  CONSTRAINT fk_seller_customer_agent
    FOREIGN KEY (sales_agent_user_id) REFERENCES users (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_seller_customer_customer
    FOREIGN KEY (customer_id) REFERENCES customers (id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT fk_seller_customer_assigned_by
    FOREIGN KEY (assigned_by) REFERENCES users (id)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

INSERT INTO seller_customer_assignments (
  sales_agent_user_id,
  customer_id,
  is_active,
  assigned_by
)
SELECT DISTINCT
  o.sales_agent_user_id,
  o.customer_id,
  1,
  o.created_by
FROM orders o
WHERE o.sales_agent_user_id IS NOT NULL
ON DUPLICATE KEY UPDATE
  is_active = VALUES(is_active);
