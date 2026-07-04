-- Restrict the sales role to daily summary, order capture, and returns.
-- Run after:
--   052_customer_neighborhood.sql

USE panaderia_db;

DELETE rp
FROM role_permissions rp
INNER JOIN roles r ON r.id = rp.role_id
INNER JOIN permissions p ON p.id = rp.permission_id
WHERE r.code = 'VENTAS'
  AND p.code <> 'orders.manage'
  AND rp.role_id > 0
  AND rp.permission_id > 0;

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p ON p.code = 'orders.manage'
WHERE r.code = 'VENTAS';
