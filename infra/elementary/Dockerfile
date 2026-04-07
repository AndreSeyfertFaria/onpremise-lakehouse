FROM python:3.10-slim

WORKDIR /app

# Install elementary with the trino adapter and supervisor
RUN pip install --no-cache-dir 'elementary-data[trino]==0.23.1' supervisor

COPY run_edr.sh /app/run_edr.sh
RUN chmod +x /app/run_edr.sh && mkdir -p /app/report

# Add supervisord.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Run supervisor
CMD ["/usr/local/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
