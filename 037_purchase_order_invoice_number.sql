-- Purchase invoice number for supplier purchases.
-- Run after:
--   036_raw_material_purchase_package.sql

USE panaderia_db;

SET @purchase_orders_invoice_number_exists = (
  SELECT COUNT(*)
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'purchase_orders'
    AND COLUMN_NAME = 'invoice_number'
);

SET @purchase_orders_invoice_number_sql = IF(
  @purchase_orders_invoice_number_exists = 0,
  'ALTER TABLE purchase_orders ADD COLUMN invoice_number VARCHAR(80) NULL AFTER supplier_id',
  'SELECT 1'
);

PREPARE purchase_orders_invoice_number_stmt FROM @purchase_orders_invoice_number_sql;
EXECUTE purchase_orders_invoice_number_stmt;
DEALLOCATE PREPARE purchase_orders_invoice_number_stmt;
