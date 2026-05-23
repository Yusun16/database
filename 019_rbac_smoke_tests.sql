-- RBAC smoke tests
-- Run after:
--   001_init_schema.sql
--   018_rbac_procedures.sql

USE panaderia_db;

SET @suffix = DATE_FORMAT(UTC_TIMESTAMP(), '%Y%m%d%H%i%s');
SET @role_code = CONCAT('ROLE_', RIGHT(@suffix, 6));
SET @perm1_code = CONCAT('perm.read.', RIGHT(@suffix, 6));
SET @perm2_code = CONCAT('perm.write.', RIGHT(@suffix, 6));

CALL sp_role_create(@role_code, 'Role Smoke', 'Role smoke test', 0, NULL, @o_code, @o_message, @o_data_json);
SELECT '1_role_create' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @role_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.role_id')) AS UNSIGNED);

CALL sp_role_update(@role_id, 'Role Smoke Updated', 'Role smoke updated', NULL, @o_code, @o_message, @o_data_json);
SELECT '2_role_update' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_permission_create(@perm1_code, 'Permission Read Smoke', 'read smoke', NULL, @o_code, @o_message, @o_data_json);
SELECT '3_permission_create_1' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_permission_create(@perm2_code, 'Permission Write Smoke', 'write smoke', NULL, @o_code, @o_message, @o_data_json);
SELECT '4_permission_create_2' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_role_set_permissions(@role_id, JSON_ARRAY(@perm1_code, @perm2_code), NULL, @o_code, @o_message, @o_data_json);
SELECT '5_role_set_permissions' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '6_role_permissions_rows' AS test_case, r.code AS role_code, p.code AS permission_code
FROM role_permissions rp
INNER JOIN roles r ON r.id = rp.role_id
INNER JOIN permissions p ON p.id = rp.permission_id
WHERE rp.role_id = @role_id
ORDER BY p.code;
