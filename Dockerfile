FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN addgroup --system controlplane && adduser --system --ingroup controlplane controlplane

COPY pyproject.toml README.md ./
COPY sre_control_plane ./sre_control_plane
COPY alembic ./alembic
COPY alembic.ini ./

RUN python -m pip install --upgrade pip && python -m pip install .

USER controlplane

EXPOSE 8080

CMD ["sh", "-c", "exec uvicorn sre_control_plane.app:app --host 0.0.0.0 --port ${PORT:-8080}"]
