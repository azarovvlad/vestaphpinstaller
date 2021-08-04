#!/bin/bash

ENV_CONFIG_PATH="/opt/docker/conf"
ENV_HTTPD_CONFIG_PATH="$ENV_CONFIG_PATH/web"
ENV_PHP_CONFIG_PATH="$ENV_CONFIG_PATH/php"
DOCKER_HUB_REPO='kotpoliglot/php'

function dockerInstall () {
  echo Install docker
  curl -fsSL https://get.docker.com | sh
  service docker enable
}

function makeDefaultDirs () {
  echo Create default directories
  mkdir -p $ENV_HTTPD_CONFIG_PATH
  mkdir -p $ENV_PHP_CONFIG_PATH
  # mkdir -p $ENV_PHP_CONFIG_PATH/5.{2,4,6}
}

# if [[ $UID != 0 ]]; then
#   echo You must be root
#   exit 1
# fi

if [ `command -v docker` ]; then
  echo Docker already installed
else 
  dockerInstall
fi

if [ -d "$ENV_CONFIG_PATH" ]; then
  echo Default directories already exists
else
  makeDefaultDirs
fi

# determine current os and vars;
OS_NAME=$(. /etc/os-release && echo $ID)
case "$OS_NAME" in
  ubuntu)
    HTTPD_SERVER='apache2'
    MYSQL_SOCKET='/var/run/mysqld/'
    EXIM="exim4"
    EXIM_CONFIG_FILE="/etc/exim4/exim4.conf.template"
  ;;
  centos)
    HTTPD_SERVER='httpd'
    MYSQL_SOCKET='/var/lib/mysql/'
    EXIM="exim"
    EXIM_CONFIG_FILE="/etc/exim/exim.conf"
  ;;
  *)
    HTTPD_SERVER='apache2'
    MYSQL_SOCKET='/var/run/mysqld/'
    EXIM="exim4"
    EXIM_CONFIG_FILE="/etc/exim4/exim4.conf.template"
  ;;
esac


#add / update httpd middleware
MIDDLEWARE_HTTPD_PORT=9080

docker pull $DOCKER_HUB_REPO:httpd

FILENAME=/etc/systemd/system/docker.httpd.service
rm $FILENAME

cat <<EOT >> $FILENAME
[Unit]
Description=Apache 2.4.29 Container
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop docker-httpd
ExecStartPre=-/usr/bin/docker rm docker-httpd
ExecStartPre=/usr/bin/docker pull $DOCKER_HUB_REPO:httpd
ExecStart=/usr/bin/docker run --rm --network host -v /home:/home -v /var/log/$HTTPD_SERVER/domains:/var/log/apache2/domains -v $ENV_HTTPD_CONFIG_PATH:/usr/local/apache2/conf/vhosts --name docker-httpd $DOCKER_HUB_REPO:httpd

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload

echo "Update exim config"
sed -e '/require.*sender/ s/^#*/#/' -i $EXIM_CONFIG_FILE
service $EXIM restart

# ###                                                         
#  #  #   #  ###  #####   #   #     #        ####  #   # #### 
#  #  ##  # #       #    # #  #     #        #   # #   # #   #
#  #  # # #  ###    #   #   # #     #        #   # ##### #   #
#  #  # # #     #   #   ##### #     #        ####  #   # #### 
#  #  #  ## #   #   #   #   # #     #        #     #   # #    
# ### #   #  ###    #   #   # ##### #####    #     #   # #    


function _usage () {
    echo "USAGE: ./bootstrap.sh PHP_VERSION"
    echo "eg: ./bootstrap.sh 5.6"
    echo "List of available versions: https://hub.docker.com/r/$DOCKER_HUB_REPO/tags"
    exit 1
}

#function _check_tag () {
#    curl --silent -f -lSL https://index.docker.io/v1/repositories/$DOCKER_HUB_REPO/tags/$1 > /dev/null
#}

#if [ -n "$1" ]; then
    TAG=74
#    if _check_tag $TAG; then
        echo "Install $TAG"
        MIDDLEWARE_PHP_VERSION=$TAG
        MIDDLEWARE_PHP_PORT=90$TAG
#    else
#        _usage
#    fi
#else
#    _usage
fi

