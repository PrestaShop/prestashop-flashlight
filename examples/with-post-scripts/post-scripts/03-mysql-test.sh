#!/bin/sh
echo "* 03-mysql-test here"

mysql_query() {
  SQL_QUERY=$1
  mysql -u "$MYSQL_USER" --host="$MYSQL_HOST" --password="$MYSQL_PASSWORD" "$MYSQL_DATABASE" -N -se "$SQL_QUERY";
}

PS_FOLDER=${PS_FOLDER:?missing PS_FOLDER}
PS_VERSION=$(awk 'NR==1{print $2}' "${PS_FOLDER}/VERSION")
PS_VERSION_DB=$(mysql_query "SELECT value FROM ps_configuration WHERE name='PS_VERSION_DB';");

if [ "$PS_VERSION_DB" != "$PS_VERSION" ]; then
  echo "Database version does not match PrestaShop version";
  exit 1;
else 
  echo "All checks passed!";
fi
