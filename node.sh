#!/usr/bin/env bash
#DATABASE_PW: root password to db
DATABASE_PW='fvfhf2016'

#дополнительные утилиты
yum -y install net-tools.x86_64
yum -y install mc
yum -y install wget
yum -y install unzip

#Настройки безопасности
#Чтобы члены кластера могли общаться друг с другом, на каждом сервере нужно разрешить доступ со всех членов кластера по портам 4444 и 4567. Кроме того, со всех серверов, которые будут использовать кластер БД нужно разрешить доступ на порт 3306 (штатный порт mysq).

iptables -I INPUT -p tcp --dport 4444 -m state --state NEW -j ACCEPT
iptables -I INPUT -p tcp --dport 4567 -m state --state NEW -j ACCEPT
iptables -I INPUT -p tcp --dport 3306 -m state --state NEW -j ACCEPT
iptables -I INPUT -p tcp --dport 80 -m state --state NEW -j ACCEPT
service iptables save
/etc/init.d/iptables restart
firewall-cmd  --permanent --add-port=4444/tcp
firewall-cmd --permanent --add-port=4567/tcp
firewall-cmd --permanent --add-port=4568/tcp
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd  --permanent --add-port=80/tcp
firewall-cmd --reload


# Настройка selinux исправить /etc/sysconfig/selinux "SELINUX=enforcing" to "SELINUX=disabled"
sed -i 's/^SELINUX=enforcing*/SELINUX=disabled/' /etc/sysconfig/selinux


yum -y install https://www.percona.com/redir/downloads/percona-release/redhat/0.1-3/percona-release-0.1-3.noarch.rpm

yum -y install Percona-Server-client-56 Percona-Server-server-56
systemctl start mysql.service

mv /etc/my.cnf /etc/my.cnf.bkp
cat >> /etc/my.cnf << EOF
# Percona Server template configuration
[mysqld]
#
# Remove leading # and set to the amount of RAM for the most important data
# cache in MySQL. Start at 70% of total RAM for dedicated server, else 10%.
# innodb_buffer_pool_size = 128M
#
# Remove leading # to turn on a very important data integrity option: logging
# changes to the binary log between backups.
# log_bin
#
# Remove leading # to set options mainly useful for reporting servers.
# The server defaults are faster for transactions and fast SELECTs.
# Adjust sizes as needed, experiment to find the optimal values.
# join_buffer_size = 128M
# sort_buffer_size = 2M
# read_rnd_buffer_size = 2M
datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
# Disabling symbolic-links is recommended to prevent assorted security risks
symbolic-links=0
[mysqld_safe]
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
EOF

systemctl restart mysql.service

#Настройка безоасности MySQL аналог mysql_secure_installation
#mysql -u root <<-EOF
#UPDATE mysql.user SET Password=PASSWORD('$DATABASE_PW') WHERE User='root';
#DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
#DELETE FROM mysql.user WHERE User='';
#DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
#FLUSH PRIVILEGES;
#EOF

yum clean all && yum makecache

#надо удалить mysql-libs, иначе перкона не встанет, они конфликтуют.
#перкона сама по зависимостям из репозитария вытащит их. но из своего.
yum -y remove mysql-libs

yum -y install Percona-XtraDB-Cluster-56
	
#Настройка кластера
#Добавим в /etc/my.cnf (в debian он может называться /etc/mysql/my.cnf - если он уже есть - правим его!) следующие строки:

mv /etc/my.cnf /etc/my.cnf.bkp
cat >> /etc/my.cnf << EOF
# Template my.cnf for PXC
# Edit to your requirements.
[mysqld]
log_bin
binlog_format                  = ROW
innodb_buffer_pool_size        = 100M
innodb_flush_log_at_trx_commit = 0
innodb_flush_method            = O_DIRECT
innodb_log_files_in_group      = 2
innodb_log_file_size           = 20M
innodb_file_per_table          = 1
datadir                        = /var/lib/mysql
user                           = mysql
wsrep_cluster_address          = gcomm://192.168.100.201,192.168.100.202,192.168.100.203
wsrep_provider                 = /usr/lib64/galera3/libgalera_smm.so
default_storage_engine         = InnoDB
wsrep_slave_threads            = 8
wsrep_cluster_name             = Cluster-DB
wsrep_node_name                = Node01-DB
wsrep_node_address             = 192.168.100.201
wsrep_sst_method               = xtrabackup-v2
wsrep_sst_auth                 = "syncuser:cfvfhf2016"
innodb_locks_unsafe_for_binlog = 1
innodb_autoinc_lock_mode       = 2
[mysqld_safe]
pid-file = /run/mysqld/mysql.pid
syslog
!includedir /etc/my.cnf.d
EOF
#Запуск первого узла кластера
#systemctl start mysql@bootstrap.service
#Запуск последующих узлов
systemctl start mysql.service

