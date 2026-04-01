FROM nginx:1.29-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY get-started.html /usr/share/nginx/html/get-started.html
COPY llms.txt /usr/share/nginx/html/llms.txt
COPY css/ /usr/share/nginx/html/css/

EXPOSE 3000
