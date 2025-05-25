FROM php:8.2-apache

RUN docker-php-ext-install mysqli
#sendmail removed
RUN apt update && apt upgrade -y && apt install git nodejs npm netcat-openbsd python3 python3-pip python-is-python3 default-libmysqlclient-dev build-essential python3-dev pkg-config cron unzip curl -y && rm -rf /var/lib/apt/lists/*
RUN cd /tmp && git clone https://github.com/REONTeam/reon.git

WORKDIR /tmp/reon

RUN mv ./web /var/www/ && ls -l /var/www/web
RUN mv vhost.example.conf /etc/apache2/sites-available/gbserver.conf
RUN a2dissite 000-default.conf && a2ensite gbserver.conf
RUN sed -i 's|/var/www/cgb/html/|/var/www/web/htdocs/|g' /etc/apache2/sites-available/gbserver.conf

#PHP y COMPOSER

RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && php -r "if (hash_file('sha384', 'composer-setup.php') === 'dac665fdc30fdd8ec78b38b9800061b4150413ff2e3b6f88543c636f7cd84f6db9189d43a81e5503cda447da73c7e5b6') { echo 'Installer verified'.PHP_EOL; } else { echo 'Installer corrupt'.PHP_EOL; unlink('composer-setup.php'); exit(1); }" && php composer-setup.php && php -r "unlink('composer-setup.php');"
RUN mv composer.phar /var/www/web/composer.phar && cd /var/www/web/ && php composer.phar install && php composer.phar update
RUN a2enmod rewrite

#DATABASE y pasarlas a maria

RUN sed -i 's/`db`/`db_gb_yoshi`/g' tables.sql && head tables.sql
RUN mkdir /shared
RUN echo "CREATE DATABASE db_gb_yoshi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER 'YoshiCrystal'@'%' IDENTIFIED BY '1234'; GRANT ALL ON YoshiCrystal.* TO 'YoshiCrystal'@'%'; FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('root'); GRANT ALL PRIVILEGES ON *.* TO 'YoshiCrystal'@'%' IDENTIFIED BY '1234';" > /shared/init.sql
RUN cp /tmp/reon/tables.sql /shared/tables.sql

#Moving stuff with npm and MAIL
RUN mv config.example.json /var/www/config.json && cd /var/www/web/ && ln -s ../config.json .

RUN sed -i 's/"hostname": "example.net"/"hostname": "localhost"/g' /var/www/config.json && \
    sed -i 's/"email_domain": "example.net"/"email_domain": "mail.example.net"/g' /var/www/config.json && \
    sed -i 's/"email_domain_dion": "xxxx.dion.ne.jp"/"email_domain_dion": "reon.dion.ne.jp"/g' /var/www/config.json && \
    sed -i 's/"mysql_host": "localhost"/"mysql_host": "db"/g' /var/www/config.json && \
    sed -i 's/"mysql_user": "USER"/"mysql_user": "YoshiCrystal"/g' /var/www/config.json && \
    sed -i 's/"mysql_password": "PASS"/"mysql_password": "1234"/g' /var/www/config.json && \
    sed -i 's/"mysql_database": "db"/"mysql_database": "db_gb_yoshi"/g' /var/www/config.json && \
    sed -i 's/"amoj_regist": "h200"/"amoj_regist": "h200"/g' /var/www/config.json
	
RUN curl -o /usr/local/bin/wait-for-it.sh https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh && \
    chmod +x /usr/local/bin/wait-for-it.sh

# Mover archivos a sus ubicaciones finales
RUN mv ./mail /var/www/web/mail && \
    mv /tmp/reon/app /var/www/web/app

# Instalar dependencias de todos los proyectos
RUN cd /var/www/web/mail && npm install && npm update && \
    cd /var/www/web/app/pokemon-exchange && npm install && npm update && \
    cd /var/www/web/app/pokemon-battle && npm install && npm update

#test user
RUN htpasswd -bnBC 10 "test" "1" | tr -d ':\n'

# MOBILE RELAY

RUN git clone https://github.com/REONTeam/mobile-relay.git /usr/local/bin/mobile-relay

WORKDIR /usr/local/bin/mobile-relay

RUN sed -i \
    -e 's/^#\[mysql\]$/\[mysql\]/' \
    -e 's/^#host = localhost$/host = db/' \
    -e 's/^#user = mobile$/user = YoshiCrystal/' \
    -e 's/^#passwd = mobile$/passwd = 1234/' \
    -e 's/^#db = mobile$/db = mobile/' \
    -e 's/^#unix_socket = \/var\/run\/mysqld\/mysqld\.sock$/unix_socket = \/var\/run\/mysqld\/mysqld.sock/' \
    -e 's/^\[sqlite\]$/#[sqlite]/' \
    -e 's/^database = users\.db$/#database = users.db/' \
    config.ini
	
RUN cp create_db.sql /shared/create_db.sql

RUN pip3 install --break-system-packages mysqlclient
RUN chmod +x users.py
RUN chmod +x server.py

# Crear primer script
RUN echo '#!/bin/sh\n'\
'cd /var/www/web/app/pokemon-exchange\n'\
'npm start' > /var/www/web/app/pokemon-exchange/start-pokemon.sh && chmod +x /var/www/web/app/pokemon-exchange/start-pokemon.sh

# Crear segundo script
RUN echo '#!/bin/sh\n'\
'cd /var/www/web/app/pokemon-battle\n'\
'npm start' > /var/www/web/app/pokemon-battle/start-pokemon.sh && chmod +x /var/www/web/app/pokemon-battle/start-pokemon.sh

# Crear una sola entrada de cron con ambas tareas
RUN echo '* * * * * /var/www/web/app/pokemon-exchange/start-pokemon.sh\n'\
'* * * * * /var/www/web/app/pokemon-battle/start-pokemon.sh' \
> /etc/cron.d/pokemon-cron

# Permisos y activar cron
RUN chmod 0644 /etc/cron.d/pokemon-cron && crontab /etc/cron.d/pokemon-cron

# SERVICIO DE NOTICIAS

WORKDIR /tmp/

RUN curl -L "https://cdn.discordapp.com/attachments/1197530253409660971/1299857938411819080/reon_news.zip?ex=68343e4a&is=6832ecca&hm=5567fff9b10da0398457e460cf5fec2a5d4d62598f1dc3364dd2e52f00454d66&" -o /tmp/reon_news.zip

RUN unzip reon_news.zip

WORKDIR /tmp/reon_news

# Edita el archivo add_news.sql IN-PLACE
RUN sed -i -e '1,3 s/reon/db_gb_yoshi/g' \
           -e 's/\/tmp\/reon_news\//\/docker-entrypoint-initdb.d\//g' \
           add_news.sql

# Mueve todos los archivos a /shared
RUN mv * /shared

# Renombra add_news.sql a zadd_news.sql dentro de /shared
RUN mv /shared/add_news.sql /shared/zadd_news.sql

# Muestra el contenido modificado para confirmar
RUN head -n 20 /shared/zadd_news.sql


# Crear el entrypoint.sh que espera a MariaDB y luego lanza tus servicios
RUN echo '#!/bin/sh\n\
set -e\n\
\n\
# Esperar a que MariaDB esté disponible\n\
/usr/local/bin/wait-for-it.sh db:3306 --timeout=30 --strict -- echo "✓ MariaDB está lista"\n\
\n\
# Iniciar servicios\n\
echo "Iniciando mail..."\n\
cd /var/www/web/mail && npm start &\n\
\n\
apache2ctl -D FOREGROUND &\n\
echo "Iniciando scripts python"\n\
python /usr/local/bin/mobile-relay/users.py & \n\
python /usr/local/bin/mobile-relay/server.py \n\
\n\
# Mantener contenedor activo\n\
wait' > /usr/local/bin/entrypoint.sh && \
chmod +x /usr/local/bin/entrypoint.sh

#last
RUN chown -R www-data:www-data /var/www/web/ && chmod -R 775 /var/www/web/

# Usar el entrypoint como comando principal
CMD cron && /usr/local/bin/entrypoint.sh