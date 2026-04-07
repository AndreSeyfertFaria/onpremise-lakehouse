FROM apache/airflow:2.10.2-python3.11

USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER airflow
# Copy requirements files
COPY requirements.txt requirements-dbt.txt /home/airflow/

# Install main environment libraries using official Airflow constraints
RUN pip install --no-cache-dir -r /home/airflow/requirements.txt \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-2.10.2/constraints-3.11.txt"

# Create a virtualenv for dbt and install its requirements
RUN python -m venv /opt/airflow/dbt_venv && \
    PIP_USER=false /opt/airflow/dbt_venv/bin/pip install --no-cache-dir -r /home/airflow/requirements-dbt.txt
