from airflow import DAG
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig, RenderConfig
from cosmos.constants import LoadMode
from cosmos.profiles.trino import TrinoBaseProfileMapping
from airflow.models.param import Param
from airflow.operators.bash import BashOperator
from datetime import datetime

import os

# The path where the dbt project is mounted in the Airflow container
DBT_PROJECT_PATH = os.getenv("DBT_PROJECT_PATH", "/opt/airflow/dbt")

# Configure the profile to use Airflow's "trino_dbt" connection
profile_config = ProfileConfig(
    profile_name="local_lakehouse",
    target_name="dev",
    profile_mapping=TrinoBaseProfileMapping(
        conn_id="trino_dbt",
        profile_args={
            "threads": 4,
            "database": "iceberg",
            "schema": "bronze",
        },
    ),
)

with DAG(
    dag_id="dag_lakehouse_bronze",
    start_date=datetime(2024, 1, 1),
    schedule_interval="*/5 * * * *", 
    catchup=False,
    tags=["lakehouse", "bronze", "ingestion", "staging"],
    params={
        "full_refresh": Param(False, type="boolean", description="Run dbt with --full-refresh"),
    },
) as dag:


    bronze_layer = DbtTaskGroup(
        group_id="bronze_layer",
        project_config=ProjectConfig(DBT_PROJECT_PATH),
        profile_config=profile_config,
        execution_config=ExecutionConfig(
            dbt_executable_path="/opt/airflow/dbt_venv/bin/dbt",
        ),
        render_config=RenderConfig(
            select=["tag:raw", "tag:staging"],
            load_method=LoadMode.DBT_LS, # Fast parsing using dbt list
            dbt_deps=False,
        ),
        operator_args={
             "install_deps": False,
             "full_refresh": "{{ params.full_refresh }}",
        },
    )

    elementary_sync = BashOperator(
        task_id="elementary_sync",
        bash_command=f"source /opt/airflow/dbt_venv/bin/activate && cd {DBT_PROJECT_PATH} && export DBT_LOG_PATH=/tmp && dbt run-operation elementary.on_run_end",
    )

    bronze_layer >> elementary_sync