MIDDLEWARE_PHP_CONF=$ENV_PHP_CONFIG_PATH/$MIDDLEWARE_PHP_VERSION

if [ -d "$MIDDLEWARE_PHP_CONF" ]; then
  rm $MIDDLEWARE_PHP_CONF/php.ini
else
  mkdir $MIDDLEWARE_PHP_CONF
fi
touch $MIDDLEWARE_PHP_CONF/php.ini
MIDDLEWARE_PHP_CONF=$MIDDLEWARE_PHP_CONF/php.ini



cat <<EOT >> $MIDDLEWARE_PHP_CONF
short_open_tag = On
max_input_vars = 10000
opcache.revalidate_freq = 0
mbstring.func_overload = 2
date.timezone = 'Europe/Moscow'
session.save_path = '/tmp'
opcache.max_accelerated_files = 100000
realpath_cache_size = 4096k
mysql.default_host = localhost
mysql.default_socket = "/var/run/mysqld/mysqld.sock"
mysql.default_port = 3306
mysqli.default_host = localhost
mysqli.default_socket = "/var/run/mysqld/mysqld.sock"
mysqli.default_port = 3306
pdo_mysql.default_socket = "/var/run/mysqld/mysqld.sock"
EOT

FILENAME="/usr/local/vesta/data/templates/web/$HTTPD_SERVER/php$MIDDLEWARE_PHP_VERSION.tpl"
if [ -f "$FILENAME" ]; then
  rm $FILENAME
fi

cat <<EOT >> $FILENAME
<VirtualHost %ip%:$MIDDLEWARE_HTTPD_PORT>

    ServerName %domain_idn%
    %alias_string%
    ServerAdmin %email%
    DocumentRoot %docroot%
    ScriptAlias /cgi-bin/ %home%/%user%/web/%domain%/cgi-bin/
    Alias /vstats/ %home%/%user%/web/%domain%/stats/
    Alias /error/ %home%/%user%/web/%domain%/document_errors/
    CustomLog /var/log/apache2/domains/%domain%.bytes bytes
    CustomLog /var/log/apache2/domains/%domain%.log combined
    ErrorLog /var/log/apache2/domains/%domain%.error.log
    DirectoryIndex index.php index.html index.htm
    <Directory %docroot%>
        AllowOverride All
        Options +Includes -Indexes +ExecCGI
        Require all granted
        <FilesMatch "\.php$">
            ProxyFCGIBackendType GENERIC
            SetHandler  "proxy:fcgi://127.0.0.1:$MIDDLEWARE_PHP_PORT"
        </FilesMatch>
    </Directory>
    <Directory %home%/%user%/web/%domain%/stats>
        AllowOverride All
    </Directory>
    IncludeOptional %home%/%user%/conf/web/%web_system%.%domain%.conf*

</VirtualHost>
EOT

FILENAME="/usr/local/vesta/data/templates/web/$HTTPD_SERVER/php$MIDDLEWARE_PHP_VERSION.stpl"
if [ -f "$FILENAME" ]; then
  rm $FILENAME
fi

cat <<EOT >> $FILENAME
<VirtualHost %ip%:$MIDDLEWARE_HTTPD_PORT>

    ServerName %domain_idn%
    %alias_string%
    ServerAdmin %email%
    DocumentRoot %docroot%
    ScriptAlias /cgi-bin/ %home%/%user%/web/%domain%/cgi-bin/
    Alias /vstats/ %home%/%user%/web/%domain%/stats/
    Alias /error/ %home%/%user%/web/%domain%/document_errors/
    CustomLog /var/log/apache2/domains/%domain%.bytes bytes
    CustomLog /var/log/apache2/domains/%domain%.log combined
    ErrorLog /var/log/apache2/domains/%domain%.error.log
    DirectoryIndex index.php index.html index.htm
    SetEnv HTTPS "on"
    <Directory %docroot%>
        AllowOverride All
        Options +Includes -Indexes +ExecCGI
        Require all granted
        <FilesMatch "\.php$">
            ProxyFCGIBackendType GENERIC
            SetHandler  "proxy:fcgi://127.0.0.1:$MIDDLEWARE_PHP_PORT"
        </FilesMatch>
    </Directory>
    <Directory %home%/%user%/web/%domain%/stats>
        AllowOverride All
    </Directory>

