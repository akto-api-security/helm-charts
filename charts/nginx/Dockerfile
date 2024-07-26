# Use Amazon Linux 2023 as the base image
FROM amazonlinux:2023.5.20240701.0

# Switch to root user
USER root

# Set up the yum repository for Nginx
RUN mkdir -p /etc/yum.repos.d && \
    echo -e "[nginx-stable]\n\
name=nginx stable repo\n\
baseurl=http://nginx.org/packages/amzn/2023/\$basearch/\n\
gpgcheck=1\n\
enabled=1\n\
gpgkey=https://nginx.org/keys/nginx_signing.key\n\
module_hotfixes=true\n\
priority=9\n\
\n\
[nginx-mainline]\n\
name=nginx mainline repo\n\
baseurl=http://nginx.org/packages/mainline/amzn/2023/\$basearch/\n\
gpgcheck=1\n\
enabled=0\n\
gpgkey=https://nginx.org/keys/nginx_signing.key\n\
module_hotfixes=true\n\
priority=9\n" > /etc/yum.repos.d/nginx.repo

# Install Nginx and nginx-module-njs
RUN yum install -y nginx nginx-module-njs

# Download and extract Nginx source
RUN yum install -y wget tar && \
    wget http://nginx.org/download/nginx-$(nginx -v 2>&1 | grep -o '[0-9.]*').tar.gz && \
    tar -zxvf nginx-$(nginx -v 2>&1 | grep -o '[0-9.]*').tar.gz

# Clone nginx-kafka-log-module
RUN yum install -y git && \
    git clone https://github.com/kaltura/nginx-kafka-log-module.git

# Set up the yum repository for Confluent
RUN echo -e "[Confluent-Clients]\n\
name=Confluent Clients repository\n\
baseurl=https://packages.confluent.io/clients/rpm/centos/9/\$basearch\n\
gpgcheck=1\n\
gpgkey=https://packages.confluent.io/clients/rpm/archive.key\n\
enabled=1\n" > /etc/yum.repos.d/confluent.repo

# Install necessary packages and compile the nginx-kafka-log-module
RUN yum install -y librdkafka1 librdkafka-devel pcre pcre-devel && \
    yum groupinstall -y "Development Tools" 

# RUN cd nginx-$(nginx -v 2>&1 | grep -o '[0-9.]*') && \
#     ./configure --with-compat --add-dynamic-module=../nginx-kafka-log-module --with-cc-opt="-I/usr/include" --with-ld-opt="-L/usr/lib" && \
#     make modules && \
#     cp objs/ngx_http_kafka_log_module.so /etc/nginx/modules/

RUN yum install -y wget tar && \
    wget https://github.com/openresty/luajit2/archive/refs/tags/v2.1-20230410.1.tar.gz && \
    tar -zxvf v2.1-20230410.1.tar.gz
RUN cd luajit2-2.1-20230410.1 && make install 

RUN yum install -y wget tar && \
    wget https://github.com/openresty/lua-resty-core/archive/refs/tags/v0.1.28.tar.gz && \
    tar -zxvf v0.1.28.tar.gz
RUN cd lua-resty-core-0.1.28 && make install LUA_LIB_DIR=/usr/local/share/lua/5.1

RUN yum install -y wget tar && \
    wget https://github.com/openresty/lua-resty-lrucache/archive/refs/tags/v0.13.tar.gz && \
    tar -zxvf v0.13.tar.gz
RUN cd lua-resty-lrucache-0.13 && make install LUA_LIB_DIR=/usr/local/share/lua/5.1

RUN yum install -y wget tar && \
    wget https://github.com/vision5/ngx_devel_kit/archive/refs/tags/v0.3.3.tar.gz && \
    tar -zxvf v0.3.3.tar.gz
    
RUN yum install -y wget tar && \
    wget https://github.com/openresty/lua-nginx-module/archive/refs/tags/v0.10.26.tar.gz && \
    tar -zxvf v0.10.26.tar.gz

RUN cd nginx-$(nginx -v 2>&1 | grep -o '[0-9.]*') && \
    export LUAJIT_LIB=/usr/local/lib && \
    export LUAJIT_INC=/usr/local/include/luajit-2.1 && \
    ./configure --with-ld-opt="-Wl,-rpath,/usr/local/lib" --add-dynamic-module=/ngx_devel_kit-0.3.3 --add-dynamic-module=/lua-nginx-module-0.10.26 --with-compat --with-cc-opt="-I/usr/include" --with-ld-opt="-lpcre"  --add-dynamic-module=../nginx-kafka-log-module && \
    make modules && \
    cp objs/ngx_http_lua_module.so /etc/nginx/modules/ && \
    cp objs/ndk_http_module.so /etc/nginx/modules/

# Add the Akto njs code to the nginx njs directory
RUN mkdir -p /etc/nginx/njs
COPY api_log.js /etc/nginx/njs/api_log.js

ENV LD_LIBRARY_PATH=/usr/local/lib
RUN yum install -y vi
# Expose ports (optional)
EXPOSE 80 443

# Command to run Nginx
CMD ["nginx", "-g", "daemon off;"]


# ./configure --with-ld-opt="-Wl,-rpath,/usr/local/lib" --add-dynamic-module=/ngx_devel_kit-0.3.3 --add-dynamic-module=/lua-nginx-module-0.10.26 --with-compat --with-cc-opt="-I/usr/include" --with-ld-opt="-lpcre"