#!/usr/bin/bash

# This script contains migrations for CassetteOS to be applied
# for versions older than v0.0.10.
# It is intended to be called from the main update.sh script, and inherits
# functions (like Show) and variables (like sudo_cmd) from it.

echo ""
Show 2 "Running migration tasks for v0.0.10..."
echo ""

# --- Create Docker Network ---
Show 2 "[v0.0.10] Checking for cassetteos docker network..."
if [ -z "$(docker network ls -q -f name=cassetteos)" ]; then
    Show 2 "cassetteos network not found. Creating..."
    docker network create \
        --driver bridge \
        --subnet 172.30.0.0/16 \
        cassetteos || Show 3 "Failed to create docker network. Maybe it already exists."
    Show 0 "Docker network 'cassetteos' created or already exists."
else
    Show 0 "Docker network 'cassetteos' already exists."
fi
echo ""

# --- Set DB Admin Password ---
Show 2 "[v0.0.10] Checking DB admin password..."
if [ -f "$APP_CONFIG_FILE" ] && ${sudo_cmd} grep -q "^\s*DBAdminPassword\s*=" "$APP_CONFIG_FILE"; then
    Show 0 "DB admin password already configured."
else
    Show 2 "DB admin password not set. Configuring..."
    DB_ADMIN_PASSWORD=$(openssl rand -base64 24)
    if [ -z "$DB_ADMIN_PASSWORD" ]; then
        Show 1 "Failed to generate password!"
        exit 1
    fi

    Show 2 "Setting new password for db_admin_user..."
    if ! ${sudo_cmd} -u postgres psql -c "ALTER ROLE db_admin_user WITH PASSWORD '$DB_ADMIN_PASSWORD';"; then
        Show 1 "Failed to set password for db_admin_user!"
        exit 1
    fi

    Show 2 "Saving new password to $APP_CONFIG_FILE..."
    set_ini_value "$APP_CONFIG_FILE" "app" "DBAdminPassword" "$DB_ADMIN_PASSWORD"
    Show 0 "DB admin password configured successfully."
fi
echo ""

# --- Remove Insecure Trust Auth from pg_hba.conf ---
Show 2 "[v0.0.10] Checking pg_hba.conf for insecure trust rule..."
PG_HBA=$(${sudo_cmd} -u postgres psql -t -P format=unaligned -c 'show hba_file';)
if [ -z "$PG_HBA" ]; then
    Show 3 "Could not determine pg_hba.conf location. Skipping."
else
    trust_rule="host    all             db_admin_user   172.30.0.0/16            trust"
    if ${sudo_cmd} grep -q "$trust_rule" "$PG_HBA"; then
        Show 2 "Found insecure trust rule. Removing..."
        if ${sudo_cmd} sed -i '/host    all             db_admin_user   172.30.0.0\/16            trust/d' "$PG_HBA"; then
            Show 0 "Removed insecure trust rule."
            Show 2 "Reloading PostgreSQL configuration..."
            ${sudo_cmd} systemctl reload postgresql || Show 3 "Failed to reload PostgreSQL."
        else
            Show 1 "Failed to remove insecure trust rule from $PG_HBA."
        fi
    else
        Show 0 "Insecure trust rule not found. No action needed."
    fi
fi
echo ""
