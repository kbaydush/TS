FROM node:11 AS compiler

LABEL maintainer="<kostiantyn.baidush@gmail.com>"

WORKDIR ./
COPY package.json ./
COPY package-lock.json ./
RUN npm install

COPY . ./
RUN npm run dev
RUN rm -rf ./node_modules/

FROM php:7.2-fpm AS server
RUN set -x \
  && apt-get update -y \
  && apt-get install --no-install-recommends --no-install-suggests -y \
    nginx \
    nginx-extras \
    curl \
    git \
    unzip \
    zlib1g-dev \
  && apt-get clean
RUN docker-php-ext-install zip

WORKDIR ./

ENV TZ=Europe/Kiev
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

ENV COMPOSER_ALLOW_SUPERUSER=1
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
COPY composer.json composer.json
COPY composer.lock composer.lock
RUN composer config -g repos.packagist composer https://packagist.jp
RUN composer global require hirak/prestissimo
RUN composer install \
  --prefer-dist \
  --no-ansi \
  --no-dev \
  --no-interaction \
  --no-progress \
  --no-scripts \
  --no-autoloader \
  && rm -rf /root/.composer

COPY deploy/web/site.conf /etc/nginx/sites-available/default
COPY deploy/web/nginx.conf /etc/nginx/nginx.conf
COPY deploy/web/mime.types /etc/nginx/mime.types
COPY deploy/web/php.ini /usr/local/etc/php/php.ini

# Force HTTPS
ARG FORCE_HTTPS=false
RUN if [ ${FORCE_HTTPS} = true ]; then \
  sed -i 's/# fastcgi_param HTTPS/fastcgi_param HTTPS/' /etc/nginx/sites-available/default \
;fi

COPY --from=compiler ./ ./
RUN composer dump-autoload --no-dev --optimize
RUN grep -q "APP_KEY=base64:HxJ5FeIw6Q9MCkWeIN7j7Uqh9sHp1XZBHD8oGhhyuHM=" || echo "APP_KEY=" >> .env
RUN php artisan key:generate \
  && php artisan config:cache \
  && php artisan route:cache \
  && php artisan view:cache;
RUN chown -R www-data:www-data ./;
RUN rm -rf ./html/ ./deploy/;

EXPOSE 8080 443

CMD service nginx start && php-fpm
