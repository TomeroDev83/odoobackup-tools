#!/bin/bash
# Copyright 2025 TomeroDev83
# Licensed under the Apache License, Version 2.0
# http://www.apache.org/licenses/LICENSE-2.0

show_help() {
    cat << EOF
odoobackup.sh - Tool for exporting/importing Odoo backups

USAGE:
  $0 export -d <DBname> -u <dbuser> [-p <dbpassword>] [-c <config.conf>] [-f <filestorepath>]
  $0 import -z <input.zip> [-c <config.conf>] [-f <filestore_dir>] [-d <dump.sql>] [-n <DBname>] [-u <dbuser>] [-p <dbpassword>] [-n <addons_paths>] [-t]
  $0 neutralize -d <DBname> -u <dbuser> [-p <dbpassword>] -n <addons_paths> [-t]
  $0 help

For more information, check README.md
EOF
    exit 0
}

load_conf() {
    local conf_file="$1"
    while IFS='=' read -r key value; do
        case "$key" in
            DBNAME) DBNAME="$value" ;;
            DBUSER) DBUSER="$value" ;;
            DBPASS) DBPASS="$value" ;;
            FILESTORE) FILESTORE="$value" ;;
            ZIP) ZIP="$value" ;;
            NEUTRALIZE_PATHS) NEUTRALIZE_PATHS="value" ;;
        esac
    done < <(grep -E '^(DBNAME|DBUSER|DBPASS|FILESTORE|ZIP|NEUTRALIZE_PATHS)=' "$conf_file")
}

validate_db_connection() {
    local dbname="$1"
    local dbuser="$2"
    local dbpass="$3"
    PGPASSWORD="$dbpass" psql -U "$dbuser" -d "$dbname" -c "\q" >/dev/null 2>&1
    [[ $? -eq 0 ]] || { echo "ERROR: Cannot connect to database $dbname"; exit 1; }
}

validate_pg_connection() {
    local dbuser="$1"
    local dbpass="$2"
    PGPASSWORD="$dbpass" psql -U "$dbuser" -d postgres -c "\q" >/dev/null 2>&1
    [[ $? -eq 0 ]] || { echo "ERROR: Cannot connect to PostgreSQL server with user $dbuser"; exit 1; }
}

spinner() {
    local pid1=$1
    local pid2=$2
    local msg="${3:-WORKING}"
    local count=0
    while { kill -0 "$pid1" 2>/dev/null || { [[ -n "$pid2" ]] && kill -0 "$pid2" 2>/dev/null; }; }; do
        ((count=(count+1)%6))
        dots=$(printf "%-${count}s" "." | tr ' ' '.')
        printf "\r%s%s" "$msg" "$dots"
        sleep 0.5
    done
    printf "\r%s... done!\n" "$msg"
}

