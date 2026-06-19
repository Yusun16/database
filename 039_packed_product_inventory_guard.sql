-- Product inventory is available for sale only after packaging.
-- Run after:
--   038_recipe_versions_and_production_plans.sql

USE panaderia_db;

SET @packing_report_output_unique_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'packing_report_items'
    AND INDEX_NAME = 'uq_packing_report_output'
);

SET @packing_report_output_unique_sql = IF(
  @packing_report_output_unique_exists = 0,
  'ALTER TABLE packing_report_items
     ADD UNIQUE KEY uq_packing_report_output (packing_report_id, production_batch_output_id)',
  'SELECT 1'
);

PREPARE packing_report_output_unique_stmt FROM @packing_report_output_unique_sql;
EXECUTE packing_report_output_unique_stmt;
DEALLOCATE PREPARE packing_report_output_unique_stmt;

SET @production_output_balance_check_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'production_batch_outputs'
    AND CONSTRAINT_NAME = 'chk_production_batch_outputs_balance'
);

SET @production_output_balance_check_sql = IF(
  @production_output_balance_check_exists = 0,
  'ALTER TABLE production_batch_outputs
     ADD CONSTRAINT chk_production_batch_outputs_balance
     CHECK (packed_quantity + damaged_quantity <= produced_quantity)',
  'SELECT 1'
);

PREPARE production_output_balance_check_stmt FROM @production_output_balance_check_sql;
EXECUTE production_output_balance_check_stmt;
DEALLOCATE PREPARE production_output_balance_check_stmt;

DELIMITER $$

DROP TRIGGER IF EXISTS trg_inventory_product_production_in_guard $$
CREATE TRIGGER trg_inventory_product_production_in_guard
BEFORE INSERT ON inventory_movements
FOR EACH ROW
BEGIN
  IF NEW.item_type = 'product'
     AND NEW.movement_type = 'production_in'
     AND COALESCE(NEW.reference_type, '') <> 'packing_report' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'solo los productos empacados pueden ingresar al inventario de venta';
  END IF;
END $$

DELIMITER ;