#создадим пользователя для синхронизации
mysql -u root -p cfvfhf2016 <<-EOF
CREATE USER 'syncuser'@'localhost' IDENTIFIED BY 'cfvfhf2016';
GRANT RELOAD, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'syncuser'@'localhost';
FLUSH PRIVILEGES;
EOF

#Установка LEMP

#Сначала для получения последней версии пакета добавим официальный репозиторий
cat >> /etc/yum.repos.d/nginx.repo << EOF
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/7/$basearch/
gpgcheck=0
enabled=1
EOF

yum -y install nginx

service nginx start
chkconfig nginx on
#systemctl enable nginx.service

#Установка интерпретатора PHP.

yum -y install php-fpm php php-mysql

#По умолчанию PHP-FPM работает на сетевом порту 9000. Я же для повышения как безопасности так и производительности запускаю его на доменном сокете.
#Для этого в файле /etc/php-fpm.d/www.conf необходимо поменять строку listen = 127.0.0.1:9000 на listen = /var/run/php-fpm/php-fpm.sock
#или быстрее просто

sed -i 's/^listen = 127.*/listen = \/var\/run\/php-fpm\/php-fpm.sock/' /etc/php-fpm.d/www.conf

#Кроме того по умолчанию есть параметр, который необходимо раскоментировать(удалив перед ним «;«) и заменить значение с 1 на 0 из соображений безопасности в /etc/php.ini
sed -i 's/^;cgi.fix_pathinfo=1*/cgi.fix_pathinfo=0/' /etc/php.ini

systemctl start php-fpm.service

systemctl enable php-fpm.service

#необходимо настроить вебсервер и менеджер процессов FastCGI. Конфиг имеет следующий вид:

mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bkp
cat >> /etc/nginx/conf.d/default.conf << EOF
server {
    listen       80 default;
    server_name  localhost;
    root   /usr/share/nginx/html;
    index index.php index.html index.htm;

    #access_log  /var/log/nginx/log/host.access.log  main;
    location / {
	try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }

    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF

# Можно перезапустить сервер
systemctl restart nginx.service
#Установка haproxy
yum -y install haproxy
mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bkp
cat >> /etc/haproxy/haproxy.cfg << EOF
global
    log         127.0.0.1 local2 info
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn<--->4096
    user        haproxy
    group       haproxy
    daemon
defaults
    log                     global
    mode                    tcp
    option                  tcplog
    option                  dontlognull
    option                  redispatch
    retries                 3
    timeout connect         10s
    timeout client          30s
    timeout server          30s
listen mysql-proxy *:3306
    balance<--->roundrobin
    option<---->tcplog
    server<---->node01-db 192.168.100.201:3306 check port 3306
    server<---->node02-db 192.168.100.202:3306 check port 3306
    server<---->node03-db 192.168.100.203:3306 check port 3306
EOF
systemctl start haproxy 
systemctl enable haproxy
#Синхронизация контента
yum -y install rsync
#Генерация ключей SSH
cd ~
mkdir .ssh
cd .ssh
ssh-keygen -y -t rsa -b 1024
cat .ssh/id_rsa.pub | ssh root@192.168.100.201 'cat >> .ssh/authorized_keys'

cat >> /bin/sh/backup/rsync.sh << EOF
rsync -avzhe ssh 192.168.100.201:/usr/share/nginx/html/ /usr/share/nginx/html/
rsync -avzhe ssh  /usr/share/nginx/html/  192.168.100.201:/usr/share/nginx/html/
EOF
crontab -e <<-EOF
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
HOME=/
*/5 * * * * /bin/sh/backup/rsync.sh
EOF

