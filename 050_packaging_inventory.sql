-- Packaging inventory categories and units.
-- Run after:
--   049_product_bag_yields.sql

USE panaderia_db;

ALTER TABLE raw_materials
  MODIFY COLUMN unit ENUM(
    'kg',
    'g',
    'lb',
    'l',
    'ml',
    'unit',
    'package',
    'roll',
    'box',
    'bag'
  ) NOT NULL;

SET @raw_materials_inventory_usage_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'raw_materials'
    AND COLUMN_NAME = 'inventory_usage_type'
);

SET @raw_materials_inventory_usage_sql = IF(
  @raw_materials_inventory_usage_exists = 0,
  'ALTER TABLE raw_materials
     ADD COLUMN inventory_usage_type ENUM(''production'',''packaging'')
       NOT NULL DEFAULT ''production'' AFTER purchase_package_quantity,
     ADD KEY idx_raw_materials_inventory_usage (inventory_usage_type, category_id)',
  'SELECT 1'
);

PREPARE raw_materials_inventory_usage_stmt FROM @raw_materials_inventory_usage_sql;
EXECUTE raw_materials_inventory_usage_stmt;
DEALLOCATE PREPARE raw_materials_inventory_usage_stmt;

INSERT INTO raw_material_categories (name, description, is_active)
VALUES
  ('Rollos', 'Inventario de rollos usados para empaque', 1),
  ('Bolsas', 'Inventario de bolsas usadas para empaque', 1)
ON DUPLICATE KEY UPDATE
  description = VALUES(description),
  is_active = 1;

UPDATE raw_materials rm
INNER JOIN raw_material_categories rmc ON rmc.id = rm.category_id
SET rm.inventory_usage_type = 'packaging'
WHERE rm.id > 0
  AND rmc.name IN ('Rollos', 'Bolsas');
