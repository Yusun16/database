-- Reporting smoke tests (Phase E)
-- Run after:
--   001_init_schema.sql
--   014_reporting_views.sql

USE panaderia_db;

SET @suffix = DATE_FORMAT(UTC_TIMESTAMP(), '%Y%m%d%H%i%s');

-- =====================================
-- 0) Minimal data for reporting
-- =====================================

INSERT INTO branches (code, name, is_active)
VALUES (CONCAT('RB', RIGHT(@suffix, 6)), CONCAT('Report Branch ', @suffix), 1);
SET @branch_id = LAST_INSERT_ID();

INSERT INTO tax_rates (code, name, rate_percent, is_active)
VALUES (CONCAT('RT', RIGHT(@suffix, 6)), 'Report Tax', 19.00, 1);
SET @tax_id = LAST_INSERT_ID();

INSERT INTO product_categories (name, is_active)
VALUES (CONCAT('Report Prod Cat ', @suffix), 1);
SET @prod_cat_id = LAST_INSERT_ID();

INSERT INTO products (sku, name, category_id, tax_rate_id, unit, base_price, min_stock, is_active)
VALUES (CONCAT('RP', RIGHT(@suffix, 8)), 'Report Product', @prod_cat_id, @tax_id, 'unit', 25.00, 2.000, 1);
SET @product_id = LAST_INSERT_ID();

INSERT INTO customers (tax_id, name, status, credit_limit)
VALUES (CONCAT('RC', RIGHT(@suffix, 8)), 'Report Customer', 'active', 0);
SET @customer_id = LAST_INSERT_ID();

INSERT INTO raw_material_categories (name, is_active)
VALUES (CONCAT('Report Mat Cat ', @suffix), 1);
SET @mat_cat_id = LAST_INSERT_ID();

INSERT INTO suppliers (tax_id, name, status)
VALUES (CONCAT('RS', RIGHT(@suffix, 8)), 'Report Supplier', 'active');
SET @supplier_id = LAST_INSERT_ID();

INSERT INTO raw_materials (sku, name, category_id, supplier_id, unit, unit_cost, min_stock, is_active)
VALUES (CONCAT('RM', RIGHT(@suffix, 8)), 'Report Material', @mat_cat_id, @supplier_id, 'kg', 7.2500, 3.000, 1);
SET @raw_material_id = LAST_INSERT_ID();

INSERT INTO orders (branch_id, customer_id, order_date, status, subtotal, tax_total, grand_total)
VALUES (@branch_id, @customer_id, CURRENT_DATE(), 'dispatched', 100.00, 19.00, 119.00);
SET @order_id = LAST_INSERT_ID();

INSERT INTO order_items (order_id, product_id, quantity, unit_price, tax_percent, line_subtotal, line_tax, line_total)
VALUES (@order_id, @product_id, 4.000, 25.00, 19.00, 100.00, 19.00, 119.00);

INSERT INTO production_orders (branch_id, planned_date, status)
VALUES (@branch_id, CURRENT_DATE(), 'completed');
SET @prod_order_id = LAST_INSERT_ID();

INSERT INTO production_order_items (production_order_id, product_id, planned_qty, produced_qty, status)
VALUES (@prod_order_id, @product_id, 10.000, 9.500, 'done');

INSERT INTO purchase_orders (branch_id, supplier_id, order_date, status, subtotal, tax_total, grand_total)
VALUES (@branch_id, @supplier_id, CURRENT_DATE(), 'received', 50.00, 0.00, 50.00);
SET @po_id = LAST_INSERT_ID();

INSERT INTO purchase_order_items (purchase_order_id, raw_material_id, quantity, unit_cost, tax_percent, line_subtotal, line_tax, line_total)
VALUES (@po_id, @raw_material_id, 10.000, 5.0000, 0, 50.00, 0.00, 50.00);

INSERT INTO stock_raw_materials (branch_id, raw_material_id, quantity_on_hand, min_stock)
VALUES (@branch_id, @raw_material_id, 12.000, 3.000)
ON DUPLICATE KEY UPDATE quantity_on_hand = VALUES(quantity_on_hand), min_stock = VALUES(min_stock);

INSERT INTO stock_products (branch_id, product_id, quantity_on_hand, min_stock)
VALUES (@branch_id, @product_id, 6.000, 2.000)
ON DUPLICATE KEY UPDATE quantity_on_hand = VALUES(quantity_on_hand), min_stock = VALUES(min_stock);

INSERT INTO inventory_movements (
  branch_id, item_type, raw_material_id, product_id, movement_type,
  quantity, unit_cost, reference_type, reference_id, notes, created_by
)
VALUES
(@branch_id, 'raw_material', @raw_material_id, NULL, 'purchase_in', 10.000, 5.0000, 'purchase_order', @po_id, 'report smoke purchase', NULL),
(@branch_id, 'product', NULL, @product_id, 'sale_out', 4.000, NULL, 'order', @order_id, 'report smoke sale', NULL);

INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
VALUES (NULL, 'report.smoke.seed', 'branches', CAST(@branch_id AS CHAR));

-- =====================================
-- 1) Query reporting views
-- =====================================

SELECT '1_vw_sales_daily' AS test_case, v.*
FROM vw_sales_daily v
WHERE v.branch_id = @branch_id
  AND v.order_date = CURRENT_DATE();

SELECT '2_vw_sales_by_customer_daily' AS test_case, v.*
FROM vw_sales_by_customer_daily v
WHERE v.branch_id = @branch_id
  AND v.customer_id = @customer_id
  AND v.order_date = CURRENT_DATE();

SELECT '3_vw_top_products_30d' AS test_case, v.*
FROM vw_top_products_30d v
WHERE v.branch_id = @branch_id
  AND v.product_id = @product_id;

SELECT '4_vw_production_daily' AS test_case, v.*
FROM vw_production_daily v
WHERE v.branch_id = @branch_id
  AND v.planned_date = CURRENT_DATE();

SELECT '5_vw_purchase_daily' AS test_case, v.*
FROM vw_purchase_daily v
WHERE v.branch_id = @branch_id
  AND v.order_date = CURRENT_DATE();

SELECT '6_vw_inventory_current_raw' AS test_case, v.*
FROM vw_inventory_current_raw v
WHERE v.branch_id = @branch_id
  AND v.raw_material_id = @raw_material_id;

SELECT '7_vw_inventory_current_products' AS test_case, v.*
FROM vw_inventory_current_products v
WHERE v.branch_id = @branch_id
  AND v.product_id = @product_id;

SELECT '8_vw_inventory_movements_daily' AS test_case, v.*
FROM vw_inventory_movements_daily v
WHERE v.branch_id = @branch_id
  AND v.moved_date = CURRENT_DATE();

SELECT '9_vw_audit_recent' AS test_case, v.*
FROM vw_audit_recent v
ORDER BY v.id DESC
LIMIT 5;
