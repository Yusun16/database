# Estandar de Arquitectura y Documentacion de SP (MySQL)

Este documento adapta el estilo SQL Server de referencia al stack actual MySQL 8 del proyecto.

## 1) Objetivo

Unificar todos los Stored Procedures en:

- Contrato de salida: `o_code`, `o_message`, `o_data_json`.
- Estructura interna consistente (validaciones, transaccion, errores, auditoria).
- Comentarios tecnicos y bloque de pruebas reproducibles.
- Mensajeria y codigos alineados al catalogo estandar (`std_error_catalog`).

## 2) Convencion de naming

- Procedimiento: `sp_<dominio>_<accion>`
  - Ejemplo: `sp_auth_login_start`, `sp_order_create`.
- Parametros IN: `p_<nombre>`.
- Parametros OUT: `o_code`, `o_message`, `o_data_json`.
- Variables locales: `v_<nombre>`.
- Accion de auditoria: `dominio.recurso.accion` (minusculas, separado por punto).

## 3) Bloque documental obligatorio por SP

Se recomienda iniciar cada SP con este bloque (ajustar valores):

```sql
/* ---------------------------------------------------------------------------
 * Project           :- Panaderia
 * Procedure         :- sp_<dominio>_<accion>
 * Created By        :- <autor>
 * Date              :- <yyyy-mm-dd>
 * Modified By       :- <autor>
 * Modified Date     :- <yyyy-mm-dd>
 * ---------------------------------------------------------------------------
 * Comment:
 *   <descripcion funcional breve>
 *
 * Rules:
 *   1) <regla>
 *   2) <regla>
 *
 * Output Contract:
 *   o_code      : 1 success | 0 business validation | -1 sql exception
 *   o_message   : short human-readable summary
 *   o_data_json : JSON payload (result/metadata/errors)
 *
 * Smoke Test:
 *   CALL sp_<dominio>_<accion>(..., @o_code, @o_message, @o_data_json);
 *   SELECT @o_code, @o_message, @o_data_json;
 * --------------------------------------------------------------------------- */
```

## 4) Estructura tecnica estandar

Orden interno recomendado:

1. Declaracion de variables locales.
2. `EXIT HANDLER FOR SQLEXCEPTION` con `GET DIAGNOSTICS`.
3. Inicializacion de salida default.
4. Validaciones de entrada (sin transaccion si no aplica).
5. `START TRANSACTION`.
6. Logica de negocio transaccional.
7. Insercion de auditoria (`audit_logs`) cuando aplique.
8. `COMMIT` y salida de exito.

## 5) Manejo de errores

### 5.1 Regla de contrato

- `o_code = 1`: ejecucion exitosa.
- `o_code = 0`: error de negocio/validacion.
- `o_code = -1`: error SQL inesperado.

### 5.2 Catalogo estandar

Preferir codigos del catalogo `std_error_catalog` para `o_message` y metadatos.

- Consulta directa: `sp_std_error_lookup`.
- Payload canonico: `fn_std_error_json(error_code, detail, metadata_json)`.

### 5.3 Idioma obligatorio de mensajes

- Todo `o_message` que pueda ser mostrado en frontend debe estar en espanol.
- `default_message` en `std_error_catalog` debe mantenerse en espanol.
- Mensajes tecnicos internos pueden ir en ingles solo en logs de sistema no expuestos a usuario final.

## 6) Validaciones

- Validar campos obligatorios al inicio.
- Normalizar strings con `TRIM()` y `LOWER()` cuando aplique.
- Validar estados permitidos contra catalogos.
- Devolver error de negocio sin lanzar excepcion SQL para reglas esperadas.

## 7) Transacciones

- Usar transaccion para cualquier operacion multi-tabla o con side effects.
- Evitar transacciones para consultas puras de lectura (salvo requerimiento explicito).
- Nunca dejar caminos sin `COMMIT`/`ROLLBACK`.

## 8) Auditoria

Cuando un SP crea, actualiza, cancela, despacha o cambia estado:

- Registrar en `audit_logs`:
  - `actor_user_id`
  - `action`
  - `entity_name`
  - `entity_id`
  - `metadata_json`

## 9) JSON de salida

- `o_data_json` debe ser un objeto JSON valido.
- Para listas, devolver objeto con arreglo interno, por ejemplo:
  - `{ "items": [ ... ], "total": 10 }`
- No mezclar multiples `SELECT` sueltos como salida principal del SP.

## 10) Migracion de patrones SQL Server a MySQL

- `TRY...CATCH` -> `DECLARE EXIT HANDLER FOR SQLEXCEPTION`.
- `RAISERROR` -> `SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = '...'`.
- `ISNULL(x,y)` -> `IFNULL(x,y)`.
- `GETDATE()` -> `CURRENT_TIMESTAMP`.
- `NOLOCK` -> no aplica en MySQL (usar aislamiento/transaccion correcto).
- `FOR JSON PATH` -> `JSON_OBJECT`, `JSON_ARRAYAGG`, `JSON_OBJECTAGG`.

## 11) Checklist de aceptacion para un SP nuevo

- Bloque documental completo.
- Contrato OUT estandar implementado.
- Handler SQL implementado y probado.
- Validaciones de negocio cubiertas.
- Auditoria agregada (si corresponde).
- Smoke test agregado en script `*_smoke_tests.sql`.
- Convenciones de naming sin violaciones (ver vistas 023).
