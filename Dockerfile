FROM node:8

RUN mkdir /app

WORKDIR /app

COPY . /app

RUN rm -Rf ./node_modules

RUN npm install

RUN npm install elm

RUN npm run build

FROM nginx:1.15

COPY --from=0 /app /usr/share/nginx/html

COPY ./nginx.conf /etc/nginx/conf.d/default.conf
