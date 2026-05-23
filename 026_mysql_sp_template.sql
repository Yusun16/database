-- MySQL SP Template (Panaderia)
-- Reusable baseline aligned with project standards.

USE panaderia_db;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_std_template_operation $$
CREATE PROCEDURE sp_std_template_operation(
  IN p_actor_user_id BIGINT UNSIGNED,
  IN p_request_json JSON,
  OUT o_code INT,
  OUT o_message VARCHAR(255),
  OUT o_data_json LONGTEXT
)
BEGIN
  /* ---------------------------------------------------------------------------
   * Project           :- Panaderia
   * Procedure         :- sp_std_template_operation
   * Created By        :- Team
   * Date              :- 2026-05-14
   * Modified By       :-
   * Modified Date     :-
   * ---------------------------------------------------------------------------
   * Comment:
   *   Plantilla base para nuevos SP en MySQL con contrato estandar.
   *
   * Rules:
   *   1) Validar actor y payload.
   *   2) Encapsular logica de negocio en transaccion.
   *   3) Responder por OUT params (sin SELECT principal suelto).
   *
   * Output Contract:
   *   o_code      : 1 success | 0 business validation | -1 sql exception
   *   o_message   : summary text
   *   o_data_json : json payload
   *
   * Smoke Test:
   *   SET @payload = JSON_OBJECT('operation', 'demo', 'entity_ref', 'X-1');
   *   CALL sp_std_template_operation(1, @payload, @o_code, @o_message, @o_data_json);
   *   SELECT @o_code, @o_message, @o_data_json;
   * --------------------------------------------------------------------------- */

  DECLARE v_sqlstate CHAR(5) DEFAULT '00000';
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_errmsg TEXT;

  DECLARE v_operation VARCHAR(80);
  DECLARE v_entity_ref VARCHAR(120);

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1
      v_sqlstate = RETURNED_SQLSTATE,
      v_errno = MYSQL_ERRNO,
      v_errmsg = MESSAGE_TEXT;

    ROLLBACK;

    SET o_code = -1;
      SET o_message = CONCAT('ERROR_SQL ', v_errno, ' ', v_sqlstate, ': ', v_errmsg);
    SET o_data_json = JSON_OBJECT(
      'error_type', 'sql_exception',
      'sqlstate', v_sqlstate,
      'errno', v_errno,
      'detail', v_errmsg
    );
  END;

  SET o_code = 0;
  SET o_message = 'error de validacion';
  SET o_data_json = NULL;

  -- 1) Input validation
  IF p_actor_user_id IS NULL OR p_actor_user_id = 0 THEN
    SET o_code = 0;
    SET o_message = 'el actor_user_id es obligatorio';
    SET o_data_json = JSON_OBJECT('field', 'p_actor_user_id');
  ELSEIF p_request_json IS NULL OR JSON_VALID(p_request_json) = 0 THEN
    SET o_code = 0;
    SET o_message = 'request_json debe ser un JSON valido';
    SET o_data_json = JSON_OBJECT('field', 'p_request_json');
  ELSE
    SET v_operation = JSON_UNQUOTE(JSON_EXTRACT(p_request_json, '$.operation'));
    SET v_entity_ref = JSON_UNQUOTE(JSON_EXTRACT(p_request_json, '$.entity_ref'));

    IF v_operation IS NULL OR CHAR_LENGTH(TRIM(v_operation)) = 0 THEN
      SET o_code = 0;
      SET o_message = 'operation es obligatorio';
      SET o_data_json = JSON_OBJECT('field', '$.operation');
    ELSE
      -- 2) Transactional business block
      START TRANSACTION;

      -- TODO: Implement domain logic here.
      -- TODO: Insert audit row in audit_logs when mutating entities.

      COMMIT;

      SET o_code = 1;
      SET o_message = 'operacion completada';
      SET o_data_json = JSON_OBJECT(
        'operation', v_operation,
        'entity_ref', v_entity_ref,
        'actor_user_id', p_actor_user_id,
        'executed_at', DATE_FORMAT(CURRENT_TIMESTAMP, '%Y-%m-%d %H:%i:%s')
      );
    END IF;
  END IF;
END $$

DELIMITER ;

-- -----------------------------------------------------------------------------
-- Smoke Test
-- -----------------------------------------------------------------------------
-- SET @payload = JSON_OBJECT('operation', 'demo', 'entity_ref', 'X-1');
-- CALL sp_std_template_operation(1, @payload, @o_code, @o_message, @o_data_json);
-- SELECT @o_code AS code, @o_message AS message, @o_data_json AS data_json;
