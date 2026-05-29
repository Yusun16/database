-- Pidomi Panaderia - Auth and IAM procedures (Sprint 1)
-- MySQL 8+

/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Module            :- IAM / Authentication (Sprint 1)
 * File              :- 004_auth_procedures.sql
 * Standard          :- 025_mysql_sp_architecture_standard.md
 * ---------------------------------------------------------------------------
 * Comment:
 *   Este script implementa los SP base de autenticacion e identidad.
 *
 * Output Contract (todos los SP del archivo):
 *   o_code      : 1 success | 0 business validation | -1 sql exception
 *   o_message   : resumen de resultado
 *   o_data_json : payload JSON de respuesta
 *
 * Notes:
 *   - Hash/verificacion de password vive en backend (no en MySQL).
 *   - Eventos relevantes se registran en audit_logs.
 * --------------------------------------------------------------------------- */

USE panaderia_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_user_create $$
CREATE PROCEDURE sp_user_create(
  IN p_username VARCHAR(60),
  IN p_email VARCHAR(255),
  IN p_password_hash VARCHAR(255),
  IN p_password_algo VARCHAR(30),
  IN p_full_name VARCHAR(150),
  IN p_phone VARCHAR(30),
  IN p_role_code VARCHAR(50),
  IN p_must_change_password TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE v_role_id BIGINT UNSIGNED;
  DECLARE v_user_id BIGINT UNSIGNED;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  SET o_code = 0;
  SET o_message = 'error de validacion';
  SET o_data_json = NULL;

  IF p_username IS NULL OR CHAR_LENGTH(TRIM(p_username)) < 3 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el nombre de usuario (username) debe tener al menos 3 caracteres';
  END IF;

  IF p_email IS NULL OR CHAR_LENGTH(TRIM(p_email)) < 5 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el correo es obligatorio';
  END IF;

  IF p_password_hash IS NULL OR CHAR_LENGTH(p_password_hash) < 40 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el hash de contrasena (password_hash) es invalido';
  END IF;

  IF p_full_name IS NULL OR CHAR_LENGTH(TRIM(p_full_name)) < 3 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el nombre completo es obligatorio';
  END IF;

  START TRANSACTION;

  IF EXISTS (SELECT 1 FROM users WHERE username = p_username) THEN
    SET o_code = 0;
    SET o_message = 'el nombre de usuario ya existe';
    ROLLBACK;
  ELSEIF EXISTS (SELECT 1 FROM users WHERE email = p_email) THEN
    SET o_code = 0;
    SET o_message = 'el correo ya existe';
    ROLLBACK;
  ELSE
    SELECT id INTO v_role_id
    FROM roles
    WHERE code = p_role_code;

    IF v_role_id IS NULL THEN
      SET o_code = 0;
      SET o_message = 'rol no encontrado';
      ROLLBACK;
    ELSE
      INSERT INTO users (
        username,
        email,
        password_hash,
        password_algo,
        full_name,
        phone,
        status,
        must_change_password,
        password_changed_at
      )
      VALUES (
        TRIM(p_username),
        LOWER(TRIM(p_email)),
        p_password_hash,
        IFNULL(p_password_algo, 'argon2id'),
        TRIM(p_full_name),
        p_phone,
        'active',
        IFNULL(p_must_change_password, 1),
        CURRENT_TIMESTAMP
      );

      SET v_user_id = LAST_INSERT_ID();

      INSERT INTO user_roles (user_id, role_id)
      VALUES (v_user_id, v_role_id);

      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        p_actor_user_id,
        'user.create',
        'users',
        CAST(v_user_id AS CHAR),
        JSON_OBJECT('username', p_username, 'email', p_email, 'role_code', p_role_code)
      );

      COMMIT;

      SET o_code = 1;
      SET o_message = 'usuario creado';
      SET o_data_json = JSON_OBJECT('user_id', v_user_id, 'username', p_username, 'email', p_email);
    END IF;
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_user_force_password_reset $$
CREATE PROCEDURE sp_user_force_password_reset(
  IN p_user_id BIGINT UNSIGNED,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  START TRANSACTION;

  UPDATE users
  SET must_change_password = 1,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_user_id
    AND deleted_at IS NULL;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'usuario no encontrado';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (
      p_actor_user_id,
      'user.force_password_reset',
      'users',
      CAST(p_user_id AS CHAR)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'se activo el cambio obligatorio de contrasena';
    SET o_data_json = JSON_OBJECT('user_id', p_user_id, 'must_change_password', 1);
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_auth_login_start $$
CREATE PROCEDURE sp_auth_login_start(
  IN p_identifier VARCHAR(255),
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_user_id BIGINT UNSIGNED;
  DECLARE v_username VARCHAR(60);
  DECLARE v_email VARCHAR(255);
  DECLARE v_password_hash VARCHAR(255);
  DECLARE v_password_algo VARCHAR(30);
  DECLARE v_status VARCHAR(20);
  DECLARE v_must_change_password TINYINT;
  DECLARE v_failed_attempts INT DEFAULT 0;

  SET o_code = 0;
  SET o_message = 'credenciales invalidas';
  SET o_data_json = NULL;

  SELECT
    id,
    username,
    email,
    password_hash,
    password_algo,
    status,
    must_change_password
  INTO
    v_user_id,
    v_username,
    v_email,
    v_password_hash,
    v_password_algo,
    v_status,
    v_must_change_password
  FROM users
  WHERE (username = TRIM(p_identifier) OR email = LOWER(TRIM(p_identifier)))
    AND deleted_at IS NULL
  LIMIT 1;

  IF v_user_id IS NULL THEN
    SET o_code = 0;
    SET o_message = 'credenciales invalidas';
    SET o_data_json = NULL;
  ELSEIF v_status <> 'active' THEN
    SET o_code = 0;
    SET o_message = CONCAT('estado de la cuenta: ', v_status);
    SET o_data_json = NULL;
  ELSE
    SELECT COUNT(*)
      INTO v_failed_attempts
    FROM login_attempts
    WHERE user_id = v_user_id
      AND success = 0
      AND attempted_at >= (CURRENT_TIMESTAMP - INTERVAL 15 MINUTE);

    SET o_code = 1;
    SET o_message = 'datos de validacion de inicio de sesion listos';
    SET o_data_json = JSON_OBJECT(
      'user_id', v_user_id,
      'username', v_username,
      'email', v_email,
      'password_hash', v_password_hash,
      'password_algo', v_password_algo,
      'must_change_password', v_must_change_password,
      'failed_attempts_15m', v_failed_attempts
    );
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_auth_login_fail $$
CREATE PROCEDURE sp_auth_login_fail(
  IN p_identifier VARCHAR(255),
  IN p_user_id BIGINT UNSIGNED,
  IN p_ip_address VARCHAR(45),
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_failed_attempts INT DEFAULT 0;
  DECLARE v_max_attempts INT DEFAULT 5;
  DECLARE v_blocked TINYINT DEFAULT 0;
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  START TRANSACTION;

  INSERT INTO login_attempts (user_id, email_or_username, ip_address, success)
  VALUES (p_user_id, TRIM(p_identifier), p_ip_address, 0);

  IF p_user_id IS NOT NULL THEN
    SELECT COUNT(*)
      INTO v_failed_attempts
    FROM login_attempts
    WHERE user_id = p_user_id
      AND success = 0
      AND attempted_at >= (CURRENT_TIMESTAMP - INTERVAL 15 MINUTE);

    IF v_failed_attempts >= v_max_attempts THEN
      UPDATE users
      SET status = 'blocked',
          updated_at = CURRENT_TIMESTAMP
      WHERE id = p_user_id
        AND status <> 'blocked';

      SET v_blocked = 1;

      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        NULL,
        'auth.account_blocked',
        'users',
        CAST(p_user_id AS CHAR),
        JSON_OBJECT('failed_attempts_15m', v_failed_attempts)
      );
    END IF;
  END IF;

  COMMIT;

  SET o_code = 1;
  IF v_blocked = 1 THEN
    SET o_message = 'inicio de sesion fallido y cuenta bloqueada';
  ELSE
    SET o_message = 'fallo de inicio de sesion registrado';
  END IF;

  SET o_data_json = JSON_OBJECT(
    'failed_attempts_15m', v_failed_attempts,
    'max_attempts_15m', v_max_attempts,
    'account_blocked', v_blocked
  );
END $$


DROP PROCEDURE IF EXISTS sp_auth_login_success $$
CREATE PROCEDURE sp_auth_login_success(
  IN p_user_id BIGINT UNSIGNED,
  IN p_identifier VARCHAR(255),
  IN p_refresh_token_hash CHAR(64),
  IN p_user_agent VARCHAR(255),
  IN p_ip_address VARCHAR(45),
  IN p_expires_at TIMESTAMP,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_must_change_password TINYINT;
  DECLARE v_session_id BIGINT UNSIGNED;
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  START TRANSACTION;

  SELECT status, must_change_password
    INTO v_status, v_must_change_password
  FROM users
  WHERE id = p_user_id
    AND deleted_at IS NULL
  FOR UPDATE;

  IF v_status IS NULL THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'usuario no encontrado';
    SET o_data_json = NULL;
  ELSEIF v_status <> 'active' THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = CONCAT('estado de la cuenta: ', v_status);
    SET o_data_json = NULL;
  ELSE
    INSERT INTO login_attempts (user_id, email_or_username, ip_address, success)
    VALUES (p_user_id, TRIM(p_identifier), p_ip_address, 1);

    UPDATE users
    SET last_login_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_user_id;

    INSERT INTO user_sessions (
      user_id,
      refresh_token_hash,
      user_agent,
      ip_address,
      expires_at,
      revoked_at
    )
    VALUES (
      p_user_id,
      p_refresh_token_hash,
      p_user_agent,
      p_ip_address,
      p_expires_at,
      NULL
    );

    SET v_session_id = LAST_INSERT_ID();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (
      p_user_id,
      'auth.login_success',
      'user_sessions',
      CAST(v_session_id AS CHAR)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'inicio de sesion exitoso registrado';
    SET o_data_json = JSON_OBJECT(
      'session_id', v_session_id,
      'user_id', p_user_id,
      'must_change_password', v_must_change_password
    );
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_auth_refresh_session $$
CREATE PROCEDURE sp_auth_refresh_session(
  IN p_session_id BIGINT UNSIGNED,
  IN p_user_id BIGINT UNSIGNED,
  IN p_current_refresh_hash CHAR(64),
  IN p_new_refresh_hash CHAR(64),
  IN p_new_expires_at TIMESTAMP,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  START TRANSACTION;

  UPDATE user_sessions
  SET refresh_token_hash = p_new_refresh_hash,
      expires_at = p_new_expires_at
  WHERE id = p_session_id
    AND user_id = p_user_id
    AND refresh_token_hash = p_current_refresh_hash
    AND revoked_at IS NULL
    AND expires_at > CURRENT_TIMESTAMP;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'sesion no encontrada, expirada, revocada o con hash no valido';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (
      p_user_id,
      'auth.refresh_session',
      'user_sessions',
      CAST(p_session_id AS CHAR)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'sesion renovada';
    SET o_data_json = JSON_OBJECT('session_id', p_session_id, 'expires_at', p_new_expires_at);
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_auth_logout $$
CREATE PROCEDURE sp_auth_logout(
  IN p_session_id BIGINT UNSIGNED,
  IN p_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_rows INT DEFAULT 0;
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  START TRANSACTION;

  UPDATE user_sessions
  SET revoked_at = CURRENT_TIMESTAMP
  WHERE id = p_session_id
    AND user_id = p_user_id
    AND revoked_at IS NULL;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'sesion no encontrada o ya revocada';
    SET o_data_json = NULL;
  ELSE
    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id)
    VALUES (
      p_user_id,
      'auth.logout',
      'user_sessions',
      CAST(p_session_id AS CHAR)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'sesion revocada';
    SET o_data_json = JSON_OBJECT('session_id', p_session_id, 'revoked', 1);
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_auth_change_password $$
CREATE PROCEDURE sp_auth_change_password(
  IN p_user_id BIGINT UNSIGNED,
  IN p_expected_current_hash VARCHAR(255),
  IN p_new_password_hash VARCHAR(255),
  IN p_new_password_algo VARCHAR(30),
  IN p_revoke_all_sessions TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_current_hash VARCHAR(255);
  DECLARE v_rows INT DEFAULT 0;
  DECLARE v_revoked_count INT DEFAULT 0;
  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
    ROLLBACK;
    SET o_code = -1;
    SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = NULL;
  END;

  IF p_new_password_hash IS NULL OR CHAR_LENGTH(p_new_password_hash) < 40 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el hash de la nueva contrasena es invalido';
  END IF;

  START TRANSACTION;

  SELECT password_hash
    INTO v_current_hash
  FROM users
  WHERE id = p_user_id
    AND deleted_at IS NULL
  FOR UPDATE;

  IF v_current_hash IS NULL THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'usuario no encontrado';
    SET o_data_json = NULL;
  ELSEIF p_expected_current_hash IS NOT NULL AND p_expected_current_hash <> v_current_hash THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'el hash de la contrasena actual no coincide';
    SET o_data_json = NULL;
  ELSE
    UPDATE users
    SET password_hash = p_new_password_hash,
        password_algo = IFNULL(p_new_password_algo, 'argon2id'),
        password_changed_at = CURRENT_TIMESTAMP,
        must_change_password = 0,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_user_id;

    SET v_rows = ROW_COUNT();

    IF IFNULL(p_revoke_all_sessions, 1) = 1 THEN
      UPDATE user_sessions
      SET revoked_at = CURRENT_TIMESTAMP
      WHERE user_id = p_user_id
        AND revoked_at IS NULL;

      SET v_revoked_count = ROW_COUNT();
    END IF;

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'auth.change_password',
      'users',
      CAST(p_user_id AS CHAR),
      JSON_OBJECT('sessions_revoked', v_revoked_count)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'contrasena actualizada';
    SET o_data_json = JSON_OBJECT('user_id', p_user_id, 'sessions_revoked', v_revoked_count, 'updated_rows', v_rows);
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_auth_validate_password_policy $$
CREATE PROCEDURE sp_auth_validate_password_policy(
  IN p_password VARCHAR(255),
  IN p_username VARCHAR(60),
  IN p_email VARCHAR(255),
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_errors JSON DEFAULT JSON_ARRAY();
  DECLARE v_password_lower VARCHAR(255);
  DECLARE v_username_lower VARCHAR(60);
  DECLARE v_email_local VARCHAR(255);
  DECLARE v_password_length INT;

  SET v_password_length = CHAR_LENGTH(p_password);
  SET v_password_lower = LOWER(IFNULL(p_password, ''));
  SET v_username_lower = LOWER(IFNULL(p_username, ''));
  SET v_email_local = LOWER(IFNULL(SUBSTRING_INDEX(p_email, '@', 1), ''));

  IF p_password IS NULL OR v_password_length < 10 THEN
    SET v_errors = JSON_ARRAY_APPEND(v_errors, '$', 'La contraseña debe tener al menos 10 caracteres');
  END IF;

  IF p_password IS NOT NULL AND NOT REGEXP_LIKE(p_password, '[A-Z]') THEN
    SET v_errors = JSON_ARRAY_APPEND(v_errors, '$', 'La contraseña debe contener al menos una letra mayúscula');
  END IF;

  IF p_password IS NOT NULL AND NOT REGEXP_LIKE(p_password, '[a-z]') THEN
    SET v_errors = JSON_ARRAY_APPEND(v_errors, '$', 'La contraseña debe contener al menos una letra minúscula');
  END IF;

  IF p_password IS NOT NULL AND NOT REGEXP_LIKE(p_password, '[0-9]') THEN
    SET v_errors = JSON_ARRAY_APPEND(v_errors, '$', 'La contraseña debe contener al menos un número');
  END IF;

  IF p_password IS NOT NULL AND NOT REGEXP_LIKE(p_password, '[^A-Za-z0-9]') THEN
    SET v_errors = JSON_ARRAY_APPEND(v_errors, '$', 'La contraseña debe contener al menos un carácter especial');
  END IF;

  IF p_password IS NOT NULL AND REGEXP_LIKE(p_password, '[[:space:]]') THEN
    SET v_errors = JSON_ARRAY_APPEND(v_errors, '$', 'La contraseña no puede contener espacios en blanco');
  END IF;

  IF v_username_lower <> '' AND v_password_lower LIKE CONCAT('%', v_username_lower, '%') THEN
    SET v_errors = JSON_ARRAY_APPEND(v_errors, '$', 'La contraseña no puede contener el nombre de usuario');
  END IF;

  IF v_email_local <> '' AND v_password_lower LIKE CONCAT('%', v_email_local, '%') THEN
    SET v_errors = JSON_ARRAY_APPEND(v_errors, '$', 'La contraseña no puede contener la parte local del correo electrónico');
  END IF;

  IF JSON_LENGTH(v_errors) > 0 THEN
    SET o_code = 0;
    SET o_message = 'política de contraseña no cumplida';
    SET o_data_json = JSON_OBJECT('errors', v_errors);
  ELSE
    SET o_code = 1;
    SET o_message = 'contraseña válida';
    SET o_data_json = JSON_OBJECT('valid', TRUE);
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_permission_list_by_user $$
CREATE PROCEDURE sp_permission_list_by_user(
  IN p_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_user_exists INT DEFAULT 0;
  DECLARE v_roles_json LONGTEXT;
  DECLARE v_permissions_json LONGTEXT;

  SELECT COUNT(*)
    INTO v_user_exists
  FROM users
  WHERE id = p_user_id
    AND deleted_at IS NULL;

  IF v_user_exists = 0 THEN
    SET o_code = 0;
    SET o_message = 'usuario no encontrado';
    SET o_data_json = NULL;
  ELSE
    SELECT IFNULL(
             CONCAT('[', GROUP_CONCAT(DISTINCT JSON_QUOTE(r.code) ORDER BY r.code SEPARATOR ','), ']'),
             '[]'
           )
      INTO v_roles_json
    FROM user_roles ur
    INNER JOIN roles r ON r.id = ur.role_id
    WHERE ur.user_id = p_user_id;

    SELECT IFNULL(
             CONCAT('[', GROUP_CONCAT(JSON_QUOTE(x.code) ORDER BY x.code SEPARATOR ','), ']'),
             '[]'
           )
      INTO v_permissions_json
    FROM (
      SELECT DISTINCT p.code
      FROM user_roles ur
      INNER JOIN role_permissions rp ON rp.role_id = ur.role_id
      INNER JOIN permissions p ON p.id = rp.permission_id
      WHERE ur.user_id = p_user_id
      ORDER BY p.code
    ) x;

    SET o_code = 1;
    SET o_message = 'permisos cargados';
    SET o_data_json = CONCAT(
      '{',
      '"user_id":', p_user_id, ',',
      '"roles":', IFNULL(v_roles_json, '[]'), ',',
      '"permissions":', IFNULL(v_permissions_json, '[]'),
      '}'
    );
  END IF;
END $$

DELIMITER ;
