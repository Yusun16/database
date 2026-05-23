-- Auth smoke tests (Sprint 1)
-- Run after:
--   001_init_schema.sql
--   004_auth_procedures.sql

USE panaderia_db;

-- ==========================
-- 0) Test data preparation
-- ==========================

SET @suffix = DATE_FORMAT(UTC_TIMESTAMP(), '%Y%m%d%H%i%s');
SET @username = CONCAT('smoke_user_', @suffix);
SET @email = CONCAT('smoke_', @suffix, '@example.com');
SET @role_code = 'ADMIN';

-- Fake hashes for smoke test only (real flow validates Argon2id in backend).
SET @hash_v1 = CONCAT('argon2id$smoke$', @suffix, '$v1____________________________');
SET @hash_v2 = CONCAT('argon2id$smoke$', @suffix, '$v2____________________________');
SET @refresh_hash_1 = SHA2(CONCAT('refresh1-', @suffix), 256);
SET @refresh_hash_2 = SHA2(CONCAT('refresh2-', @suffix), 256);
SET @identifier = @username;

-- ==========================
-- 1) Create user
-- ==========================

CALL sp_user_create(
  @username,
  @email,
  @hash_v1,
  'argon2id',
  'Smoke Test User',
  '000000000',
  @role_code,
  1,
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '1_create_user' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SET @user_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.user_id')) AS UNSIGNED);

-- =============================================
-- 2) login_start (should return validation data)
-- =============================================

CALL sp_auth_login_start(@identifier, @o_code, @o_message, @o_data_json);
SELECT '2_login_start' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =============================================
-- 3) login_fail x5 -> account should be blocked
-- =============================================

CALL sp_auth_login_fail(@identifier, @user_id, '127.0.0.1', @o_code, @o_message, @o_data_json);
SELECT '3_login_fail_1' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_auth_login_fail(@identifier, @user_id, '127.0.0.1', @o_code, @o_message, @o_data_json);
SELECT '3_login_fail_2' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_auth_login_fail(@identifier, @user_id, '127.0.0.1', @o_code, @o_message, @o_data_json);
SELECT '3_login_fail_3' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_auth_login_fail(@identifier, @user_id, '127.0.0.1', @o_code, @o_message, @o_data_json);
SELECT '3_login_fail_4' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

CALL sp_auth_login_fail(@identifier, @user_id, '127.0.0.1', @o_code, @o_message, @o_data_json);
SELECT '3_login_fail_5_block' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '3_user_status_after_failures' AS test_case, u.id, u.username, u.status
FROM users u
WHERE u.id = @user_id;

-- =============================================
-- 4) Unblock manually for remaining tests
-- =============================================
-- Note: account unblock admin SP is planned for next sprint.

UPDATE users
SET status = 'active',
    must_change_password = 1,
    updated_at = CURRENT_TIMESTAMP
WHERE id = @user_id;

SELECT '4_user_status_unblocked' AS test_case, u.id, u.username, u.status
FROM users u
WHERE u.id = @user_id;

-- =============================================
-- 5) login_success (register session)
-- =============================================

CALL sp_auth_login_success(
  @user_id,
  @identifier,
  @refresh_hash_1,
  'sql-smoke-agent',
  '127.0.0.1',
  DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 DAY),
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '5_login_success' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @session_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.session_id')) AS UNSIGNED);

-- =============================================
-- 6) Refresh session (token rotation)
-- =============================================

CALL sp_auth_refresh_session(
  @session_id,
  @user_id,
  @refresh_hash_1,
  @refresh_hash_2,
  DATE_ADD(UTC_TIMESTAMP(), INTERVAL 14 DAY),
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '6_refresh_session' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =============================================
-- 7) Load permissions by user
-- =============================================

CALL sp_permission_list_by_user(@user_id, @o_code, @o_message, @o_data_json);
SELECT '7_permissions_by_user' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- =============================================
-- 8) Change password and revoke sessions
-- =============================================

CALL sp_auth_change_password(
  @user_id,
  @hash_v1,
  @hash_v2,
  'argon2id',
  1,
  @user_id,
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '8_change_password' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '8_sessions_after_change_password' AS test_case,
       COUNT(*) AS active_sessions
FROM user_sessions
WHERE user_id = @user_id
  AND revoked_at IS NULL;

-- =============================================
-- 9) New login_success after password change
-- =============================================

SET @refresh_hash_3 = SHA2(CONCAT('refresh3-', @suffix), 256);

CALL sp_auth_login_success(
  @user_id,
  @identifier,
  @refresh_hash_3,
  'sql-smoke-agent',
  '127.0.0.1',
  DATE_ADD(UTC_TIMESTAMP(), INTERVAL 7 DAY),
  @o_code,
  @o_message,
  @o_data_json
);

SELECT '9_login_success_again' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
SET @session_id_2 = CAST(JSON_UNQUOTE(JSON_EXTRACT(@o_data_json, '$.session_id')) AS UNSIGNED);

-- =============================================
-- 10) Logout current session
-- =============================================

CALL sp_auth_logout(@session_id_2, @user_id, @o_code, @o_message, @o_data_json);
SELECT '10_logout' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

SELECT '10_session_status' AS test_case,
       s.id,
       s.user_id,
       s.revoked_at,
       s.expires_at
FROM user_sessions s
WHERE s.id = @session_id_2;
