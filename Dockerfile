FROM oraclelinux:7-slim
ENV MYSQLD_URL https://repo.mysql.com/yum/mysql-5.7-community/docker/x86_64/mysql-community-server-minimal-5.7.18-1.el7.x86_64.rpm
ENV ROUTER_URL https://repo.mysql.com/yum/mysql-tools-community/el/7/x86_64/mysql-router-2.1.3-1.el7.x86_64.rpm

# Install server
RUN rpmkeys --import http://repo.mysql.com/RPM-GPG-KEY-mysql \
  && yum install -y $MYSQLD_URL \
  && yum install -y $ROUTER_URL \
  && yum install -y libpwquality \
  && rm -rf /var/cache/yum/*
RUN mkdir /docker-entrypoint-initdb.d

ADD my.cnf /etc/mysql/my.cnf 

VOLUME /var/lib/mysql

COPY innodb_cluster-entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 3306 6606 33060
CMD [""]

