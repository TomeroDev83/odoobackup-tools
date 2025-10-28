#!/bin/bash
# Copyright 2025 TomeroDev83
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0

# Load utilities
source "$(dirname "$0")/lib/utils.sh"

# Global variables
MODE=""
ORIG_DIR=$(pwd)
FOLDER_TMP=$(mktemp -d /tmp/odoobackups_XXXX)
CONF=""
DUMP_NAME="dump.sql"
DEFAULT="/.local/share/Odoo/filestore"

FILESTORE=""
DUMP=""
ZIP=""
DBNAME=""
DBUSER=""
DBPASS=""
NEUTRALIZE_PATHS=""
TEST_MODE=0

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
    if [[ -n "$NEUTRALIZE_PATHS" ]]; then
        neutralize_db
    fi
    exit 0
elif [[ "$MODE" == "neutralize" ]]; then
    neutralize_db
fi
