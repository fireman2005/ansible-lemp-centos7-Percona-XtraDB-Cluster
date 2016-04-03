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
mysql -u root <<-EOF
UPDATE mysql.user SET Password=PASSWORD('$DATABASE_PW') WHERE User='root';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOF

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
systemctl start mysql@bootstrap.service
#Запуск последующих узлов
#systemctl start mysql.service

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

#Установка Wordpress
#Пользователь Wordpress
mysql -u root -p cfvfhf2016 <<-EOF
CREATE USER 'wordpress_user'@'localhost' IDENTIFIED BY 'cfvfhf2016';
GRANT ALL PRIVILEGES ON *.* TO wordpress_user@'%' IDENTIFIED BY 'cfvfhf2016';
FLUSH PRIVILEGES;
EOF

mysql -u root -p cfvfhf2016 <<-EOF
CREATE DATABASE wordpress;
USE wordpress;
#
# Structure for table "wp_commentmeta"
#
DROP TABLE IF EXISTS `wp_commentmeta`;
CREATE TABLE `wp_commentmeta` (
  `meta_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `comment_id` bigint(20) unsigned NOT NULL DEFAULT '0',
  `meta_key` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `meta_value` longtext COLLATE utf8mb4_unicode_ci,
  PRIMARY KEY (`meta_id`),
  KEY `comment_id` (`comment_id`),
  KEY `meta_key` (`meta_key`(191))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_commentmeta"
#


#
# Structure for table "wp_comments"
#

DROP TABLE IF EXISTS `wp_comments`;
CREATE TABLE `wp_comments` (
  `comment_ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `comment_post_ID` bigint(20) unsigned NOT NULL DEFAULT '0',
  `comment_author` tinytext COLLATE utf8mb4_unicode_ci NOT NULL,
  `comment_author_email` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `comment_author_url` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `comment_author_IP` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `comment_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `comment_date_gmt` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `comment_content` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `comment_karma` int(11) NOT NULL DEFAULT '0',
  `comment_approved` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '1',
  `comment_agent` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `comment_type` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `comment_parent` bigint(20) unsigned NOT NULL DEFAULT '0',
  `user_id` bigint(20) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`comment_ID`),
  KEY `comment_post_ID` (`comment_post_ID`),
  KEY `comment_approved_date_gmt` (`comment_approved`,`comment_date_gmt`),
  KEY `comment_date_gmt` (`comment_date_gmt`),
  KEY `comment_parent` (`comment_parent`),
  KEY `comment_author_email` (`comment_author_email`(10))
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_comments"
#

INSERT INTO `wp_comments` VALUES (3,1,'Мистер WordPress','','https://wordpress.org/','','2016-03-29 01:13:07','2016-03-28 22:13:07','Привет! Это комментарий.\nЧтобы удалить его, авторизуйтесь и просмотрите комментарии к записи. Там будут ссылки для их изменения или удаления.',0,'1','','',0,0);

#
# Structure for table "wp_links"
#

DROP TABLE IF EXISTS `wp_links`;
CREATE TABLE `wp_links` (
  `link_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `link_url` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `link_name` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `link_image` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `link_target` varchar(25) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `link_description` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `link_visible` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'Y',
  `link_owner` bigint(20) unsigned NOT NULL DEFAULT '1',
  `link_rating` int(11) NOT NULL DEFAULT '0',
  `link_updated` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `link_rel` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `link_notes` mediumtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `link_rss` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`link_id`),
  KEY `link_visible` (`link_visible`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_links"
#


#
# Structure for table "wp_options"
#

DROP TABLE IF EXISTS `wp_options`;
CREATE TABLE `wp_options` (
  `option_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `option_name` varchar(191) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `option_value` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `autoload` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'yes',
  PRIMARY KEY (`option_id`),
  UNIQUE KEY `option_name` (`option_name`)
) ENGINE=InnoDB AUTO_INCREMENT=880 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_options"
#

INSERT INTO `wp_options` VALUES (3,'siteurl','http://192.168.100.205','yes'),(6,'home','http://192.168.100.205','yes'),(9,'blogname','CentOS Cluster','yes'),(12,'blogdescription','Ещё один сайт на WordPress','yes'),(15,'users_can_register','0','yes'),(18,'admin_email','fireman_2005@mail.ru','yes'),(21,'start_of_week','1','yes'),(24,'use_balanceTags','0','yes'),(27,'use_smilies','1','yes'),(30,'require_name_email','1','yes'),(33,'comments_notify','1','yes'),(36,'posts_per_rss','10','yes'),(39,'rss_use_excerpt','0','yes'),(42,'mailserver_url','mail.example.com','yes'),(45,'mailserver_login','login@example.com','yes'),(48,'mailserver_pass','password','yes'),(51,'mailserver_port','110','yes'),(54,'default_category','1','yes'),(57,'default_comment_status','open','yes'),(60,'default_ping_status','open','yes'),(63,'default_pingback_flag','1','yes'),(66,'posts_per_page','10','yes'),(69,'date_format','d.m.Y','yes'),(72,'time_format','H:i','yes'),(75,'links_updated_date_format','d.m.Y H:i','yes'),(78,'comment_moderation','0','yes'),(81,'moderation_notify','1','yes'),(84,'permalink_structure','','yes'),(87,'hack_file','0','yes'),(90,'blog_charset','UTF-8','yes'),(93,'moderation_keys','','no'),(96,'active_plugins','a:0:{}','yes'),(99,'category_base','','yes'),(102,'ping_sites','http://rpc.pingomatic.com/','yes'),(105,'comment_max_links','2','yes'),(108,'gmt_offset','3','yes'),(111,'default_email_category','1','yes'),(114,'recently_edited','','no'),(117,'template','twentysixteen','yes'),(120,'stylesheet','twentysixteen','yes'),(123,'comment_whitelist','1','yes'),(126,'blacklist_keys','','no'),(129,'comment_registration','0','yes'),(132,'html_type','text/html','yes'),(135,'use_trackback','0','yes'),(138,'default_role','subscriber','yes'),(141,'db_version','35700','yes'),(144,'uploads_use_yearmonth_folders','1','yes'),(147,'upload_path','','yes'),(150,'blog_public','1','yes'),(153,'default_link_category','2','yes'),(156,'show_on_front','posts','yes'),(159,'tag_base','','yes'),(162,'show_avatars','1','yes'),(165,'avatar_rating','G','yes'),(168,'upload_url_path','','yes'),(171,'thumbnail_size_w','150','yes'),(174,'thumbnail_size_h','150','yes'),(177,'thumbnail_crop','1','yes'),(180,'medium_size_w','300','yes'),(183,'medium_size_h','300','yes'),(186,'avatar_default','mystery','yes'),(189,'large_size_w','1024','yes'),(192,'large_size_h','1024','yes'),(195,'image_default_link_type','none','yes'),(198,'image_default_size','','yes'),(201,'image_default_align','','yes'),(204,'close_comments_for_old_posts','0','yes'),(207,'close_comments_days_old','14','yes'),(210,'thread_comments','1','yes'),(213,'thread_comments_depth','5','yes'),(216,'page_comments','0','yes'),(219,'comments_per_page','50','yes'),(222,'default_comments_page','newest','yes'),(225,'comment_order','asc','yes'),(228,'sticky_posts','a:0:{}','yes'),(231,'widget_categories','a:2:{i:2;a:4:{s:5:\"title\";s:0:\"\";s:5:\"count\";i:0;s:12:\"hierarchical\";i:0;s:8:\"dropdown\";i:0;}s:12:\"_multiwidget\";i:1;}','yes'),(234,'widget_text','a:0:{}','yes'),(237,'widget_rss','a:0:{}','yes'),(240,'uninstall_plugins','a:0:{}','no'),(243,'timezone_string','','yes'),(246,'page_for_posts','0','yes'),(249,'page_on_front','0','yes'),(252,'default_post_format','0','yes'),(255,'link_manager_enabled','0','yes'),(258,'finished_splitting_shared_terms','1','yes'),(261,'site_icon','0','yes'),(264,'medium_large_size_w','768','yes'),(267,'medium_large_size_h','0','yes'),(270,'initial_db_version','35700','yes'),(273,'wp_user_roles','a:5:{s:13:\"administrator\";a:2:{s:4:\"name\";s:13:\"Administrator\";s:12:\"capabilities\";a:61:{s:13:\"switch_themes\";b:1;s:11:\"edit_themes\";b:1;s:16:\"activate_plugins\";b:1;s:12:\"edit_plugins\";b:1;s:10:\"edit_users\";b:1;s:10:\"edit_files\";b:1;s:14:\"manage_options\";b:1;s:17:\"moderate_comments\";b:1;s:17:\"manage_categories\";b:1;s:12:\"manage_links\";b:1;s:12:\"upload_files\";b:1;s:6:\"import\";b:1;s:15:\"unfiltered_html\";b:1;s:10:\"edit_posts\";b:1;s:17:\"edit_others_posts\";b:1;s:20:\"edit_published_posts\";b:1;s:13:\"publish_posts\";b:1;s:10:\"edit_pages\";b:1;s:4:\"read\";b:1;s:8:\"level_10\";b:1;s:7:\"level_9\";b:1;s:7:\"level_8\";b:1;s:7:\"level_7\";b:1;s:7:\"level_6\";b:1;s:7:\"level_5\";b:1;s:7:\"level_4\";b:1;s:7:\"level_3\";b:1;s:7:\"level_2\";b:1;s:7:\"level_1\";b:1;s:7:\"level_0\";b:1;s:17:\"edit_others_pages\";b:1;s:20:\"edit_published_pages\";b:1;s:13:\"publish_pages\";b:1;s:12:\"delete_pages\";b:1;s:19:\"delete_others_pages\";b:1;s:22:\"delete_published_pages\";b:1;s:12:\"delete_posts\";b:1;s:19:\"delete_others_posts\";b:1;s:22:\"delete_published_posts\";b:1;s:20:\"delete_private_posts\";b:1;s:18:\"edit_private_posts\";b:1;s:18:\"read_private_posts\";b:1;s:20:\"delete_private_pages\";b:1;s:18:\"edit_private_pages\";b:1;s:18:\"read_private_pages\";b:1;s:12:\"delete_users\";b:1;s:12:\"create_users\";b:1;s:17:\"unfiltered_upload\";b:1;s:14:\"edit_dashboard\";b:1;s:14:\"update_plugins\";b:1;s:14:\"delete_plugins\";b:1;s:15:\"install_plugins\";b:1;s:13:\"update_themes\";b:1;s:14:\"install_themes\";b:1;s:11:\"update_core\";b:1;s:10:\"list_users\";b:1;s:12:\"remove_users\";b:1;s:13:\"promote_users\";b:1;s:18:\"edit_theme_options\";b:1;s:13:\"delete_themes\";b:1;s:6:\"export\";b:1;}}s:6:\"editor\";a:2:{s:4:\"name\";s:6:\"Editor\";s:12:\"capabilities\";a:34:{s:17:\"moderate_comments\";b:1;s:17:\"manage_categories\";b:1;s:12:\"manage_links\";b:1;s:12:\"upload_files\";b:1;s:15:\"unfiltered_html\";b:1;s:10:\"edit_posts\";b:1;s:17:\"edit_others_posts\";b:1;s:20:\"edit_published_posts\";b:1;s:13:\"publish_posts\";b:1;s:10:\"edit_pages\";b:1;s:4:\"read\";b:1;s:7:\"level_7\";b:1;s:7:\"level_6\";b:1;s:7:\"level_5\";b:1;s:7:\"level_4\";b:1;s:7:\"level_3\";b:1;s:7:\"level_2\";b:1;s:7:\"level_1\";b:1;s:7:\"level_0\";b:1;s:17:\"edit_others_pages\";b:1;s:20:\"edit_published_pages\";b:1;s:13:\"publish_pages\";b:1;s:12:\"delete_pages\";b:1;s:19:\"delete_others_pages\";b:1;s:22:\"delete_published_pages\";b:1;s:12:\"delete_posts\";b:1;s:19:\"delete_others_posts\";b:1;s:22:\"delete_published_posts\";b:1;s:20:\"delete_private_posts\";b:1;s:18:\"edit_private_posts\";b:1;s:18:\"read_private_posts\";b:1;s:20:\"delete_private_pages\";b:1;s:18:\"edit_private_pages\";b:1;s:18:\"read_private_pages\";b:1;}}s:6:\"author\";a:2:{s:4:\"name\";s:6:\"Author\";s:12:\"capabilities\";a:10:{s:12:\"upload_files\";b:1;s:10:\"edit_posts\";b:1;s:20:\"edit_published_posts\";b:1;s:13:\"publish_posts\";b:1;s:4:\"read\";b:1;s:7:\"level_2\";b:1;s:7:\"level_1\";b:1;s:7:\"level_0\";b:1;s:12:\"delete_posts\";b:1;s:22:\"delete_published_posts\";b:1;}}s:11:\"contributor\";a:2:{s:4:\"name\";s:11:\"Contributor\";s:12:\"capabilities\";a:5:{s:10:\"edit_posts\";b:1;s:4:\"read\";b:1;s:7:\"level_1\";b:1;s:7:\"level_0\";b:1;s:12:\"delete_posts\";b:1;}}s:10:\"subscriber\";a:2:{s:4:\"name\";s:10:\"Subscriber\";s:12:\"capabilities\";a:2:{s:4:\"read\";b:1;s:7:\"level_0\";b:1;}}}','yes'),(276,'WPLANG','ru_RU','yes'),(279,'widget_search','a:2:{i:2;a:1:{s:5:\"title\";s:0:\"\";}s:12:\"_multiwidget\";i:1;}','yes'),(282,'widget_recent-posts','a:2:{i:2;a:2:{s:5:\"title\";s:0:\"\";s:6:\"number\";i:5;}s:12:\"_multiwidget\";i:1;}','yes'),(285,'widget_recent-comments','a:2:{i:2;a:2:{s:5:\"title\";s:0:\"\";s:6:\"number\";i:5;}s:12:\"_multiwidget\";i:1;}','yes'),(288,'widget_archives','a:2:{i:2;a:3:{s:5:\"title\";s:0:\"\";s:5:\"count\";i:0;s:8:\"dropdown\";i:0;}s:12:\"_multiwidget\";i:1;}','yes'),(291,'widget_meta','a:2:{i:2;a:1:{s:5:\"title\";s:0:\"\";}s:12:\"_multiwidget\";i:1;}','yes'),(294,'sidebars_widgets','a:3:{s:19:\"wp_inactive_widgets\";a:0:{}s:9:\"sidebar-1\";a:6:{i:0;s:8:\"search-2\";i:1;s:14:\"recent-posts-2\";i:2;s:17:\"recent-comments-2\";i:3;s:10:\"archives-2\";i:4;s:12:\"categories-2\";i:5;s:6:\"meta-2\";}s:13:\"array_version\";i:3;}','yes'),(302,'widget_pages','a:1:{s:12:\"_multiwidget\";i:1;}','yes'),(305,'widget_calendar','a:1:{s:12:\"_multiwidget\";i:1;}','yes'),(308,'widget_tag_cloud','a:1:{s:12:\"_multiwidget\";i:1;}','yes'),(311,'widget_nav_menu','a:1:{s:12:\"_multiwidget\";i:1;}','yes'),(314,'cron','a:3:{i:1459695611;a:1:{s:16:\"wp_version_check\";a:1:{s:32:\"40cd750bba9870f18aada2478b24840a\";a:2:{s:8:\"schedule\";b:0;s:4:\"args\";a:0:{}}}}i:1459721599;a:3:{s:16:\"wp_version_check\";a:1:{s:32:\"40cd750bba9870f18aada2478b24840a\";a:3:{s:8:\"schedule\";s:10:\"twicedaily\";s:4:\"args\";a:0:{}s:8:\"interval\";i:43200;}}s:17:\"wp_update_plugins\";a:1:{s:32:\"40cd750bba9870f18aada2478b24840a\";a:3:{s:8:\"schedule\";s:10:\"twicedaily\";s:4:\"args\";a:0:{}s:8:\"interval\";i:43200;}}s:16:\"wp_update_themes\";a:1:{s:32:\"40cd750bba9870f18aada2478b24840a\";a:3:{s:8:\"schedule\";s:10:\"twicedaily\";s:4:\"args\";a:0:{}s:8:\"interval\";i:43200;}}}s:7:\"version\";i:2;}','yes'),(318,'_site_transient_update_core','O:8:\"stdClass\":4:{s:7:\"updates\";a:1:{i:0;O:8:\"stdClass\":10:{s:8:\"response\";s:6:\"latest\";s:8:\"download\";s:65:\"https://downloads.wordpress.org/release/ru_RU/wordpress-4.4.2.zip\";s:6:\"locale\";s:5:\"ru_RU\";s:8:\"packages\";O:8:\"stdClass\":5:{s:4:\"full\";s:65:\"https://downloads.wordpress.org/release/ru_RU/wordpress-4.4.2.zip\";s:10:\"no_content\";b:0;s:11:\"new_bundled\";b:0;s:7:\"partial\";b:0;s:8:\"rollback\";b:0;}s:7:\"current\";s:5:\"4.4.2\";s:7:\"version\";s:5:\"4.4.2\";s:11:\"php_version\";s:5:\"5.2.4\";s:13:\"mysql_version\";s:3:\"5.0\";s:11:\"new_bundled\";s:3:\"4.4\";s:15:\"partial_version\";s:0:\"\";}}s:12:\"last_checked\";i:1459688411;s:15:\"version_checked\";s:5:\"4.4.2\";s:12:\"translations\";a:0:{}}','yes'),(319,'_transient_is_multi_author','0','yes'),(322,'_transient_twentysixteen_categories','1','yes'),(336,'_site_transient_update_themes','O:8:\"stdClass\":4:{s:12:\"last_checked\";i:1459688414;s:7:\"checked\";a:3:{s:13:\"twentyfifteen\";s:3:\"1.4\";s:14:\"twentyfourteen\";s:3:\"1.6\";s:13:\"twentysixteen\";s:3:\"1.1\";}s:8:\"response\";a:0:{}s:12:\"translations\";a:0:{}}','yes'),(872,'_site_transient_timeout_theme_roots','1459690212','yes'),(875,'_site_transient_theme_roots','a:3:{s:13:\"twentyfifteen\";s:7:\"/themes\";s:14:\"twentyfourteen\";s:7:\"/themes\";s:13:\"twentysixteen\";s:7:\"/themes\";}','yes'),(878,'_site_transient_update_plugins','O:8:\"stdClass\":4:{s:12:\"last_checked\";i:1459688414;s:8:\"response\";a:1:{s:19:\"akismet/akismet.php\";O:8:\"stdClass\":8:{s:2:\"id\";s:2:\"15\";s:4:\"slug\";s:7:\"akismet\";s:6:\"plugin\";s:19:\"akismet/akismet.php\";s:11:\"new_version\";s:6:\"3.1.10\";s:3:\"url\";s:38:\"https://wordpress.org/plugins/akismet/\";s:7:\"package\";s:57:\"https://downloads.wordpress.org/plugin/akismet.3.1.10.zip\";s:6:\"tested\";s:3:\"4.5\";s:13:\"compatibility\";b:0;}}s:12:\"translations\";a:0:{}s:9:\"no_update\";a:1:{s:9:\"hello.php\";O:8:\"stdClass\":6:{s:2:\"id\";s:4:\"3564\";s:4:\"slug\";s:11:\"hello-dolly\";s:6:\"plugin\";s:9:\"hello.php\";s:11:\"new_version\";s:3:\"1.6\";s:3:\"url\";s:42:\"https://wordpress.org/plugins/hello-dolly/\";s:7:\"package\";s:58:\"https://downloads.wordpress.org/plugin/hello-dolly.1.6.zip\";}}}','yes');

#
# Structure for table "wp_postmeta"
#

DROP TABLE IF EXISTS `wp_postmeta`;
CREATE TABLE `wp_postmeta` (
  `meta_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `post_id` bigint(20) unsigned NOT NULL DEFAULT '0',
  `meta_key` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `meta_value` longtext COLLATE utf8mb4_unicode_ci,
  PRIMARY KEY (`meta_id`),
  KEY `post_id` (`post_id`),
  KEY `meta_key` (`meta_key`(191))
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_postmeta"
#

INSERT INTO `wp_postmeta` VALUES (3,2,'_wp_page_template','default');

#
# Structure for table "wp_posts"
#

DROP TABLE IF EXISTS `wp_posts`;
CREATE TABLE `wp_posts` (
  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `post_author` bigint(20) unsigned NOT NULL DEFAULT '0',
  `post_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `post_date_gmt` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `post_content` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `post_title` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `post_excerpt` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `post_status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'publish',
  `comment_status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'open',
  `ping_status` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'open',
  `post_password` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `post_name` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `to_ping` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `pinged` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `post_modified` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `post_modified_gmt` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `post_content_filtered` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `post_parent` bigint(20) unsigned NOT NULL DEFAULT '0',
  `guid` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `menu_order` int(11) NOT NULL DEFAULT '0',
  `post_type` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'post',
  `post_mime_type` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `comment_count` bigint(20) NOT NULL DEFAULT '0',
  PRIMARY KEY (`ID`),
  KEY `post_name` (`post_name`(191)),
  KEY `type_status_date` (`post_type`,`post_status`,`post_date`,`ID`),
  KEY `post_parent` (`post_parent`),
  KEY `post_author` (`post_author`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_posts"
#

INSERT INTO `wp_posts` VALUES (3,3,'2016-03-29 01:13:07','2016-03-28 22:13:07','Добро пожаловать в WordPress. Это ваша первая запись. Отредактируйте или удалите её, затем пишите!','Привет, мир!','','publish','open','open','','%d0%bf%d1%80%d0%b8%d0%b2%d0%b5%d1%82-%d0%bc%d0%b8%d1%80','','','2016-03-29 01:13:07','2016-03-28 22:13:07','',0,'http://192.168.100.205/?p=1',0,'post','',1),(6,3,'2016-03-29 01:13:07','2016-03-28 22:13:07','Это пример страницы. От записей в блоге она отличается тем, что остаётся на одном месте и отображается в меню сайта (в большинстве тем). На странице &laquo;Детали&raquo; владельцы сайтов обычно рассказывают о себе потенциальным посетителям. Например, так:\n\n<blockquote>Привет! Днём я курьер, а вечером &#8212; подающий надежды актёр. Это мой блог. Я живу в Ростове-на-Дону, люблю своего пса Джека и пинаколаду. (И ещё попадать под дождь.)</blockquote>\n\n...или так:\n\n<blockquote>Компания &laquo;Штучки XYZ&raquo; была основана в 1971 году и с тех пор производит качественные штучки. Компания находится в Готэм-сити, имеет штат из более чем 2000 сотрудников и приносит много пользы жителям Готэма.</blockquote>\n\nПерейдите <a href=\"http://192.168.100.205/wp-admin/\">в консоль</a>, чтобы удалить эту страницу и создать новые. Успехов!','Пример страницы','','publish','closed','open','','sample-page','','','2016-03-29 01:13:07','2016-03-28 22:13:07','',0,'http://192.168.100.205/?page_id=2',0,'page','',0);

#
# Structure for table "wp_term_relationships"
#

DROP TABLE IF EXISTS `wp_term_relationships`;
CREATE TABLE `wp_term_relationships` (
  `object_id` bigint(20) unsigned NOT NULL DEFAULT '0',
  `term_taxonomy_id` bigint(20) unsigned NOT NULL DEFAULT '0',
  `term_order` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`object_id`,`term_taxonomy_id`),
  KEY `term_taxonomy_id` (`term_taxonomy_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_term_relationships"
#

INSERT INTO `wp_term_relationships` VALUES (1,3,0);

#
# Structure for table "wp_term_taxonomy"
#

DROP TABLE IF EXISTS `wp_term_taxonomy`;
CREATE TABLE `wp_term_taxonomy` (
  `term_taxonomy_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `term_id` bigint(20) unsigned NOT NULL DEFAULT '0',
  `taxonomy` varchar(32) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `description` longtext COLLATE utf8mb4_unicode_ci NOT NULL,
  `parent` bigint(20) unsigned NOT NULL DEFAULT '0',
  `count` bigint(20) NOT NULL DEFAULT '0',
  PRIMARY KEY (`term_taxonomy_id`),
  UNIQUE KEY `term_id_taxonomy` (`term_id`,`taxonomy`),
  KEY `taxonomy` (`taxonomy`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_term_taxonomy"
#

INSERT INTO `wp_term_taxonomy` VALUES (3,1,'category','',0,1);

#
# Structure for table "wp_termmeta"
#

DROP TABLE IF EXISTS `wp_termmeta`;
CREATE TABLE `wp_termmeta` (
  `meta_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `term_id` bigint(20) unsigned NOT NULL DEFAULT '0',
  `meta_key` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `meta_value` longtext COLLATE utf8mb4_unicode_ci,
  PRIMARY KEY (`meta_id`),
  KEY `term_id` (`term_id`),
  KEY `meta_key` (`meta_key`(191))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_termmeta"
#


#
# Structure for table "wp_terms"
#

DROP TABLE IF EXISTS `wp_terms`;
CREATE TABLE `wp_terms` (
  `term_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `slug` varchar(200) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `term_group` bigint(10) NOT NULL DEFAULT '0',
  PRIMARY KEY (`term_id`),
  KEY `slug` (`slug`(191)),
  KEY `name` (`name`(191))
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_terms"
#

INSERT INTO `wp_terms` VALUES (1,'Без рубрики','%d0%91%d0%b5%d0%b7-%d1%80%d1%83%d0%b1%d1%80%d0%b8%d0%ba%d0%b8',0);

#
# Structure for table "wp_usermeta"
#

DROP TABLE IF EXISTS `wp_usermeta`;
CREATE TABLE `wp_usermeta` (
  `umeta_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL DEFAULT '0',
  `meta_key` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `meta_value` longtext COLLATE utf8mb4_unicode_ci,
  PRIMARY KEY (`umeta_id`),
  KEY `user_id` (`user_id`),
  KEY `meta_key` (`meta_key`(191))
) ENGINE=InnoDB AUTO_INCREMENT=40 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_usermeta"
#

INSERT INTO `wp_usermeta` VALUES (3,3,'nickname','fireman'),(6,3,'first_name',''),(9,3,'last_name',''),(12,3,'description',''),(15,3,'rich_editing','true'),(18,3,'comment_shortcuts','false'),(21,3,'admin_color','fresh'),(24,3,'use_ssl','0'),(27,3,'show_admin_bar_front','true'),(30,3,'wp_capabilities','a:1:{s:13:\"administrator\";b:1;}'),(33,3,'wp_user_level','10'),(36,3,'dismissed_wp_pointers',''),(39,3,'show_welcome_panel','1');

#
# Structure for table "wp_users"
#

DROP TABLE IF EXISTS `wp_users`;
CREATE TABLE `wp_users` (
  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_login` varchar(60) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `user_pass` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `user_nicename` varchar(50) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `user_email` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `user_url` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `user_registered` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `user_activation_key` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  `user_status` int(11) NOT NULL DEFAULT '0',
  `display_name` varchar(250) COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`ID`),
  KEY `user_login_key` (`user_login`),
  KEY `user_nicename` (`user_nicename`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

#
# Data for table "wp_users"
#

INSERT INTO `wp_users` VALUES (3,'fireman','$P$Bnw46JWdyuMRgGdZnYuVxD6dr3OWC/1','fireman','fireman_2005@mail.ru','','2016-03-28 22:13:00','',0,'fireman');
EOF

cd /usr/share/nginx/html/ && wget http://webinar73.ru/wordpress.zip  && unzip wordpress.zip

#Генерация ключей SSH
cd ~
mkdir .ssh
cd .ssh
touch authorized_keys
chmod 700 ./.ssh/authorized_keys
