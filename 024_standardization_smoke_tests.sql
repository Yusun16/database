-- Standardization smoke tests
-- Run after:
--   001_init_schema.sql
--   022_standardization_baseline.sql
--   023_standardization_contract_views.sql

USE panaderia_db;

CALL sp_std_error_lookup('AUTH.INVALID_CREDENTIALS', @o_code, @o_message, @o_data_json);
SELECT '1_error_lookup_valid' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_std_error_lookup('UNKNOWN.ERROR.CODE', @o_code, @o_message, @o_data_json);
SELECT '2_error_lookup_unknown' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_std_config_get('auth.login.max_attempts_15m', @o_code, @o_message, @o_data_json);
SELECT '3_config_get_valid' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_std_config_get('unknown.config.key', @o_code, @o_message, @o_data_json);
SELECT '4_config_get_unknown' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '5_fn_std_error_json' AS test_case,
       fn_std_error_json('INVENTORY.INSUFFICIENT_STOCK', 'qty requested > qty on hand', JSON_OBJECT('branch_id', 1, 'item_id', 10)) AS payload;

SELECT '6_contract_violations' AS test_case, v.*
FROM vw_std_procedure_contract_violations v
ORDER BY v.procedure_name;

SELECT '7_naming_violations' AS test_case, v.*
FROM vw_std_procedure_naming_violations v
ORDER BY v.procedure_name;

SELECT '8_audit_action_naming_issues' AS test_case, v.*
FROM vw_std_audit_action_naming_issues v
ORDER BY v.id DESC
LIMIT 20;
