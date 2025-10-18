# odoobackup.sh

Tool for safely exporting and importing Odoo backups, including database and filestore.

---

## Description

`odoobackup.sh` allows you to:

* **Export**: Create a backup of the Odoo database and its filestore, packaged in a `.zip` file.
* **Import**: Restore a backup from a `.zip` into a new database, moving the filestore and restoring the DB.

The script works using **Unix sockets**, without requiring `sudo`, and allows working with `.conf` configuration files to simplify parameters.

---

## Requirements

* PostgreSQL installed and accessible via local socket.
* PostgreSQL user with sufficient permissions to create and restore databases.
* `zip` and `unzip` installed.
* Bash 4+ (for modern arrays and functions).

---

## Usage

```bash
# Show help
./odoobackup.sh help

# Export backup
./odoobackup.sh export -d <DBNAME> -u <DBUSER> -p <DBPASS> [-c <config.conf>] [-f <filestore_dir>]

# Import backup
./odoobackup.sh import -d <DBNAME> -u <DBUSER> -p <DBPASS> -z <input.zip> [-c <config.conf>] [-f <filestore_dir>]
```

---

## Options

### Export

| Option | Description                                                        |
| ------ | ------------------------------------------------------------------ |
| `-d`   | Database name to export **(required)**                              |
| `-u`   | PostgreSQL user                                                    |
| `-p`   | User password                                                      |
| `-f`   | Path to filestore. Default: `$HOME/.local/share/Odoo/filestore/`   |
| `-c`   | Configuration file `.conf` (see example below)                      |

### Import

| Option | Description                                                                      |
| ------ | -------------------------------------------------------------------------------- |
| `-d`   | Database name to create/restore **(required)**                                    |
| `-u`   | Database owner user **(required)**                                                |
| `-p`   | User password                                                                    |
| `-z`   | Backup `.zip` file **(required)**                                                |
| `-f`   | Path where filestore will be copied. Default: `$HOME/.local/share/Odoo/filestore/`|
| `-c`   | Configuration file `.conf` (see example below)                                    |

---

## Configuration file `.conf` (optional)

If you don't want to pass all parameters each time, you can create a `.conf` file with the following format:

```ini
DBNAME=mydatabase
DBUSER=myuser
DBPASS=mypassword
FILESTORE=/var/lib/odoo/filestore
ZIP=/home/user/backup.zip
```

> The script will only read the necessary keys and will override any parameters passed via command line.

---

## Examples

### Export a backup

```bash
./odoobackup.sh export -d odoo14 -u odoo -p myPassword
```

Result:

* Creates a ZIP named `odoo14_YYYYMMDD_HHMMSS.zip`.
* Contains `dump.sql` and the database filestore.

### Import a backup

```bash
./odoobackup.sh import -d odoo14_new -u odoo -p myPassword -z odoo14_20251018_173015.zip
```

* Checks if DB already exists.
* Creates database with specified user as owner.
* Restores dump and filestore in parallel, with visual progress spinner.
* Ends showing a success message.

---

## Additional Features

* **Animated spinner** during export/import to show progress.
* **Unique name generation** for backups (`timestamp`) avoiding overwrites.
* **Connection validation** to PostgreSQL server before critical operations.
* Compatible with **Unix sockets** and no need for `sudo`.
* Clear error messages if database exists or cannot connect.

---

## Best Practices

1. Don't run import on an existing database unless you know what you're doing.
2. Keep historical backups thanks to timestamp in ZIP name.
3. Use `.conf` files to avoid exposing passwords in command line when possible.
4. Clean `/tmp/odoobackups` only after successful operation completion.

---

## License

MIT License