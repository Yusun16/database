-- Pidomi Panaderia - Auth admin procedures (Sprint 2)
-- MySQL 8+

/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Module            :- IAM / Auth Administration (Sprint 2)
 * File              :- 006_auth_admin_procedures.sql
 * Standard          :- 025_mysql_sp_architecture_standard.md
 * ---------------------------------------------------------------------------
 * Comment:
 *   SP administrativos de usuarios, roles operativos y control de sesiones.
 *
 * Output Contract:
 *   o_code      : 1 success | 0 business validation | -1 sql exception
 *   o_message   : summary text
 *   o_data_json : json payload
 * --------------------------------------------------------------------------- */

USE panaderia_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_user_update_profile $$
CREATE PROCEDURE sp_user_update_profile(
  IN p_user_id BIGINT UNSIGNED,
  IN p_full_name VARCHAR(150),
  IN p_email VARCHAR(255),
  IN p_phone VARCHAR(30),
  IN p_status VARCHAR(20),
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_exists INT DEFAULT 0;
  DECLARE v_email_conflict INT DEFAULT 0;
  DECLARE v_status_ok INT DEFAULT 0;
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

  SET o_code = 0;
  SET o_message = 'error de validacion';
  SET o_data_json = NULL;

  IF p_full_name IS NULL OR CHAR_LENGTH(TRIM(p_full_name)) < 3 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el nombre completo es obligatorio';
  END IF;

  IF p_email IS NULL OR CHAR_LENGTH(TRIM(p_email)) < 5 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el correo es obligatorio';
  END IF;

  SET v_status_ok = CASE WHEN p_status IN ('active', 'inactive', 'blocked') THEN 1 ELSE 0 END;
  IF v_status_ok = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el estado es invalido';
  END IF;

  START TRANSACTION;

  SELECT COUNT(*) INTO v_exists
  FROM users
  WHERE id = p_user_id
    AND deleted_at IS NULL
  FOR UPDATE;

  IF v_exists = 0 THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'usuario no encontrado';
  ELSE
    SELECT COUNT(*) INTO v_email_conflict
    FROM users
    WHERE email = LOWER(TRIM(p_email))
      AND id <> p_user_id;

    IF v_email_conflict > 0 THEN
      ROLLBACK;
      SET o_code = 0;
      SET o_message = 'el correo ya existe';
    ELSE
      UPDATE users
      SET full_name = TRIM(p_full_name),
          email = LOWER(TRIM(p_email)),
          phone = p_phone,
          status = p_status,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = p_user_id;

      SET v_rows = ROW_COUNT();

      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        p_actor_user_id,
        'user.update_profile',
        'users',
        CAST(p_user_id AS CHAR),
        JSON_OBJECT('status', p_status)
      );

      COMMIT;

      SET o_code = 1;
      SET o_message = 'perfil de usuario actualizado';
      SET o_data_json = JSON_OBJECT('user_id', p_user_id, 'updated_rows', v_rows);
    END IF;
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_user_assign_roles $$
CREATE PROCEDURE sp_user_assign_roles(
  IN p_user_id BIGINT UNSIGNED,
  IN p_role_codes_json JSON,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_user_exists INT DEFAULT 0;
  DECLARE v_input_count INT DEFAULT 0;
  DECLARE v_found_count INT DEFAULT 0;
  DECLARE v_assigned_count INT DEFAULT 0;
  DECLARE v_idx INT DEFAULT 0;
  DECLARE v_role_code VARCHAR(50);

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

  SET o_code = 0;
  SET o_message = 'error de validacion';
  SET o_data_json = NULL;

  IF p_role_codes_json IS NULL OR JSON_VALID(p_role_codes_json) = 0 OR JSON_TYPE(p_role_codes_json) <> 'ARRAY' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el parametro p_role_codes_json debe ser un arreglo JSON valido';
  END IF;

  SET v_input_count = JSON_LENGTH(p_role_codes_json);
  IF v_input_count = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'al menos un rol es obligatorio';
  END IF;

  START TRANSACTION;

  SELECT COUNT(*) INTO v_user_exists
  FROM users
  WHERE id = p_user_id
    AND deleted_at IS NULL
  FOR UPDATE;

  IF v_user_exists = 0 THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'usuario no encontrado';
  ELSE
    DROP TEMPORARY TABLE IF EXISTS tmp_role_codes;
    CREATE TEMPORARY TABLE tmp_role_codes (
      role_code VARCHAR(50) NOT NULL,
      PRIMARY KEY (role_code)
    ) ENGINE=Memory;

    SET v_idx = 0;
    WHILE v_idx < JSON_LENGTH(p_role_codes_json) DO
      SET v_role_code = TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_role_codes_json, CONCAT('$[', v_idx, ']'))));

      IF v_role_code IS NOT NULL AND v_role_code <> '' THEN
        INSERT IGNORE INTO tmp_role_codes (role_code)
        VALUES (v_role_code);
      END IF;

      SET v_idx = v_idx + 1;
    END WHILE;

    SELECT COUNT(*) INTO v_input_count FROM tmp_role_codes;

    SELECT COUNT(*) INTO v_found_count
    FROM tmp_role_codes t
    INNER JOIN roles r ON r.code = t.role_code;

    IF v_input_count <> v_found_count THEN
      ROLLBACK;
      SET o_code = 0;
      SET o_message = 'uno o mas roles no existen';
    ELSE
      DELETE FROM user_roles WHERE user_id = p_user_id;

      INSERT INTO user_roles (user_id, role_id)
      SELECT p_user_id, r.id
      FROM tmp_role_codes t
      INNER JOIN roles r ON r.code = t.role_code;

      SET v_assigned_count = ROW_COUNT();

      INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
      VALUES (
        p_actor_user_id,
        'user.assign_roles',
        'users',
        CAST(p_user_id AS CHAR),
        JSON_OBJECT('roles_count', v_assigned_count)
      );

      COMMIT;

      SET o_code = 1;
      SET o_message = 'roles asignados';
      SET o_data_json = JSON_OBJECT('user_id', p_user_id, 'roles_assigned', v_assigned_count);
    END IF;
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_user_set_status $$
CREATE PROCEDURE sp_user_set_status(
  IN p_user_id BIGINT UNSIGNED,
  IN p_status VARCHAR(20),
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

  IF p_status NOT IN ('active', 'inactive', 'blocked') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'el estado es invalido';
  END IF;

  START TRANSACTION;

  UPDATE users
  SET status = p_status,
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
    IF p_status <> 'active' THEN
      UPDATE user_sessions
      SET revoked_at = CURRENT_TIMESTAMP
      WHERE user_id = p_user_id
        AND revoked_at IS NULL;
    END IF;

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'user.set_status',
      'users',
      CAST(p_user_id AS CHAR),
      JSON_OBJECT('status', p_status)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'estado de usuario actualizado';
    SET o_data_json = JSON_OBJECT('user_id', p_user_id, 'status', p_status);
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_auth_logout_all $$
CREATE PROCEDURE sp_auth_logout_all(
  IN p_user_id BIGINT UNSIGNED,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  DECLARE v_user_exists INT DEFAULT 0;
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

  START TRANSACTION;

  SELECT COUNT(*) INTO v_user_exists
  FROM users
  WHERE id = p_user_id
    AND deleted_at IS NULL
  FOR UPDATE;

  IF v_user_exists = 0 THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'usuario no encontrado';
    SET o_data_json = NULL;
  ELSE
    UPDATE user_sessions
    SET revoked_at = CURRENT_TIMESTAMP
    WHERE user_id = p_user_id
      AND revoked_at IS NULL;

    SET v_revoked_count = ROW_COUNT();

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'auth.logout_all',
      'users',
      CAST(p_user_id AS CHAR),
      JSON_OBJECT('revoked_sessions', v_revoked_count)
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'todas las sesiones activas fueron revocadas';
    SET o_data_json = JSON_OBJECT('user_id', p_user_id, 'revoked_sessions', v_revoked_count);
  END IF;
END $$


DROP PROCEDURE IF EXISTS sp_auth_reset_password_admin $$
CREATE PROCEDURE sp_auth_reset_password_admin(
  IN p_target_user_id BIGINT UNSIGNED,
  IN p_new_password_hash VARCHAR(255),
  IN p_new_password_algo VARCHAR(30),
  IN p_force_change_next_login TINYINT,
  IN p_revoke_all_sessions TINYINT,
  IN p_actor_user_id BIGINT UNSIGNED,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
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

  UPDATE users
  SET password_hash = p_new_password_hash,
      password_algo = IFNULL(p_new_password_algo, 'argon2id'),
      must_change_password = IFNULL(p_force_change_next_login, 1),
      password_changed_at = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
  WHERE id = p_target_user_id
    AND deleted_at IS NULL;

  SET v_rows = ROW_COUNT();

  IF v_rows = 0 THEN
    ROLLBACK;
    SET o_code = 0;
    SET o_message = 'usuario objetivo no encontrado';
    SET o_data_json = NULL;
  ELSE
    IF IFNULL(p_revoke_all_sessions, 1) = 1 THEN
      UPDATE user_sessions
      SET revoked_at = CURRENT_TIMESTAMP
      WHERE user_id = p_target_user_id
        AND revoked_at IS NULL;

      SET v_revoked_count = ROW_COUNT();
    END IF;

    INSERT INTO audit_logs (actor_user_id, action, entity_name, entity_id, metadata_json)
    VALUES (
      p_actor_user_id,
      'auth.reset_password_admin',
      'users',
      CAST(p_target_user_id AS CHAR),
      JSON_OBJECT(
        'force_change_next_login', IFNULL(p_force_change_next_login, 1),
        'sessions_revoked', v_revoked_count
      )
    );

    COMMIT;

    SET o_code = 1;
    SET o_message = 'contrasena restablecida por administrador';
    SET o_data_json = JSON_OBJECT(
      'target_user_id', p_target_user_id,
      'sessions_revoked', v_revoked_count,
      'must_change_password', IFNULL(p_force_change_next_login, 1)
    );
  END IF;
END $$

DELIMITER ;
