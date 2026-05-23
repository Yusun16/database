-- Customer and route smoke tests (Phase C)
-- Run after:
--   001_init_schema.sql
--   004_auth_procedures.sql
--   010_customer_route_procedures.sql

USE panaderia_db;

SET @suffix = DATE_FORMAT(UTC_TIMESTAMP(), '%Y%m%d%H%i%s');

-- =====================================
-- 1) Create active user to use as driver
-- =====================================
SET @driver_username = CONCAT('driver_smoke_', @suffix);
SET @driver_email = CONCAT('driver_', @suffix, '@example.com');
SET @driver_hash = CONCAT('argon2id$driver$', @suffix, '$v1___________________________');

CALL sp_user_create(
  @driver_username,
  @driver_email,
  @driver_hash,
  'argon2id',
  'Driver Smoke User',
  '5550001',
  'VENTAS',
  0,
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '1_driver_user_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @driver_user_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.user_id')) AS UNSIGNED);

-- =====================================
-- 2) Customer create/update/status
-- =====================================
SET @customer_tax = CONCAT('CC', RIGHT(@suffix, 8));

CALL sp_customer_create(
  @customer_tax,
  'Cliente Smoke',
  'cliente@example.com',
  '3000000000',
  'Dir cliente 123',
  'active',
  100000.00,
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '2_customer_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @customer_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.customer_id')) AS UNSIGNED);

CALL sp_customer_update(
  @customer_id,
  @customer_tax,
  'Cliente Smoke Updated',
  'cliente2@example.com',
  '3110000000',
  'Dir cliente 456',
  'active',
  150000.00,
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '2_customer_update' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_customer_set_status(@customer_id, 'inactive', NULL, @o_code, @o_message, @o_data_json);
SELECT '2_customer_set_status_inactive' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_customer_set_status(@customer_id, 'active', NULL, @o_code, @o_message, @o_data_json);
SELECT '2_customer_set_status_active' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =====================================
-- 3) Route create/update/status
-- =====================================
SET @route_code = CONCAT('R', RIGHT(@suffix, 6));

CALL sp_route_create(@route_code, 'Ruta Smoke', 'Ruta de prueba', 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '3_route_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @route_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.route_id')) AS UNSIGNED);

CALL sp_route_update(@route_id, 'Ruta Smoke Updated', 'Ruta de prueba updated', 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '3_route_update' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =====================================
-- 4) Driver assignment
-- =====================================
CALL sp_route_assign_driver(
  @route_id,
  @driver_user_id,
  CURRENT_DATE(),
  DATE_ADD(CURRENT_DATE(), INTERVAL 7 DAY),
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);
SELECT '4_route_assign_driver' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '4_route_driver_row' AS test_case, rd.id, rd.route_id, rd.user_id, rd.assigned_from, rd.assigned_to
FROM route_drivers rd
WHERE rd.route_id = @route_id
  AND rd.user_id = @driver_user_id
ORDER BY rd.id DESC
LIMIT 1;

-- =====================================
-- 5) Overlap validation (should fail)
-- =====================================
CALL sp_route_assign_driver(
  @route_id,
  @driver_user_id,
  DATE_ADD(CURRENT_DATE(), INTERVAL 1 DAY),
  DATE_ADD(CURRENT_DATE(), INTERVAL 10 DAY),
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);
SELECT '5_route_assign_overlap_expected_fail' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =====================================
-- 6) Route status toggle
-- =====================================
CALL sp_route_set_status(@route_id, 0, NULL, @o_code, @o_message, @o_data_json);
SELECT '6_route_set_status_inactive' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_route_set_status(@route_id, 1, NULL, @o_code, @o_message, @o_data_json);
SELECT '6_route_set_status_active' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
