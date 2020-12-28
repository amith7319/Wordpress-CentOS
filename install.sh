#!/bin/bash
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi
read -p "Enter the system Wordpress site name:  " WORDPRESSSITE

yum update -y
yum install wget epel-release curl nano -y

# Installing Nginx

if [ ! -x /usr/sbin/nginx ];
    then
        echo "NGINX will be INSTALLED now"
        yum install nginx -y
        systemctl start nginx
        systemctl enable nginx
    else
        echo -----------------------------------------------------------------------------
        echo "NGINX is already INSTALLED"
        echo -----------------------------------------------------------------------------
fi

# Database environment creation
MYSQLROOT=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
echo Wordpress site name = $WORDPRESSSITE >> /root/WORDPRESSpassword.txt
WPDATABASE=$(cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 10 | head -n 1)
echo Wordpress database name = $WPDATABASE >> /root/WORDPRESSpassword.txt
WPUSER=$(cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 10 | head -n 1)
echo Wordpress user = $WPUSER >> /root/WORDPRESSpassword.txt
WPPASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
echo Wordpress password = $WPPASSWORD >> /root/WORDPRESSpassword.txt
echo "CREATE DATABASE $WPDATABASE;" >> /tmp/$WORDPRESSSITE.sql
echo "GRANT ALL ON $WPDATABASE.* TO '$WPUSER'@'localhost' IDENTIFIED BY '$WPPASSWORD';" >> /tmp/$WORDPRESSSITE.sql
echo "FLUSH PRIVILEGES;" >> /tmp/$WORDPRESSSITE.sql

## Installing Mariadb and Database setup for Wordpress
if [ ! -x /usr/bin/mysql ];
   then
      echo "MARIADB will be INSTALLED now"
      yum -y install mariadb mariadb-server
      systemctl start mariadb
      systemctl enable mariadb
      mysql_secure_installation <<EOF
      
      y
      $MYSQLROOT
      $MYSQLROOT
      y
      n
      y
      y
EOF
      echo Mysql root password = $MYSQLROOT >> /root/WORDPRESSpassword.txt
      mysql -u root -p"$MYSQLROOT" < /tmp/$WORDPRESSSITE.sql
else
      echo -----------------------------------------------------------------------------
      echo "MARIADB is already INSTALLED"
      echo -----------------------------------------------------------------------------
      read -p "Enter the Mysql root password:  " EXISTINGPASSWORD
      mysql -u root -p"$EXISTINGPASSWORD" < /tmp/$WORDPRESSSITE.sql
fi
rm -rf /tmp/$WORDPRESSSITE.sql

## Installing PHP

if [ ! -x /usr/bin/php ];
   then
      echo "PHP will be INSTALLED now"
      yum install http://rpms.remirepo.net/enterprise/remi-release-7.rpm -y
      yum --disablerepo="*" --enablerepo="remi-safe" list php[7-9][0-9].x86_64 |grep php
      echo -----------------------------------------------------------------------------
      read -p "Select one PHP version from above...like php70,php71,php80  " PHPV
      echo -----------------------------------------------------------------------------
      yum-config-manager --enable remi-$PHPV
      yum install php php-fpm php-opcache php-cli php-gd php-curl php-mysql -y
   else
      echo -----------------------------------------------------------------------------
      echo "PHP is already installed"
      echo -----------------------------------------------------------------------------
fi

#Changing PHP-FPM according to Nginx

sed -i 's|user = apache|user = nginx|g' /etc/php-fpm.d/www.conf
sed -i 's|group = apache|group = nginx|g' /etc/php-fpm.d/www.conf
sed -i 's|;listen.owner = nobody|listen.owner = nginx|g' /etc/php-fpm.d/www.conf
sed -i 's|;listen.group = nobody|listen.group = nginx|g' /etc/php-fpm.d/www.conf
sed -i 's|listen = 127.0.0.1:9000|listen = /run/php-fpm/www.sock|g' /etc/php-fpm.d/www.conf
sed -i 's|;listen.mode = 0660|listen.mode = 0666|g' /etc/php-fpm.d/www.conf
chown -R root:nginx /var/lib/php
systemctl enable php-fpm
systemctl start php-fpm

# Downloading Wordpress
sudo mkdir -p /var/www/html/$WORDPRESSSITE
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar xf latest.tar.gz
mv /tmp/wordpress/* /var/www/html/$WORDPRESSSITE
cd /var/www/html/$WORDPRESSSITE
cp wp-config-sample.php wp-config.php	
chown -R nginx: /var/www/html/$WORDPRESSSITE
sed -i 's|database_name_here|'$WPDATABASE'|g' /var/www/html/$WORDPRESSSITE/wp-config.php
sed -i 's|username_here|'$WPUSER'|g' /var/www/html/$WORDPRESSSITE/wp-config.php
sed -i 's|password_here|'$WPPASSWORD'|g' /var/www/html/$WORDPRESSSITE/wp-config.php

#Configuring TEST block NGINX

IP=$(curl checkip.amazonaws.com)
touch /etc/nginx/conf.d/$WORDPRESSSITE.conf
cat > /etc/nginx/conf.d/$WORDPRESSSITE.conf << EOL
server {
    listen 80;
    server_name  $IP $WORDPRESSSITE www.$WORDPRESSSITE;
    root   /var/www/html/$WORDPRESSSITE;
    index index.php index.html index.htm;
    
    access_log /var/log/nginx/$WORDPRESSSITE.access.log;
    error_log /var/log/nginx/$WORDPRESSSITE.error.log;
    
    location ~ \.php$ {
    fastcgi_pass unix:/run/php-fpm/www.sock;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include fastcgi_params;
  }
}
EOL
sed -i 's|fastcgi_param SCRIPT_FILENAME ;|fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;|g' /etc/nginx/conf.d/$WORDPRESSSITE.conf

systemctl restart nginx

echo ...............................Finished...Installation....!!!
echo " Visit.... http://$WORDPRESSSITE"
echo " All password and username are stored in /root/WORDPRESSpassword.txt"