</VirtualHost>
EOT

# update default template
FILENAME="/usr/local/vesta/data/templates/web/$HTTPD_SERVER/default.sh"
if [ -f "$FILENAME" ]; then
  rm $FILENAME
fi

cat <<EOT >> $FILENAME
#!/bin/bash
# reset
user="\$1"
domain="\$2"
ip="\$3"
home_dir="\$4"
docroot="$5"

sed -i 's/9080/8080/g' /home/\$user/conf/web/\$domain.nginx.conf
sed -i 's/9080/8443/g' /home/\$user/conf/web/\$domain.nginx.ssl.conf 2>/dev/null
sed -i 's/http\:/https\:/g' /home/\$user/conf/web/\$domain.nginx.ssl.conf 2>/dev/null
nginx -s reload
EOT
chmod 755 $FILENAME


# http or apache !
FILENAME="/usr/local/vesta/data/templates/web/$HTTPD_SERVER/php$MIDDLEWARE_PHP_VERSION.sh"
if [ -f "$FILENAME" ]; then
  rm $FILENAME
fi

cat <<EOT >> $FILENAME
#!/bin/bash
# Adding php wrapper
user="\$1"
domain="\$2"
ip="\$3"
home_dir="\$4"
docroot="\$5"

groupadd -g 82 www-data
useradd -u 82 -g 82 www-data
chown -R www-data /home/\$user/web/\$domain/public_html

mv -f /home/\$user/conf/web/\$domain.$HTTPD_SERVER.* $ENV_HTTPD_CONFIG_PATH/
touch "/home/\$user/conf/web/\$domain.$HTTPD_SERVER.conf"
touch "/home/\$user/conf/web/\$domain.$HTTPD_SERVER.ssl.conf"
sed -i 's/8080/9080/g' /home/\$user/conf/web/\$domain.nginx.*
sed -i 's/8443/9080/g' /home/\$user/conf/web/\$domain.nginx.*
sed -i 's/https/http/g' /home/\$user/conf/web/\$domain.nginx.ssl.* 2>/dev/null
service nginx restart

users=\`v-list-users | tail -n +3 | awk '{print \$1}'\`
cat /etc/hosts > /root/hosts
for user in \$users; do
        v-list-web-domains \$user | tail -n +3 | awk '{print \$2" "\$1;}' >> /root/hosts
done
sort -u /root/hosts > /etc/hosts

service docker.php.$MIDDLEWARE_PHP_VERSION start
service docker.httpd restart
exit 0
EOT

# chmod 755 "/usr/local/vesta/data/templates/web/$HTTPD_SERVER/php$MIDDLEWARE_PHP_VERSION.sh"
chmod 755 $FILENAME

# service file
# MYSQL_SOCKET=$(mysqladmin variables | grep "| socket" | sed 's/\ //g' | awk -F "|" '{print $3}')

# if [ -z $MYSQL_SOCKET ]; then
#   # TODO: Fix
#   MYSQL_SOCKET="/var/run/mysqld/mysqld.sock"
# fi

FILENAME="/etc/systemd/system/docker.php.$MIDDLEWARE_PHP_VERSION.service"
if [ -f "$FILENAME" ]; then
  rm $FILENAME
fi
cat <<EOT >> $FILENAME
[Unit]
Description=PHP $MIDDLEWARE_PHP_VERSION Container
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop php-$MIDDLEWARE_PHP_VERSION
ExecStartPre=-/usr/bin/docker rm php-$MIDDLEWARE_PHP_VERSION
ExecStartPre=/usr/bin/docker pull $DOCKER_HUB_REPO:$MIDDLEWARE_PHP_VERSION
ExecStart=/usr/bin/docker run --rm --network host --cpus=2 -v /etc/passwd:/etc/passwd -v /etc/group:/etc/group -v /etc/hosts:/etc/hosts -v $MYSQL_SOCKET:/var/run/mysqld/ -v $MIDDLEWARE_PHP_CONF:/usr/local/etc/php/conf.d/docker.ini -v /home:/home --name php-$MIDDLEWARE_PHP_VERSION $DOCKER_HUB_REPO:$MIDDLEWARE_PHP_VERSION

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl start docker.httpd
# systemctl start docker.php.$MIDDLEWARE_PHP_VERSION

exit 0
