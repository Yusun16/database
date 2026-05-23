-- Standardization contract views (procedure contract + naming checks)
-- MySQL 8+

USE panaderia_db;

DROP VIEW IF EXISTS vw_std_procedure_contract_summary;
CREATE VIEW vw_std_procedure_contract_summary AS
SELECT
  p.SPECIFIC_NAME AS procedure_name,
  MAX(CASE WHEN p.PARAMETER_MODE = 'OUT' AND p.PARAMETER_NAME = 'o_code' THEN 1 ELSE 0 END) AS has_o_code,
  MAX(CASE WHEN p.PARAMETER_MODE = 'OUT' AND p.PARAMETER_NAME = 'o_message' THEN 1 ELSE 0 END) AS has_o_message,
  MAX(CASE WHEN p.PARAMETER_MODE = 'OUT' AND p.PARAMETER_NAME = 'o_data_json' THEN 1 ELSE 0 END) AS has_o_data_json
FROM information_schema.PARAMETERS p
WHERE p.SPECIFIC_SCHEMA = DATABASE()
  AND p.SPECIFIC_NAME LIKE 'sp\_%' ESCAPE '\\'
GROUP BY p.SPECIFIC_NAME;

DROP VIEW IF EXISTS vw_std_procedure_contract_violations;
CREATE VIEW vw_std_procedure_contract_violations AS
SELECT
  s.procedure_name,
  s.has_o_code,
  s.has_o_message,
  s.has_o_data_json
FROM vw_std_procedure_contract_summary s
WHERE s.has_o_code = 0
   OR s.has_o_message = 0
   OR s.has_o_data_json = 0;

DROP VIEW IF EXISTS vw_std_procedure_naming_violations;
CREATE VIEW vw_std_procedure_naming_violations AS
SELECT
  r.ROUTINE_NAME AS procedure_name
FROM information_schema.ROUTINES r
WHERE r.ROUTINE_SCHEMA = DATABASE()
  AND r.ROUTINE_TYPE = 'PROCEDURE'
  AND r.ROUTINE_NAME NOT LIKE 'sp\_%' ESCAPE '\\';

DROP VIEW IF EXISTS vw_std_audit_action_naming_issues;
CREATE VIEW vw_std_audit_action_naming_issues AS
SELECT
  al.id,
  al.created_at,
  al.action,
  al.entity_name,
  al.entity_id
FROM audit_logs al
WHERE al.action IS NOT NULL
  AND al.action <> ''
  AND al.action NOT REGEXP '^[a-z]+(\.[a-z_]+)+$';