check_db_exists() {
    local dbname="$1"
    local dbuser="$2"
    local dbpass="$3"
    local tmp_folder="$4"
    exists=$(PGPASSWORD="$dbpass" psql -U "$dbuser" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$dbname';")
    if [[ "$exists" == "1" ]]; then
        echo "❌ ERROR: Database '$dbname' already exists."
        echo "👉 Choose another name with -d or delete the existing database manually:"
        echo "   dropdb -U $dbuser $dbname"
        rm -rf "$tmp_folder"
        exit 1
    fi
}

check_write_permissions() {
    local target_dir="$1"

    if [[ ! -d "$target_dir" ]]; then
        # Try to create parent directory to test permissions
        parent_dir=$(dirname "$target_dir")
        if ! mkdir -p "$target_dir" 2>/dev/null; then
            echo "❌ ERROR: Cannot write to $parent_dir. Check permissions."
            exit 1
        fi
        # Remove if it was just a test
        rmdir "$target_dir"
    else
        # Check if we have write permissions
        if [[ ! -w "$target_dir" ]]; then
            echo "❌ ERROR: No write permissions in $target_dir"
            exit 1
        fi
    fi
}

cleanup() {
    # Clean temporary directories
    [[ -n "$FOLDER_TMP" && -d "$FOLDER_TMP" ]] && rm -rf "$FOLDER_TMP"

    # Clean temporary neutralize file
    [[ -n "$TMP_SQL" && -f "$TMP_SQL" ]] && rm -f "$TMP_SQL"

    # Remove DB only if there was a failure during import
    if [[ "$MODE" == "import" && "$DB_CREATED" == "1" && "$IMPORT_SUCCESS" != "1" ]]; then
        echo "❌ Removing incomplete database $DBNAME..."
        PGPASSWORD="$DBPASS" dropdb -U "$DBUSER" "$DBNAME" 2>/dev/null
    fi
}

# Detect Odoo major version from database
get_odoo_major_version() {
    local dbname="$1"
    local dbuser="$2"
    local dbpass="$3"

    # Consultar la versión desde el módulo 'base'
    RAW_VERSION=$(PGPASSWORD="$dbpass" psql -U "$dbuser" -d "$dbname" -tAc "
        SELECT latest_version
          FROM ir_module_module
         WHERE name='base';
    " 2>/dev/null | tr -d '[:space:]')

    if [[ -z "$RAW_VERSION" ]]; then
        echo "⚠️  Could not detect Odoo version, defaulting to 16"
        echo "16"
        return
    fi

    # Extraer solo el primer número (major version)
    MAJOR_VERSION=$(echo "$RAW_VERSION" | cut -d'.' -f1)
    echo "$MAJOR_VERSION"
}

parse_args() {
    case "${1:-}" in
        export) MODE="export"; shift ;;
        import) MODE="import"; shift ;;
        neutralize) MODE="neutralize"; shift ;;
        help) show_help ;;
        *) show_help ;;
    esac

    while getopts ":d:u:p:z:c:f:n:t" opt; do
        case $opt in
            d) DBNAME="$OPTARG" ;;
            u) DBUSER="$OPTARG" ;;
            p) DBPASS="$OPTARG" ;;
            z) ZIP="$OPTARG" ;;
            c) CONF="$OPTARG" ;;
            f) FILESTORE="$OPTARG" ;;
            n) NEUTRALIZE_PATHS="$OPTARG" ;;
            t) TEST_MODE=1 ;;
            :) echo "❌ Error: option -$OPTARG requires an argument"; exit 1 ;;
            \?) echo "❌ Error: invalid option -$OPTARG"; exit 1 ;;
        esac
    done
}

