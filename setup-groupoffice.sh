#!/bin/bash

# Ensure we're in the right directory
cd /etc/nixos

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root"
  exit 1
fi

echo "Creating GroupOffice configuration..."

# Create initial config file
cat > /etc/groupoffice/config.php << 'EOL'
<?php
$config['db_name'] = 'groupoffice';
$config['db_host'] = 'groupoffice-db';
$config['db_user'] = 'groupoffice';
$config['db_pass'] = 'groupoffice';
$config['db_port'] = 3306;
$config['file_storage_path'] = '/var/lib/groupoffice';
$config['tmpdir'] = '/tmp/groupoffice';
$config['debug'] = false;
$config['default_timezone'] = 'Australia/Sydney';
$config['default_charset'] = 'UTF-8';
$config['default_language'] = 'en';
$config['default_text_separator'] = ';';
$config['default_list_separator'] = ',';
$config['default_currency'] = '€';
$config['default_decimal_separator'] = '.';
$config['default_thousands_separator'] = ',';
$config['default_date_format'] = 'd-m-Y';
$config['default_date_separator'] = '-';
$config['default_time_format'] = 'G:i';
$config['default_first_weekday'] = 1;
$config['default_tags'] = '';
$config['default_max_rows_list'] = 50;
$config['default_max_search_results'] = 50;
$config['default_time_zone'] = 'Australia/Sydney';
EOL

# Set proper permissions
chown admin:docker /etc/groupoffice/config.php
chmod 660 /etc/groupoffice/config.php

# Create temp directory
mkdir -p /tmp/groupoffice
chown admin:docker /tmp/groupoffice
chmod 770 /tmp/groupoffice

# Wait for database to be ready
echo "Waiting for database to be ready..."
for i in {1..30}; do
    if docker exec groupoffice-db mysqladmin ping -h localhost -u groupoffice -pgroupoffice &> /dev/null; then
        echo "Database is ready!"
        break
    fi
    echo "Waiting for database... ($i/30)"
    sleep 2
done

# Restart GroupOffice container
echo "Restarting GroupOffice container..."
docker restart groupoffice

echo "Setup complete! Please wait a minute, then access GroupOffice at http://localhost:9000"
echo ""
echo "Database connection details:"
echo "  Host: groupoffice-db"
echo "  Port: 3306"
echo "  Database: groupoffice"
echo "  Username: groupoffice"
echo "  Password: groupoffice"
echo ""
echo "Admin user password is 'changeme' - please change this immediately after logging in!"