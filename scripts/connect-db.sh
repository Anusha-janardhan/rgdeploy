#!/bin/bash
version="0.1.0"
echo "Connecting to DB....(connect-db.sh v$version)"

if [ "$1" == "-h" ]; then
	echo "Usage: $(basename $0)"
	exit 0
fi

[ -z "$RG_HOME" ] && RG_HOME='/opt/deploy/sp2'
echo "RG_HOME=$RG_HOME"
myinput=$(cat "$RG_HOME/config/mongo-config.json")
if [ -z "$myinput" ]; then
	echo "Could not find DB details file. Exiting"
	exit 1
fi

mydbuser=$(jq -r '.db_auth_config.username' <<<"${myinput}")
mydbuserpwd=$(jq -r '.db_auth_config.password' <<<"${myinput}")

if [ -z "$mydbuser" ] || [ -z "$mydbuserpwd" ]; then
	echo "Could not find DB details. Exiting"
	exit 1
fi

if [ ! -f "$RG_HOME/docker-compose.yml" ]; then
	echo "docker-compose.yml does not exist. Exiting"
	exit 1
fi
mydocdburl=$(grep DB_HOST "$RG_HOME/docker-compose.yml" | head -1 | sed -e "s/.*DB_HOST=//")
if [ -z "$mydocdburl" ]; then
	echo "Could not find DB URL. Exiting"
	exit 1
fi

mongo --ssl --host "$mydocdburl:27017" --sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
	--username "$mydbuser" --password "$mydbuserpwd"
