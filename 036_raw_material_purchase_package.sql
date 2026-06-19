-- Raw material purchase package configuration.
-- Run after:
--   035_production_output_materials.sql

USE panaderia_db;

SET @raw_materials_purchase_package_name_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'raw_materials'
    AND COLUMN_NAME = 'purchase_package_name'
);

SET @raw_materials_purchase_package_name_sql = IF(
  @raw_materials_purchase_package_name_exists = 0,
  'ALTER TABLE raw_materials ADD COLUMN purchase_package_name VARCHAR(60) NULL AFTER unit',
  'SELECT 1'
);

PREPARE raw_materials_purchase_package_name_stmt FROM @raw_materials_purchase_package_name_sql;
EXECUTE raw_materials_purchase_package_name_stmt;
DEALLOCATE PREPARE raw_materials_purchase_package_name_stmt;

SET @raw_materials_purchase_package_quantity_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'raw_materials'
    AND COLUMN_NAME = 'purchase_package_quantity'
);

SET @raw_materials_purchase_package_quantity_sql = IF(
  @raw_materials_purchase_package_quantity_exists = 0,
  'ALTER TABLE raw_materials ADD COLUMN purchase_package_quantity DECIMAL(14,3) NULL AFTER purchase_package_name',
  'SELECT 1'
);

PREPARE raw_materials_purchase_package_quantity_stmt FROM @raw_materials_purchase_package_quantity_sql;
EXECUTE raw_materials_purchase_package_quantity_stmt;
DEALLOCATE PREPARE raw_materials_purchase_package_quantity_stmt;

SET @raw_materials_bag_size_grams_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'raw_materials'
    AND COLUMN_NAME = 'bag_size_grams'
);

SET @raw_materials_copy_bag_size_sql = IF(
  @raw_materials_bag_size_grams_exists = 1,
  'UPDATE raw_materials
   SET purchase_package_name = COALESCE(NULLIF(purchase_package_name, ''''), ''Bulto''),
       purchase_package_quantity = COALESCE(purchase_package_quantity, bag_size_grams)
   WHERE bag_size_grams IS NOT NULL
     AND bag_size_grams > 0
     AND id > 0
     AND (purchase_package_quantity IS NULL OR purchase_package_quantity <= 0)',
  'SELECT 1'
);

PREPARE raw_materials_copy_bag_size_stmt FROM @raw_materials_copy_bag_size_sql;
EXECUTE raw_materials_copy_bag_size_stmt;
DEALLOCATE PREPARE raw_materials_copy_bag_size_stmt;
