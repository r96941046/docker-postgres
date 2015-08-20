#!/bin/bash

# exit immediately if a command exits with a non-zero status
set -e

echo "Start setting PostgreSQL server..."

DB_USER=${DB_USER:-}
DB_PASS=${DB_PASS:-}
DB_NAME=${DB_NAME:-}

# standalone/master/slave/snapshot
PSQL_MODE=${PSQL_MODE:-standalone}

create_data_dir() {
    mkdir -p ${PG_HOME}
    chmod -R 0700 ${PG_HOME}
    chown -R ${PG_USER}:${PG_USER} ${PG_HOME}
}

create_log_dir() {
    mkdir -p ${PG_LOGDIR}
    chmod -R 1755 ${PG_LOGDIR}
    chown -R root:${PG_USER} ${PG_LOGDIR}
}

create_run_dir() {
    mkdir -p ${PG_RUNDIR} ${PG_RUNDIR}/${PG_VERSION}-main.pg_stat_tmp
    chmod -R 0755 ${PG_RUNDIR}
    chmod g+s ${PG_RUNDIR}
    chown -R ${PG_USER}:${PG_USER} ${PG_RUNDIR}
}

create_data_dir
create_log_dir
create_run_dir

# listen on all interfaces
cat >> ${PG_CONFDIR}/postgresql.conf <<EOF
listen_addresses = '*'
EOF

# allow tcp connections to postgresql database
cat >> ${PG_CONFDIR}/pg_hba.conf <<EOF
host    all             all             0.0.0.0/0               md5
EOF

# create DB_USER with DB_PASS
if [[ -n ${DB_USER} ]]; then
    if [[ -z ${DB_PASS} ]]; then
        echo ""
        echo "WARNING: "
        echo "   Please specify a password for \"${DB_USER}\". Skipping user creation..."
        echo ""
        DB_USER=
    else
        echo "Creating user \"${DB_USER}\"..."
        echo "CREATE ROLE ${DB_USER} with PASSWORD '${DB_PASS}' LOGIN CREATEDB;" |
            sudo -Hu ${PG_USER} ${PG_BINDIR}/postgres --single \
                -D ${PG_DATADIR} -c config_file=${PG_CONFDIR}/postgresql.conf >/dev/null
    fi
fi

# create DB_NAME
if [[ -n ${DB_NAME} ]]; then

    # create utf-8 encoded template1 from which we later create db from
    echo "Create utf-8 encoded template1..."

    locale-gen "en_US.UTF-8"

    echo "UPDATE pg_database SET datistemplate=false WHERE datname='template1';" | \
        sudo -Hu ${PG_USER} ${PG_BINDIR}/postgres --single \
            -D ${PG_DATADIR} -c config_file=${PG_CONFDIR}/postgresql.conf >/dev/null
    echo "DROP DATABASE Template1;" | \
        sudo -Hu ${PG_USER} ${PG_BINDIR}/postgres --single \
            -D ${PG_DATADIR} -c config_file=${PG_CONFDIR}/postgresql.conf >/dev/null
    echo "CREATE DATABASE template1 WITH owner=postgres encoding='UTF-8' lc_collate='en_US.UTF-8' lc_ctype='en_US.UTF-8' template template0;" | \
        sudo -Hu ${PG_USER} ${PG_BINDIR}/postgres --single \
            -D ${PG_DATADIR} -c config_file=${PG_CONFDIR}/postgresql.conf >/dev/null
    echo "UPDATE pg_database SET datistemplate=true WHERE datname='template1';" | \
        sudo -Hu ${PG_USER} ${PG_BINDIR}/postgres --single \
            -D ${PG_DATADIR} -c config_file=${PG_CONFDIR}/postgresql.conf >/dev/null

    for db in $(awk -F',' '{for (i = 1 ; i <= NF ; i++) print $i}' <<< "${DB_NAME}"); do
        echo "Creating database \"${db}\"..."
        echo "CREATE DATABASE ${db} OWNER ${DB_USER} ENCODING 'UTF8' LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8' TEMPLATE template1;" | \
            sudo -Hu ${PG_USER} ${PG_BINDIR}/postgres --single \
                -D ${PG_DATADIR} -c config_file=${PG_CONFDIR}/postgresql.conf >/dev/null

        if [[ -n ${DB_USER} ]]; then
            echo "Granting access to database \"${db}\" for user \"${DB_USER}\"..."
            echo "GRANT ALL PRIVILEGES ON DATABASE ${db} to ${DB_USER};" | \
                sudo -Hu ${PG_USER} ${PG_BINDIR}/postgres --single \
                    -D ${PG_DATADIR} -c config_file=${PG_CONFDIR}/postgresql.conf >/dev/null
        fi
    done
fi

# start PostgreSQL server
echo "Starting PostgreSQL server..."
exec start-stop-daemon --start --chuid ${PG_USER}:${PG_USER} --exec ${PG_BINDIR}/postgres -- \
    -c config_file=${PG_CONFDIR}/postgresql.conf

echo "Done"
