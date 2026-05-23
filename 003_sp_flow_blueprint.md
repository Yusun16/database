# Flujo maestro de Stored Procedures (prioridad: autenticacion)

Objetivo: definir el orden profesional de implementacion de SP para que el backend solo envie parametros, reciba respuesta estandar y el frontend muestre resultados.

## 1) Contrato estandar de respuesta SP

Todos los SP deben responder por OUT:

- `o_code`:
  - `1` exito
  - `0` validacion de negocio no cumplida
  - `-1` error SQL/tecnico
- `o_message`: mensaje legible para backend/frontend.
- `o_data_json` (opcional): JSON con datos de salida.

Estandar sugerido para toda la plataforma:

- `o_trace_id` (opcional): correlacion para auditoria.

## 2) Fase A - Identidad y acceso (primero)

### A.1 Registro y gestion de usuarios

1. `sp_user_create`
- Crea usuario interno.
- Valida username/email unicos, rol inicial y estado.

2. `sp_user_update_profile`
- Edita nombre, telefono, email, estado.

3. `sp_user_assign_roles`
- Reemplaza roles del usuario en una transaccion.

4. `sp_user_set_status`
- Activa, inactiva o bloquea usuario.

5. `sp_user_force_password_reset`
- Marca `must_change_password = 1`.

### A.2 Credenciales y password

6. `sp_auth_change_password`
- Cambia password autenticado.
- Requiere hash nuevo y fecha de cambio.

7. `sp_auth_reset_password_admin`
- Reset por administrador (sin conocer password anterior).
- Fuerza cambio en siguiente login.

8. `sp_auth_validate_password_policy`
- Opcional: valida politica desde DB y retorna resultado.

### A.3 Login, sesiones y tokens

9. `sp_auth_login_start`
- Busca usuario por username/email.
- Retorna estado de cuenta y hash para validacion en backend.
- Registra intento (aun sin exito).

10. `sp_auth_login_success`
- Registra login exitoso.
- Actualiza `last_login_at`.
- Inserta sesion (`user_sessions`) con `refresh_token_hash`.

11. `sp_auth_login_fail`
- Registra fallo y permite politica de bloqueo por intentos.

12. `sp_auth_refresh_session`
- Rota refresh token hash.
- Extiende expiracion.

13. `sp_auth_logout`
- Revoca sesion actual (`revoked_at`).

14. `sp_auth_logout_all`
- Revoca todas las sesiones activas del usuario.

### A.4 Roles y permisos

15. `sp_role_create`
16. `sp_role_update`
17. `sp_role_set_permissions`
18. `sp_permission_list_by_user`
- Devuelve permisos efectivos del usuario para middleware RBAC.

## 3) Fase B - Catalogos operativos (despues de login)

1. `sp_branch_create`, `sp_branch_update`
2. `sp_tax_rate_create`, `sp_tax_rate_update`
3. `sp_product_category_create`, `sp_product_category_update`
4. `sp_product_create`, `sp_product_update`, `sp_product_set_status`
5. `sp_material_category_create`, `sp_material_category_update`
6. `sp_supplier_create`, `sp_supplier_update`, `sp_supplier_set_status`
7. `sp_raw_material_create`, `sp_raw_material_update`, `sp_raw_material_set_status`
8. `sp_recipe_create`, `sp_recipe_add_item`, `sp_recipe_publish_version`

## 4) Fase C - Clientes y rutas

1. `sp_customer_create`, `sp_customer_update`, `sp_customer_set_status`
2. `sp_route_create`, `sp_route_update`, `sp_route_set_status`
3. `sp_route_assign_driver`

## 5) Fase D - Pedidos, produccion, inventario (ya iniciado)

1. Pedidos: crear, editar items, confirmar, cancelar.
2. Produccion: planificar, registrar resultado, cerrar orden.
3. Inventario: movimientos atomicos y recepcion de compras.

## 6) Secuencia de implementacion recomendada (sprints)

### Sprint 1 (seguridad minima viable)

1. `sp_user_create`
2. `sp_auth_login_start`
3. `sp_auth_login_success`
4. `sp_auth_login_fail`
5. `sp_auth_refresh_session`
6. `sp_auth_logout`
7. `sp_auth_change_password`
8. `sp_user_force_password_reset`
9. `sp_permission_list_by_user`

### Sprint 2 (administracion IAM completa)

1. `sp_user_update_profile`
2. `sp_user_assign_roles`
3. `sp_user_set_status`
4. `sp_role_create`
5. `sp_role_update`
6. `sp_role_set_permissions`
7. `sp_auth_logout_all`
8. `sp_auth_reset_password_admin`

### Sprint 3+ (operacion negocio)

- Catalogos -> clientes/rutas -> pedidos -> produccion -> inventario -> reportes.

## 7) Flujo login-end-to-end (backend simple)

1. Backend llama `sp_auth_login_start(identifier)`.
2. DB responde estado de cuenta + hash almacenado.
3. Backend valida password (Argon2id).
4. Si falla: backend llama `sp_auth_login_fail(...)`.
5. Si ok: backend emite JWT y refresh token, llama `sp_auth_login_success(...)` guardando hash de refresh.
6. Frontend recibe sesion y permisos (via `sp_permission_list_by_user`).

## 8) Politicas de seguridad que deben quedar en SP

1. Bloqueo por intentos fallidos (ventana temporal).
2. Password expirada / cambio forzado.
3. Revocacion de sesiones.
4. Auditoria obligatoria en acciones criticas.
5. Cambios de rol con trazabilidad.

## 9) Regla de oro de arquitectura

- DB: consistencia, transacciones, auditoria, seguridad de datos.
- Backend: autenticacion criptografica, autorizacion por endpoint, validacion de entrada y orquestacion.

No mover criptografia de contrasenas a SQL; mantener Argon2id en Node.
