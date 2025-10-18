#!/bin/bash

# Load utilities
source "$(dirname "$0")/lib/utils.sh"

# Global variables
MODE=""
ORIG_DIR=$(pwd)
FOLDER_TMP="/tmp/odoobackups"
CONF=""
DUMP_NAME="dump.sql"
DEFAULT="/.local/share/Odoo/filestore"

FILESTORE=""
DUMP=""
ZIP=""
DBNAME=""
DBUSER=""
DBPASS=""

# Automatic cleanup of temporary files
trap 'cleanup' EXIT

##############
###   RUN   ##
##############

parse_args "$@"

# Load configuration if applicable
if [[ -n "$CONF" ]]; then
    if [[ -f "$CONF" ]]; then
        load_conf "$CONF"
    else
        echo "ERROR: Configuration file does not exist."
        exit 1
    fi
fi

if [[ "$MODE" == "export" ]]; then
    export_db
elif [[ "$MODE" == "import" ]]; then
    import_db
fi