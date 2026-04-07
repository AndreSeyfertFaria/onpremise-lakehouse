FROM apache/superset:6.0.0

USER root

# Install dependencies for Trino directly into the app virtualenv
RUN uv pip install --python /app/.venv sqlalchemy-trino

# Copy initialization script
COPY superset_init.sh /app/superset_init.sh
RUN chmod +x /app/superset_init.sh && sed -i 's/\r$//' /app/superset_init.sh

# Revert to superset user
USER superset

ENTRYPOINT ["/bin/bash", "/app/superset_init.sh"]
