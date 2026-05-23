-- Seed user for login tests (backend-compatible bcrypt hash)
-- Run after:
--   001_init_schema.sql
--   004_auth_procedures.sql
--
-- Ejecuta este script sobre el esquema donde tengas cargados los SP
-- (por ejemplo panaderia o panaderia_db).

-- Credenciales de prueba
-- username: qa_login
-- email: qa_login@panaderia.local
-- password (texto plano): Panaderia.2026!

SET @username = 'qa_login';
SET @email = 'qa_login@panaderia.local';
SET @role_code = 'ADMIN';
SET @password_hash = '$2a$10$CX63W8MgVhBGrstrfG1InucVxP1AvwvYE5wH7qcT3s99P6CT6UVEK';

CALL sp_user_create(
  @username,
  @email,
  @password_hash,
  'bcrypt',
  'Usuario QA Login',
  '3000000000',
  @role_code,
  0,
  NULL,
  @o_code,
  @o_message,
  @o_data_json
);

SELECT 'create_user' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;

-- Validacion rapida para confirmar que el usuario es visible para login_start
CALL sp_auth_login_start(@username, @o_code, @o_message, @o_data_json);
SELECT 'login_start_probe' AS test_case, @o_code AS code, @o_message AS message, @o_data_json AS data_json;
