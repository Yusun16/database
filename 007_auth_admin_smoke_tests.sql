-- Auth admin smoke tests (Sprint 2)
-- Run after:
--   001_init_schema.sql
--   004_auth_procedures.sql
--   006_auth_admin_procedures.sql

USE panaderia_db;

SET @suffix = DATE_FORMAT(UTC_TIMESTAMP(), '%Y%m%d%H%i%s');
SET @username = CONCAT('admin_smoke_user_', @suffix);
SET @email = CONCAT('admin_smoke_', @suffix, '@example.com');
SET @email2 = CONCAT('admin_smoke2_', @suffix, '@example.com');
SET @hash_v1 = CONCAT('argon2id$adminsmoke$', @suffix, '$v1_________________________');
SET @hash_v2 = CONCAT('argon2id$adminsmoke$', @suffix, '$v2_________________________');

-- =====================================
-- 1) Create user for admin smoke tests
-- =====================================

CALL sp_user_create(
  @username,
  @email,
  @hash_v1,
  'argon2id',
  'Admin Smoke User',
  '99999999',
  'VENTAS',
  1,
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '1_create_user' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @user_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.user_id')) AS UNSIGNED);

-- =====================================
-- 2) Update profile
-- =====================================

CALL sp_user_update_profile(
  @user_id,
  'Admin Smoke User Updated',
  @email2,
  '77777777',
  'active',
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '2_update_profile' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SELECT '2_user_after_update' AS test_case, id, username, email, full_name, phone, status
FROM users
WHERE id = @user_id;

-- =====================================
-- 3) Assign roles (array JSON)
-- =====================================

CALL sp_user_assign_roles(
  @user_id,
  JSON_ARRAY('ADMIN', 'VENTAS'),
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '3_assign_roles' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '3_roles_after_assign' AS test_case, r.code AS role_code
FROM user_roles ur
INNER JOIN roles r ON r.id = ur.role_id
WHERE ur.user_id = @user_id
ORDER BY r.code;

-- =====================================
-- 4) Create session then logout_all
-- =====================================

SET @refresh_hash_1 = SHA2(CONCAT('admin-refresh1-', @suffix), 256);
SET @refresh_hash_2 = SHA2(CONCAT('admin-refresh2-', @suffix), 256);

CALL sp_auth_login_success(
  @user_id,
  @username,
  @refresh_hash_1,
  'admin-smoke-agent',
  '127.0.0.1',
  DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 DAY),
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '4_login_success_1' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_auth_login_success(
  @user_id,
  @username,
  @refresh_hash_2,
  'admin-smoke-agent',
  '127.0.0.1',
  DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 DAY),
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '4_login_success_2' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '4_active_sessions_before_logout_all' AS test_case,
       COUNT(*) AS active_sessions
FROM user_sessions
WHERE user_id = @user_id
  AND revoked_at IS NULL;

CALL sp_auth_logout_all(@user_id, NULL, @o_code, @o_message, @o_data_json);
SELECT '4_logout_all' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '4_active_sessions_after_logout_all' AS test_case,
       COUNT(*) AS active_sessions
FROM user_sessions
WHERE user_id = @user_id
  AND revoked_at IS NULL;

-- =====================================
-- 5) Reset password by admin
-- =====================================

CALL sp_auth_reset_password_admin(
  @user_id,
  @hash_v2,
  'argon2id',
  1,
  1,
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '5_reset_password_admin' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '5_user_after_reset' AS test_case,
       id,
       must_change_password,
       password_algo,
       password_changed_at
FROM users
WHERE id = @user_id;

-- =====================================
-- 6) set_status inactive (must revoke sessions)
-- =====================================

SET @refresh_hash_3 = SHA2(CONCAT('admin-refresh3-', @suffix), 256);

CALL sp_auth_login_success(
  @user_id,
  @username,
  @refresh_hash_3,
  'admin-smoke-agent',
  '127.0.0.1',
  DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 DAY),
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '6_login_success_before_inactive' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '6_active_sessions_before_inactive' AS test_case,
       COUNT(*) AS active_sessions
FROM user_sessions
WHERE user_id = @user_id
  AND revoked_at IS NULL;

CALL sp_user_set_status(@user_id, 'inactive', NULL, @o_code, @o_message, @o_data_json);
SELECT '6_set_status_inactive' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '6_user_after_inactive' AS test_case, id, status
FROM users
WHERE id = @user_id;

SELECT '6_active_sessions_after_inactive' AS test_case,
       COUNT(*) AS active_sessions
FROM user_sessions
WHERE user_id = @user_id
  AND revoked_at IS NULL;
