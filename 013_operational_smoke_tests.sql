-- Operational smoke tests (Phase D)
-- Run after:
--   001_init_schema.sql
--   012_operational_procedures.sql

USE panaderia_db;

SET @suffix = DATE_FORMAT(UTC_TIMESTAMP(), '%Y%m%d%H%i%s');

-- =========================
-- 0) Minimal base data
-- =========================

INSERT INTO branches (code, name, is_active)
VALUES (CONCAT('B', RIGHT(@suffix, 6)), CONCAT('Branch ', @suffix), 1);
SET @branch_id = LAST_INSERT_ID();

INSERT INTO tax_rates (code, name, rate_percent, is_active)
VALUES (CONCAT('T', RIGHT(@suffix, 6)), 'Tax Smoke', 19.00, 1);
SET @tax_id = LAST_INSERT_ID();

INSERT INTO product_categories (name, is_active)
VALUES (CONCAT('CatProd ', @suffix), 1);
SET @prod_cat_id = LAST_INSERT_ID();

INSERT INTO products (sku, name, category_id, tax_rate_id, unit, base_price, min_stock, is_active)
VALUES (CONCAT('P', RIGHT(@suffix, 8)), 'Product Smoke', @prod_cat_id, @tax_id, 'unit', 10.00, 0, 1);
SET @product_id = LAST_INSERT_ID();

INSERT INTO customers (tax_id, name, status, credit_limit)
VALUES (CONCAT('C', RIGHT(@suffix, 8)), 'Customer Smoke', 'active', 0);
SET @customer_id = LAST_INSERT_ID();

INSERT INTO raw_material_categories (name, is_active)
VALUES (CONCAT('CatMat ', @suffix), 1);
SET @mat_cat_id = LAST_INSERT_ID();

INSERT INTO suppliers (tax_id, name, status)
VALUES (CONCAT('S', RIGHT(@suffix, 8)), 'Supplier Smoke', 'active');
SET @supplier_id = LAST_INSERT_ID();

INSERT INTO raw_materials (sku, name, category_id, supplier_id, unit, unit_cost, min_stock, is_active)
VALUES (CONCAT('M', RIGHT(@suffix, 8)), 'Material Smoke', @mat_cat_id, @supplier_id, 'kg', 5.0000, 0, 1);
SET @raw_material_id = LAST_INSERT_ID();

-- =========================
-- 1) Cancel order
-- =========================

INSERT INTO orders (branch_id, customer_id, order_date, status, subtotal, tax_total, grand_total)
VALUES (@branch_id, @customer_id, CURRENT_DATE(), 'draft', 0, 0, 0);
SET @order_cancel_id = LAST_INSERT_ID();

CALL sp_cancel_order(@order_cancel_id, 'smoke cancel', NULL, @o_code, @o_message, @o_data_json);
SELECT '1_cancel_order' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '1_order_status' AS test_case, id, status
FROM orders
WHERE id = @order_cancel_id;

-- =========================
-- 2) Receive purchase order
-- =========================

INSERT INTO purchase_orders (
  branch_id, supplier_id, order_date, status, subtotal, tax_total, grand_total
)
VALUES (
  @branch_id, @supplier_id, CURRENT_DATE(), 'sent', 100, 0, 100
);
SET @po_id = LAST_INSERT_ID();

INSERT INTO purchase_order_items (
  purchase_order_id, raw_material_id, quantity, unit_cost, tax_percent, line_subtotal, line_tax, line_total
)
VALUES (
  @po_id, @raw_material_id, 10.000, 5.0000, 0, 50, 0, 50
);

CALL sp_receive_purchase_order(@po_id, NULL, @o_code, @o_message, @o_data_json);
SELECT '2_receive_purchase_order' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '2_po_status' AS test_case, id, status
FROM purchase_orders
WHERE id = @po_id;

SELECT '2_raw_stock_after_receive' AS test_case, branch_id, raw_material_id, quantity_on_hand
FROM stock_raw_materials
WHERE branch_id = @branch_id
  AND raw_material_id = @raw_material_id;

-- =========================
-- 3) Dispatch order
-- =========================

INSERT INTO stock_products (branch_id, product_id, quantity_on_hand, min_stock)
VALUES (@branch_id, @product_id, 20.000, 0)
ON DUPLICATE KEY UPDATE quantity_on_hand = 20.000;

INSERT INTO orders (branch_id, customer_id, order_date, status, subtotal, tax_total, grand_total)
VALUES (@branch_id, @customer_id, CURRENT_DATE(), 'confirmed', 100, 19, 119);
SET @order_dispatch_id = LAST_INSERT_ID();

INSERT INTO order_items (
  order_id, product_id, quantity, unit_price, tax_percent, line_subtotal, line_tax, line_total
)
VALUES (
  @order_dispatch_id, @product_id, 5.000, 20.00, 19.00, 100, 19, 119
);

CALL sp_dispatch_order(@order_dispatch_id, NULL, @o_code, @o_message, @o_data_json);
SELECT '3_dispatch_order' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '3_order_status' AS test_case, id, status
FROM orders
WHERE id = @order_dispatch_id;

SELECT '3_product_stock_after_dispatch' AS test_case, branch_id, product_id, quantity_on_hand
FROM stock_products
WHERE branch_id = @branch_id
  AND product_id = @product_id;

-- =========================
-- 4) Close production order
-- =========================

INSERT INTO production_orders (branch_id, planned_date, status)
VALUES (@branch_id, CURRENT_DATE(), 'in_progress');
SET @prod_order_id = LAST_INSERT_ID();

INSERT INTO production_order_items (production_order_id, product_id, planned_qty, produced_qty, status)
VALUES (@prod_order_id, @product_id, 10.000, 10.000, 'done');

CALL sp_close_production_order(@prod_order_id, NULL, @o_code, @o_message, @o_data_json);
SELECT '4_close_production_order' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '4_production_status' AS test_case, id, status
FROM production_orders
WHERE id = @prod_order_id;
