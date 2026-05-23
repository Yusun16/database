-- Read procedures smoke tests
-- Run after:
--   001_init_schema.sql
--   004_auth_procedures.sql
--   008_catalog_procedures.sql
--   010_customer_route_procedures.sql
--   027_read_procedures.sql

USE panaderia_db;

-- -----------------------------------------------------------------------------
-- 1) User detail by id (may return not found depending on seed data)
-- -----------------------------------------------------------------------------
CALL sp_user_get_by_id(1, @o_code, @o_message, @o_data_json);
SELECT '1_user_get_by_id' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- -----------------------------------------------------------------------------
-- 2) User list (page 1)
-- -----------------------------------------------------------------------------
CALL sp_user_list(NULL, NULL, 1, 20, @o_code, @o_message, @o_data_json);
SELECT '2_user_list' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- -----------------------------------------------------------------------------
-- 3) Branch list (all)
-- -----------------------------------------------------------------------------
CALL sp_branch_list(0, @o_code, @o_message, @o_data_json);
SELECT '3_branch_list_all' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- -----------------------------------------------------------------------------
-- 4) Branch list (only active)
-- -----------------------------------------------------------------------------
CALL sp_branch_list(1, @o_code, @o_message, @o_data_json);
SELECT '4_branch_list_active' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- -----------------------------------------------------------------------------
-- 5) Customer list (all)
-- -----------------------------------------------------------------------------
CALL sp_customer_list(NULL, NULL, 1, 20, @o_code, @o_message, @o_data_json);
SELECT '5_customer_list_all' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- -----------------------------------------------------------------------------
-- 6) Customer list with search filter
-- -----------------------------------------------------------------------------
CALL sp_customer_list(NULL, 'demo', 1, 20, @o_code, @o_message, @o_data_json);
SELECT '6_customer_list_search' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- -----------------------------------------------------------------------------
-- 7) Route list with reference date (today)
-- -----------------------------------------------------------------------------
CALL sp_route_list(0, CURRENT_DATE(), @o_code, @o_message, @o_data_json);
SELECT '7_route_list_today' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- -----------------------------------------------------------------------------
-- 8) Product list (active)
-- -----------------------------------------------------------------------------
CALL sp_product_list(1, NULL, NULL, 1, 20, @o_code, @o_message, @o_data_json);
SELECT '8_product_list_active' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- -----------------------------------------------------------------------------
-- 9) Product list with search filter
-- -----------------------------------------------------------------------------
CALL sp_product_list(0, NULL, 'pan', 1, 20, @o_code, @o_message, @o_data_json);
SELECT '9_product_list_search' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- -----------------------------------------------------------------------------
-- 10) Raw material list (active)
-- -----------------------------------------------------------------------------
CALL sp_raw_material_list(1, NULL, NULL, 1, 20, @o_code, @o_message, @o_data_json);
SELECT '10_raw_material_list_active' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- -----------------------------------------------------------------------------
-- 11) Raw material list with search filter
-- -----------------------------------------------------------------------------
CALL sp_raw_material_list(0, NULL, 'harina', 1, 20, @o_code, @o_message, @o_data_json);
SELECT '11_raw_material_list_search' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
