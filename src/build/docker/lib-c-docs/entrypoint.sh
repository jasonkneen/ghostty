#!/bin/sh
if [ "$ADD_NOINDEX_HEADER" = "true" ]; then
    cat > /etc/nginx/conf.d/noindex.conf << 'EOF'
server {
    listen 80;
    location / {
        root /usr/share/nginx/html;
        index index.html;
        add_header X-Robots-Tag "noindex, nofollow" always;
    }
}
EOF
    # Remove default server config
    rm -f /etc/nginx/conf.d/default.conf
fi
exec nginx -g "daemon off;"
