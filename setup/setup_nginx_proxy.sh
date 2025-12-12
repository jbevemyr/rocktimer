#!/bin/bash
# Optional: configure Nginx to serve RockTimer on port 80 and proxy to :8080
#
# This makes it possible to use:
#   http://rocktimer
# instead of:
#   http://rocktimer:8080

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Run as root (sudo)"
  exit 1
fi

echo "==================================="
echo "RockTimer Nginx Proxy Setup"
echo "==================================="

echo "[1/3] Installing nginx..."
apt-get update
apt-get install -y nginx

echo "[2/3] Writing site config..."
cat > /etc/nginx/sites-available/rocktimer << 'EOF'
server {
    listen 80;
    server_name rocktimer rocktimer.local 192.168.50.1;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default || true
ln -sf /etc/nginx/sites-available/rocktimer /etc/nginx/sites-enabled/rocktimer

echo "[3/3] Restarting nginx..."
nginx -t
systemctl enable nginx
systemctl restart nginx

echo ""
echo "Done."
echo "You can now use:"
echo "  http://rocktimer"
echo "  http://rocktimer.local"
echo "  http://192.168.50.1"