neutralize_db() {
    echo "🔹 Starting neutralization process..."

    # Validar inputs
    [[ -z "$DBNAME" || -z "$DBUSER" || -z "$DBPASS" ]] && {
        echo "❌ Missing database credentials."
        return 1
    }

    # Solo validar conexión si se ejecuta en modo neutralize
    if [[ "$MODE" == "neutralize" ]]; then
        validate_db_connection "$DBNAME" "$DBUSER" "$DBPASS"
    fi

    # Validar rutas de addons
    if [[ -z "$NEUTRALIZE_PATHS" ]]; then
        echo "❌ Missing -N <paths> (addons paths separated by commas)"
        exit 1
    fi

    # Separar por comas y limpiar rutas
    IFS=',' read -ra PATHS_RAW <<< "$NEUTRALIZE_PATHS"
    PATHS=()
    for path in "${PATHS_RAW[@]}"; do
        path=$(echo "$path" | xargs)   # trim espacios
        path="${path%/}"               # quitar barra final
        [[ ! -d "$path" ]] && { echo "❌ Addons path not found: $path"; exit 1; }
        PATHS+=("$path")
    done

    # Detect major version
    ODOO_MAJOR=$(get_odoo_major_version "$DBNAME" "$DBUSER" "$DBPASS")
    echo "📌 Detected Odoo major version: $ODOO_MAJOR"

    # Crear archivo temporal
    TMP_SQL=$(mktemp /tmp/neutralize_XXXX.sql)


    if (( ODOO_MAJOR < 16 )); then
        echo "⚠️  Version <16 detected, applying alternative neutralize SQL..."
        ALT_SQL_FILE="$(dirname "$0")/sql/neutralize_pre16.sql"
        if [[ ! -f "$ALT_SQL_FILE" ]]; then
            echo "❌ Alternative neutralize SQL file not found: $ALT_SQL_FILE"
            rm -f "$TMP_SQL"
            exit 1
        fi
        cp "$ALT_SQL_FILE" "$TMP_SQL"
    else
        # Consultar módulos instalados
        echo "📦 Fetching installed modules..."
        MODULES=$(PGPASSWORD="$DBPASS" psql -U "$DBUSER" -d "$DBNAME" -tAc "
            SELECT name FROM ir_module_module
            WHERE state IN ('installed', 'to upgrade', 'to remove');
        ")

        if [[ -z "$MODULES" ]]; then
            echo "⚠️  No modules found in the database."
            return 0
        fi

        # Convertir rutas separadas por coma en array
        IFS=',' read -ra PATHS <<< "$NEUTRALIZE_PATHS"

        echo "🔍 Searching for neutralize.sql files..."

        for path in "${PATHS[@]}"; do
            for mod in $MODULES; do
                # Buscar recursivamente cualquier neutralize.sql dentro de $mod/data/
                while IFS= read -r file; do
                    echo "✅ Found: $file"
                    cat "$file" >> "$TMP_SQL"
                    echo "" >> "$TMP_SQL"
                done < <(find "$path" -type f -path "*/$mod/data/neutralize.sql" 2>/dev/null)
            done
        done
    fi

    # Si no hay scripts, salir
    if [[ ! -s "$TMP_SQL" ]]; then
        echo "ℹ️ No neutralize.sql scripts found."
        rm -f "$TMP_SQL"
        return 0
    fi

    # En modo test/debug solo mostramos info y no ejecutamos SQL
    if [[ "$TEST_MODE" -eq 1 ]]; then
        echo "DEBUG: Test mode enabled, skipping SQL execution."
        rm -f "$TMP_SQL"
        return 0
    fi

    echo "⚙️  Executing neutralization SQL..."
    PGPASSWORD="$DBPASS" psql -U "$DBUSER" -d "$DBNAME" -f "$TMP_SQL" >/dev/null 2>&1 &
    PID_NEUTRALIZE=$!
    spinner "$PID_NEUTRALIZE" "" "Neutralizing"
    wait "$PID_NEUTRALIZE"

    if [[ $? -eq 0 ]]; then
        echo "✅ Neutralization completed successfully."
    else
        echo "❌ Error applying neutralize scripts."
    fi

    rm -f "$TMP_SQL"
}

export_db() {
    [[ -z "$DBNAME" ]] && { echo "ERROR: -d DBNAME is required"; exit 1; }
    [[ -z "$DBUSER" ]] && { echo "ERROR: -u DBUSER is required"; exit 1; }
    [[ -z "$FILESTORE" ]] && FILESTORE="$HOME$DEFAULT"
    validate_db_connection "$DBNAME" "$DBUSER" "$DBPASS"
    mkdir -p "$FOLDER_TMP" && cd "$FOLDER_TMP"
    timestamp=$(date +"%Y%m%d_%H%M%S")
    NAME_ZIP="${DBNAME}_${timestamp}.zip"
    ZIP="${FOLDER_TMP}/$NAME_ZIP"
    DUMP="$FOLDER_TMP/$DUMP_NAME"
    echo "Adding filestore..."
    ln -s "$FILESTORE/$DBNAME" filestore
    zip -r "$ZIP" filestore >/dev/null 2>&1 & PID_FILESTORE=$!
    echo "Exporting DB..."
    PGPASSWORD="$DBPASS" pg_dump -U "$DBUSER" -d "$DBNAME" -x > "$DUMP" 2>/dev/null & PID_DUMP=$!
    spinner "$PID_FILESTORE" "$PID_DUMP" & PID_SPINNER=$!
    wait "$PID_FILESTORE"; STATUS_FILESTORE=$?
    wait "$PID_DUMP"; STATUS_DUMP=$?
    kill "$PID_SPINNER" 2>/dev/null
    echo ""
    if [[ $STATUS_FILESTORE -ne 0 || $STATUS_DUMP -ne 0 ]]; then
        echo "❌ Error during export."
        exit 1
    fi
    zip -u -q "$ZIP" "$DUMP_NAME"
    echo "Operations completed successfully"
    cd "$ORIG_DIR"
    mv "$ZIP" .
    echo "Export completed: $NAME_ZIP"
    exit 0
}

import_db() {
    [[ -z "$DBNAME" ]] && { echo "ERROR: -d DBNAME is required"; exit 1; }
    [[ -z "$DBUSER" ]] && { echo "ERROR: -u DBUSER is required"; exit 1; }
    [[ -z "$ZIP" ]] && { echo "ERROR: -z file.zip is required for import"; exit 1; }
    [[ ! -f "$ZIP" ]] && { echo "ERROR: Zip file not found"; exit 1; }
    [[ -z "$FILESTORE" ]] && FILESTORE="$HOME$DEFAULT"
    validate_pg_connection "$DBUSER" "$DBPASS"
    check_db_exists "$DBNAME" "$DBUSER" "$DBPASS" "$FOLDER_TMP"
    check_write_permissions "$FILESTORE"
    mkdir -p "$FOLDER_TMP"
    FILES_FILESTORE="$FOLDER_TMP/$DBNAME"
    echo "Descomprimiendo backup..."
    unzip -q "$ZIP" -d "$FILES_FILESTORE" &
    PID_UNZIP=$!
    spinner "$PID_UNZIP" "" "UNZIP"  # Llamamos spinner con solo un PID
    wait "$PID_UNZIP"
    STATUS_UNZIP=$?

    if [[ $STATUS_UNZIP -ne 0 ]]; then
        echo "❌ Error al descomprimir el archivo ZIP."
        exit 1
    fi

    DUMP="$FILES_FILESTORE/dump.sql"
    FILES_FILESTORE="$FILES_FILESTORE/filestore"
    [[ ! -f "$DUMP" || ! -d "$FILES_FILESTORE" ]] && { echo "ERROR: filestore or dump.sql not found in zip"; exit 1; }
    echo "Creating database $DBNAME..."
    PGPASSWORD="$DBPASS" createdb -U "$DBUSER" -O "$DBUSER" "$DBNAME"
    DB_CREATED=1
    echo "Moving filestore..."
    mv "$FILES_FILESTORE" "$FILESTORE/$DBNAME" >/dev/null 2>&1 & PID_FILESTORE=$!
    echo "Importing DB..."
    PGPASSWORD="$DBPASS" psql -U "$DBUSER" -d "$DBNAME" -f "$DUMP" >/dev/null 2>&1 & PID_DUMP=$!
    spinner "$PID_FILESTORE" "$PID_DUMP" & PID_SPINNER=$!
    wait "$PID_FILESTORE"; STATUS_FILESTORE=$?
    wait "$PID_DUMP"; STATUS_DUMP=$?
    kill "$PID_SPINNER" 2>/dev/null
    echo ""
    if [[ $STATUS_FILESTORE -ne 0 || $STATUS_DUMP -ne 0 ]]; then
        echo "❌ Error during import."
        exit 1
    fi
    IMPORT_SUCCESS=1
    echo "Operations completed successfully"
    echo "Import completed: $DBNAME"
    return 0
}