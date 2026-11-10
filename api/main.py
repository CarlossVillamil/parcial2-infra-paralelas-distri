"""
API REST - Parcial II Infraestructuras Paralelas y Distribuidas (Univalle)
CRUD de estudiantes sobre PostgreSQL + endpoints de salud para Kubernetes.

Endpoints:
  GET    /health              -> liveness  (no toca la BD)
  GET    /health/ready        -> readiness (SELECT 1 contra la BD; 200 o 503)
  GET    /estudiantes
  GET    /estudiantes/{id}
  POST   /estudiantes
  PUT    /estudiantes/{id}
  DELETE /estudiantes/{id}

Todas las respuestas llevan el header X-Pod-Name con el nombre del Pod que atendió.
"""
import logging
import os
import socket
import threading
import time
from contextlib import asynccontextmanager, contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("parcial2-api")


class _SinHealthFilter(logging.Filter):
    """Oculta del access log las llamadas de las probes (cada 5-10 s ensucian los logs)."""

    def filter(self, record: logging.LogRecord) -> bool:
        return "/health" not in record.getMessage()


logging.getLogger("uvicorn.access").addFilter(_SinHealthFilter())

# En Kubernetes el hostname del contenedor es el nombre del Pod.
POD_NAME = socket.gethostname()

# Conexión leída de variables de entorno (las credenciales vienen del Secret).
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "parcialdb"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", ""),
    "connect_timeout": 2,  # menor que el timeoutSeconds de la readinessProbe
}

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS estudiantes (
    id         SERIAL PRIMARY KEY,
    nombre     VARCHAR(100) NOT NULL,
    email      VARCHAR(150) NOT NULL UNIQUE,
    creado_en  TIMESTAMP NOT NULL DEFAULT NOW()
)
"""
COLS = "id, nombre, email, creado_en"

tabla_lista = threading.Event()


@contextmanager
def get_conn():
    """Una conexión por petición: si Postgres se cae y vuelve, la API se recupera sola."""
    conn = psycopg2.connect(**DB_CONFIG)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def asegurar_tabla() -> None:
    if tabla_lista.is_set():
        return
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute(CREATE_TABLE_SQL)
    tabla_lista.set()
    log.info(
        "Conexion a la BD exitosa (%s:%s/%s). Tabla 'estudiantes' lista.",
        DB_CONFIG["host"], DB_CONFIG["port"], DB_CONFIG["dbname"],
    )


def inicializar_en_segundo_plano() -> None:
    """Reintenta crear la tabla sin tumbar el proceso si la BD aún no está disponible."""
    while not tabla_lista.is_set():
        try:
            asegurar_tabla()
        except Exception as exc:  # noqa: BLE001
            log.warning("BD no disponible todavia (%s). Reintento en 5 s.", str(exc).strip())
            time.sleep(5)


@asynccontextmanager
async def lifespan(_: FastAPI):
    log.info(
        "API iniciando en el pod %s. BD destino: %s:%s/%s",
        POD_NAME, DB_CONFIG["host"], DB_CONFIG["port"], DB_CONFIG["dbname"],
    )
    threading.Thread(target=inicializar_en_segundo_plano, daemon=True).start()
    yield


app = FastAPI(title="Parcial II - API Estudiantes", version="1.0", lifespan=lifespan)


@app.middleware("http")
async def agregar_header_pod(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Pod-Name"] = POD_NAME
    return response


@app.exception_handler(psycopg2.OperationalError)
async def bd_no_disponible(_: Request, exc: psycopg2.OperationalError):
    return JSONResponse(
        status_code=503,
        content={"detail": "Base de datos no disponible", "error": str(exc).strip(), "pod": POD_NAME},
    )


# ---------------------------------------------------------------- salud
@app.get("/health")
def liveness():
    # NO consulta la BD: si Postgres cae, no queremos que Kubernetes reinicie la API.
    return {"status": "ok", "pod": POD_NAME}


@app.get("/health/ready")
def readiness():
    try:
        with get_conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
        return {"status": "ready", "db": "ok", "pod": POD_NAME}
    except Exception as exc:  # noqa: BLE001
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "db": "error", "error": str(exc).strip(), "pod": POD_NAME},
        )


# ---------------------------------------------------------------- CRUD
class EstudianteIn(BaseModel):
    nombre: str = Field(min_length=1, max_length=100)
    email: str = Field(min_length=3, max_length=150)


@app.get("/estudiantes")
def listar_estudiantes():
    asegurar_tabla()
    with get_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(f"SELECT {COLS} FROM estudiantes ORDER BY id")
        return cur.fetchall()


@app.get("/estudiantes/{estudiante_id}")
def obtener_estudiante(estudiante_id: int):
    asegurar_tabla()
    with get_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(f"SELECT {COLS} FROM estudiantes WHERE id = %s", (estudiante_id,))
        fila = cur.fetchone()
    if fila is None:
        raise HTTPException(status_code=404, detail="Estudiante no encontrado")
    return fila


@app.post("/estudiantes", status_code=201)
def crear_estudiante(datos: EstudianteIn):
    asegurar_tabla()
    try:
        with get_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                f"INSERT INTO estudiantes (nombre, email) VALUES (%s, %s) RETURNING {COLS}",
                (datos.nombre, datos.email),
            )
            return cur.fetchone()
    except psycopg2.IntegrityError:
        raise HTTPException(status_code=409, detail="Ya existe un estudiante con ese email")


@app.put("/estudiantes/{estudiante_id}")
def actualizar_estudiante(estudiante_id: int, datos: EstudianteIn):
    asegurar_tabla()
    try:
        with get_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                f"UPDATE estudiantes SET nombre = %s, email = %s WHERE id = %s RETURNING {COLS}",
                (datos.nombre, datos.email, estudiante_id),
            )
            fila = cur.fetchone()
    except psycopg2.IntegrityError:
        raise HTTPException(status_code=409, detail="Ya existe un estudiante con ese email")
    if fila is None:
        raise HTTPException(status_code=404, detail="Estudiante no encontrado")
    return fila


@app.delete("/estudiantes/{estudiante_id}")
def eliminar_estudiante(estudiante_id: int):
    asegurar_tabla()
    with get_conn() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM estudiantes WHERE id = %s RETURNING id", (estudiante_id,))
        fila = cur.fetchone()
    if fila is None:
        raise HTTPException(status_code=404, detail="Estudiante no encontrado")
    return {"deleted": estudiante_id, "pod": POD_NAME}
