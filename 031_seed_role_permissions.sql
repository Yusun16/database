-- Default role-permission assignments for IAM bootstrap.
-- Run after:
--   001_init_schema.sql
--   018_rbac_procedures.sql

USE panaderia_db;

INSERT INTO permissions (code, name, description)
VALUES
  ('customers.manage', 'Gestionar clientes', 'Crear, editar y desactivar clientes'),
  ('routes.manage', 'Gestionar rutas', 'Crear, editar y asignar repartidores a rutas')
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  description = VALUES(description);

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.code = 'SUPER_ADMIN';

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN (
    'users.manage',
    'roles.manage',
    'products.manage',
    'materials.manage',
    'customers.manage',
    'routes.manage',
    'recipes.manage',
    'orders.manage',
    'production.manage',
    'inventory.manage',
    'reports.view'
  )
WHERE r.code = 'ADMIN';

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN ('customers.manage', 'routes.manage', 'orders.manage', 'reports.view')
WHERE r.code = 'VENTAS';

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN ('production.manage', 'recipes.manage', 'reports.view')
WHERE r.code = 'PRODUCCION';

INSERT IGNORE INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
INNER JOIN permissions p
  ON p.code IN ('inventory.manage', 'materials.manage', 'products.manage', 'reports.view')
WHERE r.code = 'INVENTARIO';
