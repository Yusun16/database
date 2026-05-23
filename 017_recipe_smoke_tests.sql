-- Recipe smoke tests
-- Run after:
--   001_init_schema.sql
--   016_recipe_procedures.sql

USE panaderia_db;

SET @suffix = DATE_FORMAT(UTC_TIMESTAMP(), '%Y%m%d%H%i%s');

-- Base data
INSERT INTO tax_rates (code, name, rate_percent, is_active)
VALUES (CONCAT('RT', RIGHT(@suffix, 6)), 'Tax Recipe', 19.00, 1);
SET @tax_id = LAST_INSERT_ID();

INSERT INTO product_categories (name, is_active)
VALUES (CONCAT('Recipe Cat ', @suffix), 1);
SET @prod_cat_id = LAST_INSERT_ID();

INSERT INTO products (sku, name, category_id, tax_rate_id, unit, base_price, min_stock, is_active)
VALUES (CONCAT('RCP', RIGHT(@suffix, 8)), 'Recipe Product', @prod_cat_id, @tax_id, 'unit', 15.00, 1.000, 1);
SET @product_id = LAST_INSERT_ID();

INSERT INTO raw_material_categories (name, is_active)
VALUES (CONCAT('Recipe Mat Cat ', @suffix), 1);
SET @mat_cat_id = LAST_INSERT_ID();

INSERT INTO suppliers (tax_id, name, status)
VALUES (CONCAT('RS', RIGHT(@suffix, 8)), 'Recipe Supplier', 'active');
SET @supplier_id = LAST_INSERT_ID();

INSERT INTO raw_materials (sku, name, category_id, supplier_id, unit, unit_cost, min_stock, is_active)
VALUES
(CONCAT('RM1', RIGHT(@suffix, 6)), 'Flour', @mat_cat_id, @supplier_id, 'kg', 4.5000, 1.000, 1),
(CONCAT('RM2', RIGHT(@suffix, 6)), 'Sugar', @mat_cat_id, @supplier_id, 'kg', 3.2500, 1.000, 1);

SELECT id INTO @rm1_id FROM raw_materials WHERE name = 'Flour' ORDER BY id DESC LIMIT 1;
SELECT id INTO @rm2_id FROM raw_materials WHERE name = 'Sugar' ORDER BY id DESC LIMIT 1;

CALL sp_recipe_create(@product_id, 10.000, 'base recipe', NULL, @o_code, @o_message, @o_data_json);
SELECT '1_recipe_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @recipe_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.recipe_id')) AS UNSIGNED);

CALL sp_recipe_add_item(@recipe_id, @rm1_id, 5.0000, 2.00, NULL, @o_code, @o_message, @o_data_json);
SELECT '2_recipe_add_item_rm1' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_recipe_add_item(@recipe_id, @rm2_id, 2.0000, 1.50, NULL, @o_code, @o_message, @o_data_json);
SELECT '3_recipe_add_item_rm2' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_recipe_remove_item(@recipe_id, @rm2_id, NULL, @o_code, @o_message, @o_data_json);
SELECT '4_recipe_remove_item_rm2' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_recipe_add_item(@recipe_id, @rm2_id, 1.5000, 1.00, NULL, @o_code, @o_message, @o_data_json);
SELECT '5_recipe_readd_item_rm2' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_recipe_publish_version(@recipe_id, NULL, @o_code, @o_message, @o_data_json);
SELECT '6_recipe_publish' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '7_recipe_rows' AS test_case, r.id, r.product_id, r.version_no, r.output_quantity, r.is_active
FROM recipes r
WHERE r.product_id = @product_id
ORDER BY r.version_no;

SELECT '8_recipe_items' AS test_case, ri.recipe_id, ri.raw_material_id, ri.quantity, ri.wastage_percent
FROM recipe_items ri
WHERE ri.recipe_id = @recipe_id
ORDER BY ri.raw_material_id;
