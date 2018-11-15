# 此 Dockerfile 使用了多阶段构建，同时构建了 PHP 及 NGINX 两个镜像
#
# @link https://docs.docker.com/engine/reference/builder/
# @link https://docs.docker.com/develop/develop-images/multistage-build/
# @link https://laravel-news.com/multi-stage-docker-builds-for-laravel
#
# 只有 git 打了 tag 才能将对应的镜像部署到生产环境
#
# !! 搜索 /app/EXAMPLE 替换为自己的项目目录 !!

ARG NODE_VERSION=11.1.0
ARG PHP_VERSION=7.2.12
ARG NGINX_VERSION=1.15.6
ARG DOCKER_HUB_USERNAME=khs1994

# 1.前端构建
FROM node:${NODE_VERSION:-11.1.0}-alpine as frontend

ARG NODE_REGISTRY=https://registry.npmjs.org

# COPY package.json webpack.mix.js yarn.lock /app/
# COPY package.json webpack.mix.js /app/

# COPY package.json webpack.mix.js package-lock.json /app/
COPY package.json webpack.mix.js /app/

RUN cd /app \
      # && yarn install \
      && npm install --registry=${NODE_REGISTRY}

COPY resources/assets/ /app/resources/assets/

RUN cd /app \
      && set PATH=./node_modules/.bin:$PATH \
      # && yarn production \
      && npm run production

# 2.安装 composer 依赖
FROM ${DOCKER_HUB_USERNAME:-khs1994}/php:7.2.12-composer-alpine as composer

# COPY composer.json composer.lock /app/EXAMPLE/
COPY composer.json /app/
COPY database/ /app/database/

RUN cd /app \
      && composer install --no-dev \
             --ignore-platform-reqs \
             --prefer-dist \
             --no-interaction \
             --no-scripts \
             --no-plugins

# 3.将项目打入 PHP 镜像
# $ docker build -t khs1994/php:7.2.12-pro-GIT_TAG-alpine --target=php .
FROM ${DOCKER_HUB_USERNAME:-khs1994}/php:${PHP_VERSION}-fpm-alpine as bundle

COPY . /app
COPY --from=composer /app/vendor/ /app/vendor/
COPY --from=frontend /app/public/js/ /app/public/js/
COPY --from=frontend /app/public/css/ /app/public/css/
COPY --from=frontend /app/mix-manifest.json /app/mix-manifest.json

# 4. 将多个文件合并到一层
FROM ${DOCKER_HUB_USERNAME:-khs1994}/php:${PHP_VERSION}-fpm-alpine as php

COPY --from=bundle /app/ /app/EXAMPLE/

CMD ["php-fpm", "-R"]

# 5.将 PHP 项目打入 NGINX 镜像
# Nginx 配置文件统一通过 configs 管理，严禁将配置文件打入镜像
# $ docker build -t khs1994/nginx:1.15.6-pro-GIT_TAG-alpine .

# FROM ${DOCKER_HUB_USERNAME:-khs1994}/nginx:1.15.6-alpine
FROM nginx:${NGINX_VERSION} as nginx

COPY --from=php /app/ /app/

ADD https://raw.githubusercontent.com/khs1994-docker/lnmp-nginx-conf-demo/master/wait-for-php.sh /wait-for-php.sh

RUN rm -rf /etc/nginx/conf.d \
    && chmod +x /wait-for-php.sh

CMD ["/wait-for-php.sh"]
