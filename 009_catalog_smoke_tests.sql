-- Catalog smoke tests (Phase B)
-- Run after:
--   001_init_schema.sql
--   008_catalog_procedures.sql

USE panaderia_db;

SET @suffix = DATE_FORMAT(UTC_TIMESTAMP(), '%Y%m%d%H%i%s');

-- =========================
-- 1) Branch
-- =========================
SET @branch_code = CONCAT('BR', RIGHT(@suffix, 6));

CALL sp_branch_create(@branch_code, 'Sucursal Smoke', 'Calle 123', '555-111', NULL, @o_code, @o_message, @o_data_json);
SELECT '1_branch_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @branch_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.branch_id')) AS UNSIGNED);

CALL sp_branch_update(@branch_id, 'Sucursal Smoke Updated', 'Calle 456', '555-222', 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '1_branch_update' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =========================
-- 2) Tax rate
-- =========================
SET @tax_code = CONCAT('IVA', RIGHT(@suffix, 4));

CALL sp_tax_rate_create(@tax_code, 'IVA Smoke', 19.00, 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '2_tax_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @tax_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.tax_rate_id')) AS UNSIGNED);

CALL sp_tax_rate_update(@tax_id, 'IVA Smoke Updated', 18.00, 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '2_tax_update' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =========================
-- 3) Product category
-- =========================
SET @prod_cat = CONCAT('Panaderia ', @suffix);

CALL sp_product_category_create(@prod_cat, 'Categoria smoke', 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '3_prod_cat_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @prod_cat_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.category_id')) AS UNSIGNED);

CALL sp_product_category_update(@prod_cat_id, CONCAT(@prod_cat, ' U'), 'Categoria smoke updated', 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '3_prod_cat_update' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =========================
-- 4) Raw material category
-- =========================
SET @mat_cat = CONCAT('Insumos ', @suffix);

CALL sp_raw_material_category_create(@mat_cat, 'Categoria insumos smoke', 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '4_mat_cat_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @mat_cat_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.category_id')) AS UNSIGNED);

CALL sp_raw_material_category_update(@mat_cat_id, CONCAT(@mat_cat, ' U'), 'Categoria insumos updated', 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '4_mat_cat_update' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =========================
-- 5) Supplier
-- =========================
SET @supplier_tax = CONCAT('NIT', RIGHT(@suffix, 8));

CALL sp_supplier_create(@supplier_tax, 'Proveedor Smoke', 'proveedor@example.com', '555-333', 'Cra 1', 'Contacto', 'active', NULL, @o_code, @o_message, @o_data_json);
SELECT '5_supplier_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @supplier_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.supplier_id')) AS UNSIGNED);

CALL sp_supplier_update(@supplier_id, @supplier_tax, 'Proveedor Smoke Updated', 'proveedor2@example.com', '555-444', 'Cra 2', 'Contacto U', 'active', NULL, @o_code, @o_message, @o_data_json);
SELECT '5_supplier_update' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =========================
-- 6) Product
-- =========================
SET @product_sku = CONCAT('PROD', RIGHT(@suffix, 8));

CALL sp_product_create(@product_sku, 'Producto Smoke', 'Producto prueba', @prod_cat_id, @tax_id, 'unit', 1500.00, 2.000, 900.000, 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '6_product_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @product_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.product_id')) AS UNSIGNED);

CALL sp_product_update(@product_id, 'Producto Smoke Updated', 'Producto prueba updated', @prod_cat_id, @tax_id, 'unit', 1800.00, 3.000, 950.000, 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '6_product_update' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_product_set_status(@product_id, 0, NULL, @o_code, @o_message, @o_data_json);
SELECT '6_product_set_status' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =========================
-- 7) Raw material
-- =========================
SET @mat_sku = CONCAT('MAT', RIGHT(@suffix, 8));

CALL sp_raw_material_create(@mat_sku, 'Materia Smoke', 'Insumo prueba', @mat_cat_id, @supplier_id, 'kg', 8.2500, 5.000, 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '7_raw_material_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @raw_material_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.raw_material_id')) AS UNSIGNED);

CALL sp_raw_material_update(@raw_material_id, 'Materia Smoke Updated', 'Insumo prueba updated', @mat_cat_id, @supplier_id, 'kg', 9.1500, 6.000, 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '7_raw_material_update' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_raw_material_set_status(@raw_material_id, 0, NULL, @o_code, @o_message, @o_data_json);
SELECT '7_raw_material_set_status' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
