import os
import sys
import logging
from pprint import pprint

logging.basicConfig(level=logging.INFO)

from superset.app import create_app
app = create_app()
app.app_context().push()

from superset.commands.dashboard.importers.v1 import ImportDashboardsCommand
from flask import g
from superset import security_manager

g.user = security_manager.find_user(username="admin")

contents = {}
base_dir = '/app/superset_home/assets'
for root, dirs, files in os.walk(base_dir):
    for file in files:
        if file.endswith('.yaml') or file.endswith('.yml'):
            path = os.path.join(root, file)
            rel_path = os.path.relpath(path, base_dir)
            rel_path = rel_path.replace(os.sep, '/')
            with open(path) as f:
                contents[rel_path] = f.read()

contents['metadata.yaml'] = 'version: 1.0.0\ntype: Dashboard\ntimestamp: "2026-04-01T20:00:00Z"\n'

print("Importing the following files as Dashboard bundle:")
pprint(list(contents.keys()))

try:
    command = ImportDashboardsCommand(contents, overwrite=True)
    command.run()
    print("SUCCESS")
except Exception as e:
    import traceback
    traceback.print_exc()
