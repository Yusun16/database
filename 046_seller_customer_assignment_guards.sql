-- One active seller per customer and route module retirement.
-- Run after:
--   045_sales_returns_and_exchanges.sql

USE panaderia_db;

SET @seller_assignment_unassigned_at_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'seller_customer_assignments'
    AND COLUMN_NAME = 'unassigned_at'
);

SET @seller_assignment_history_sql = IF(
  @seller_assignment_unassigned_at_exists = 0,
  'ALTER TABLE seller_customer_assignments
     ADD COLUMN unassigned_by BIGINT UNSIGNED NULL AFTER assigned_by,
     ADD COLUMN unassigned_at TIMESTAMP NULL AFTER assigned_at,
     ADD KEY idx_seller_customer_unassigned_by (unassigned_by),
     ADD CONSTRAINT fk_seller_customer_unassigned_by
       FOREIGN KEY (unassigned_by) REFERENCES users (id)
       ON DELETE SET NULL ON UPDATE CASCADE',
  'SELECT 1'
);

PREPARE seller_assignment_history_stmt FROM @seller_assignment_history_sql;
EXECUTE seller_assignment_history_stmt;
DEALLOCATE PREPARE seller_assignment_history_stmt;

UPDATE seller_customer_assignments sca
INNER JOIN (
  SELECT customer_id, MAX(id) AS keep_id
  FROM seller_customer_assignments
  WHERE is_active = 1
  GROUP BY customer_id
  HAVING COUNT(*) > 1
) duplicated ON duplicated.customer_id = sca.customer_id
SET sca.is_active = 0,
    sca.unassigned_at = COALESCE(sca.unassigned_at, CURRENT_TIMESTAMP)
WHERE sca.id > 0
  AND sca.id <> duplicated.keep_id
  AND sca.is_active = 1;

SET @seller_assignment_active_customer_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'seller_customer_assignments'
    AND COLUMN_NAME = 'active_customer_id'
);

SET @seller_assignment_active_customer_sql = IF(
  @seller_assignment_active_customer_exists = 0,
  'ALTER TABLE seller_customer_assignments
     ADD COLUMN active_customer_id BIGINT UNSIGNED NULL AFTER customer_id',
  'SELECT 1'
);

PREPARE seller_assignment_active_customer_stmt FROM @seller_assignment_active_customer_sql;
EXECUTE seller_assignment_active_customer_stmt;
DEALLOCATE PREPARE seller_assignment_active_customer_stmt;

UPDATE seller_customer_assignments
SET active_customer_id = CASE
  WHEN is_active = 1 THEN customer_id
  ELSE NULL
END
WHERE id > 0;

SET @seller_assignment_active_unique_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'seller_customer_assignments'
    AND INDEX_NAME = 'uq_seller_customer_one_active'
);

SET @seller_assignment_active_unique_sql = IF(
  @seller_assignment_active_unique_exists = 0,
  'ALTER TABLE seller_customer_assignments
     ADD UNIQUE KEY uq_seller_customer_one_active (active_customer_id)',
  'SELECT 1'
);

PREPARE seller_assignment_active_unique_stmt FROM @seller_assignment_active_unique_sql;
EXECUTE seller_assignment_active_unique_stmt;
DEALLOCATE PREPARE seller_assignment_active_unique_stmt;

DELETE rp
FROM role_permissions rp
INNER JOIN roles r ON r.id = rp.role_id
INNER JOIN permissions p ON p.id = rp.permission_id
WHERE r.code = 'VENTAS'
  AND p.code IN ('customers.manage', 'routes.manage')
  AND rp.role_id > 0
  AND rp.permission_id > 0;

DELETE FROM permissions
WHERE code = 'routes.manage';
