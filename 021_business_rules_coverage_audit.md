# Auditoria de Cobertura de Reglas de Negocio (DB)

Fecha: 2026-05-14

Alcance evaluado:

- Esquema base y constraints.
- 54 procedimientos almacenados.
- Smoke tests por dominio.

## 1) Resultado ejecutivo

Estado general: COBERTURA ALTA con pendientes puntuales de endurecimiento.

- Identidad y acceso: cubierto.
- Catalogos: cubierto.
- Clientes y rutas: cubierto.
- Operacion principal (pedido/compra/despacho/produccion): cubierto.
- Recetas: cubierto.
- RBAC avanzado: cubierto.
- Reporteria de lectura: cubierto (vistas).

## 2) Matriz por dominio

### IAM y Seguridad

Cubierto:

- Alta de usuario, estado, perfiles, roles.
- Login start/success/fail, bloqueo por intentos.
- Refresh, logout, logout global.
- Cambio y reset de clave.
- Auditoria de acciones criticas.

Riesgo residual:

- `sp_auth_login_start` retorna hash para validar en backend; es valido para arquitectura actual, pero exige control estricto de acceso al endpoint.

### RBAC

Cubierto:

- Alta/edicion de rol.
- Alta de permisos.
- Set masivo de permisos por rol.
- Set masivo de roles por usuario.

Riesgo residual:

- Falta SP dedicado para desactivar/eliminar rol con checks de impacto.

### Catalogos

Cubierto:

- CRUD operativo de sedes, impuestos, categorias, proveedores, productos y materias.
- Activacion/desactivacion en entidades clave.

Riesgo residual:

- No hay historico de cambios de precio/costo (solo audit generico).

### Clientes y rutas

Cubierto:

- CRUD clientes.
- CRUD rutas.
- Asignacion de repartidor con control de traslape.

Riesgo residual:

- No hay SP de cierre de asignacion vigente (actualmente se crea nueva asignacion).

### Operacion

Cubierto:

- Creacion/edicion/confirmacion/cancelacion de pedidos.
- Recepcion de orden de compra e ingreso de stock.
- Despacho de pedido con salida de stock.
- Cierre de orden de produccion.
- Movimiento atomico de inventario con control de negativos.

Riesgo residual:

- No existe SP de devoluciones (venta/compra).
- No existe SP de ajuste masivo por inventario fisico (solo movimiento unitario).

### Recetas y produccion

Cubierto:

- Versionado de receta.
- Items de receta con merma.
- Publicacion de version activa.
- Registro de produccion con consumo y acreditacion de stock.

Riesgo residual:

- No hay workflow de aprobacion de receta (draft/approved) separado.

### Reportes

Cubierto:

- Ventas diarias, por cliente, top productos.
- Produccion diaria.
- Compras diarias.
- Stock actual y movimientos.
- Auditoria reciente.

Riesgo residual:

- Vistas actuales no incluyen seguridad row-level por sede (se controla en backend).

## 3) Reglas criticas validadas

- Integridad referencial por FK: aplicada.
- Validacion de estados de flujo: aplicada en SP principales.
- Control de stock negativo: aplicado en salidas.
- Trazabilidad: audit_logs en cambios clave.
- Transaccionalidad: aplicada en SP de alto impacto.

## 4) Pendientes para nivel enterprise (recomendado)

Prioridad Alta:

1. SP de devolucion de venta (`sale_return_in`) y devolucion a proveedor.
2. SP de cierre de caja/periodo diario por sede (bloqueo de cambios post-cierre).
3. SP de apertura/cierre de jornada con snapshot de stock.

Prioridad Media:

1. Bitacora de cambios de precio/costo con versionado.
2. SP de corte de ruta (finalizar asignacion activa).
3. Politica configurable de bloqueo login (parametrizable por tabla).

Prioridad Baja:

1. Vistas materializadas o tablas de agregados para BI.
2. Catalogo de codigos de error estandarizado para UX.

## 5) Veredicto de cierre DB

Con lo implementado, la DB ya soporta una operacion completa y profesional para el alcance definido.

Criterio de cierre recomendado:

- Ejecutar 100% scripts y smoke tests sin error.
- Ejecutar pruebas de concurrencia minima en:
  - `sp_dispatch_order`
  - `sp_apply_inventory_movement`
  - `sp_register_production_result`
- Definir politicas operativas de pendientes (devoluciones y cierres).
