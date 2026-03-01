# Hướng dẫn Setup Reverse Proxy cho Database bằng Nginx

Tài liệu mô tả cách dùng Nginx làm **reverse proxy (TCP stream)** cho database (PostgreSQL, MySQL, Redis), giúp tập trung kết nối qua một cổng, áp dụng giới hạn IP và (tùy chọn) SSL.

## Mục lục

1. [Tại sao dùng Nginx proxy cho database?](#1-tại-sao-dùng-nginx-proxy-cho-database)
2. [Yêu cầu](#2-yêu-cầu)
3. [Cấu hình Nginx Stream cho PostgreSQL](#3-cấu-hình-nginx-stream-cho-postgresql)
4. [Cấu hình cho MySQL và Redis](#4-cấu-hình-cho-mysql-và-redis)
5. [Giới hạn IP (bảo mật)](#5-giới-hạn-ip-bảo-mật)
6. [SSL/TLS cho kết nối database (tùy chọn)](#6-ssltls-cho-kết-nối-database-tùy-chọn)
7. [Cấu hình qua Nginx UI](#7-cấu-hình-qua-nginx-ui)
8. [Firewall và kiểm tra](#8-firewall-và-kiểm-tra)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Tại sao dùng Nginx proxy cho database?

- **Không cần mở PostgreSQL/MySQL ra toàn mạng**: Database vẫn listen trên `127.0.0.1`, chỉ Nginx lắng nghe port công khai (ví dụ `5433`).
- **Một điểm vào**: Có thể proxy nhiều database (PostgreSQL, MySQL, Redis) qua các port khác nhau trên cùng server.
- **Giới hạn IP**: Chỉ cho phép kết nối từ IP hoặc dải IP tin cậy (VPN, office, app server).
- **SSL termination**: Có thể để Nginx nhận kết nối SSL và chuyển tiếp plain TCP tới database (hoặc SSL end-to-end nếu backend hỗ trợ).

**Lưu ý**: Nginx stream proxy **chỉ chuyển tiếp TCP**, không hiểu giao thức database. Mọi xác thực và bảo mật vẫn do database xử lý.

---

## 2. Yêu cầu

- **Nginx** đã cài (script `install.sh` đã cài Nginx).
- **Module stream**: Trên Ubuntu/Debian script đã cài `libnginx-mod-stream`. Kiểm tra:

```bash
# Ubuntu/Debian: module thường đã được load khi cài libnginx-mod-stream
nginx -V 2>&1 | grep -o with-stream

# Hoặc kiểm tra file cấu hình stream có load không
ls /etc/nginx/modules-enabled/ 2>/dev/null | grep stream || true
```

Trên CentOS/RHEL, module stream thường có sẵn trong gói `nginx`. Nếu thiếu:

```bash
yum install -y nginx-mod-stream   # CentOS/RHEL 7/8
```

---

## 3. Cấu hình Nginx Stream cho PostgreSQL

PostgreSQL mặc định listen trên `127.0.0.1:5432`. Ta sẽ để Nginx lắng nghe một port khác (ví dụ `5433`) và proxy TCP tới `127.0.0.1:5432`.

### Bước 1: Tạo file cấu hình stream

Trên Ubuntu/Debian, cấu hình stream thường đặt trong `/etc/nginx/` và được include từ `nginx.conf`.

**Cách 1: Include file stream riêng (khuyến nghị)**

Tạo file:

```bash
sudo nano /etc/nginx/stream.conf
```

Nội dung mẫu:

```nginx
# /etc/nginx/stream.conf
# Reverse proxy TCP cho PostgreSQL

stream {
    log_format proxy '$remote_addr [$time_local] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time';

    server {
        listen 5433;              # Port công khai (client kết nối tới đây)
        proxy_pass 127.0.0.1:5432;  # PostgreSQL thực tế
        proxy_connect_timeout 10s;
        proxy_timeout 30m;
        proxy_buffer_size 16k;
    }
}
```

**Cách 2: Đặt trực tiếp trong nginx.conf**

Mở `/etc/nginx/nginx.conf`, đảm bảo có block `stream { ... }` ở **cùng cấp** với block `http { ... }` (không nằm trong `http`):

```nginx
# Ví dụ cấu trúc nginx.conf
user www-data;
worker_processes auto;
# ...

events {
    worker_connections 1024;
}

http {
    # ... toàn bộ cấu hình http ...
}

# Block stream PHẢI ngoài http
stream {
    include /etc/nginx/stream.conf;
}
```

Nếu dùng **Cách 1**, trong `nginx.conf` (bên ngoài block `http`) thêm:

```nginx
stream {
    include /etc/nginx/stream.conf;
}
```

### Bước 2: Đảm bảo PostgreSQL chỉ listen localhost

Database không cần (và không nên) bind ra `0.0.0.0` khi dùng proxy. Giữ cấu hình mặc định:

- File `postgresql.conf`: `listen_addresses = 'localhost'` (hoặc không set).
- Không bật `POSTGRES_ALLOW_REMOTE=true` trong `.env` nếu chỉ truy cập qua Nginx proxy.

### Bước 3: Test và reload Nginx

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Sau đó từ máy được phép kết nối:

```bash
psql -h <IP_SERVER> -p 5433 -U postgres -d dev
```

---

## 4. Cấu hình cho MySQL và Redis

Cùng cơ chế stream, chỉ khác port backend và port proxy.

### MySQL (port 3306)

Thêm vào `stream { }` (trong `stream.conf` hoặc trong block `stream` của `nginx.conf`):

```nginx
server {
    listen 3307;                     # Port công khai
    proxy_pass 127.0.0.1:3306;       # MySQL
    proxy_connect_timeout 10s;
    proxy_timeout 30m;
    proxy_buffer_size 16k;
}
```

### Redis (port 6379)

```nginx
server {
    listen 6380;                     # Port công khai
    proxy_pass 127.0.0.1:6379;       # Redis
    proxy_connect_timeout 5s;
    proxy_timeout 1h;
    proxy_buffer_size 4k;
}
```

Ví dụ `stream.conf` gom nhiều database:

```nginx
stream {
    log_format proxy '$remote_addr [$time_local] $protocol $status $bytes_sent $bytes_received $session_time';

    # PostgreSQL
    server {
        listen 5433;
        proxy_pass 127.0.0.1:5432;
        proxy_connect_timeout 10s;
        proxy_timeout 30m;
        proxy_buffer_size 16k;
    }

    # MySQL (nếu có)
    server {
        listen 3307;
        proxy_pass 127.0.0.1:3306;
        proxy_connect_timeout 10s;
        proxy_timeout 30m;
    }

    # Redis (nếu có)
    server {
        listen 6380;
        proxy_pass 127.0.0.1:6379;
        proxy_connect_timeout 5s;
        proxy_timeout 1h;
    }
}
```

---

## 5. Giới hạn IP (bảo mật)

Chỉ cho phép kết nối từ một số IP/dải IP (ví dụ VPN, office, app server).

Trong từng block `server` của stream, dùng `allow` / `deny`:

```nginx
stream {
    server {
        listen 5433;
        proxy_pass 127.0.0.1:5432;
        proxy_connect_timeout 10s;
        proxy_timeout 30m;

        allow 192.168.1.0/24;   # Mạng nội bộ
        allow 10.0.0.0/8;       # VPN hoặc mạng private
        deny all;
    }
}
```

Hoặc chỉ một IP:

```nginx
allow 203.0.113.50;
deny all;
```

Sau khi sửa: `sudo nginx -t && sudo systemctl reload nginx`.

---

## 6. SSL/TLS cho kết nối database (tùy chọn)

Nếu muốn client kết nối tới Nginx bằng SSL (port 5433), Nginx có thể giải mã và chuyển tiếp plain TCP tới PostgreSQL (hoặc dùng SSL tới backend nếu PostgreSQL được cấu hình SSL).

Ví dụ **SSL termination tại Nginx** (client → Nginx: SSL; Nginx → PostgreSQL: TCP thường):

```nginx
stream {
    server {
        listen 5433 ssl;
        proxy_pass 127.0.0.1:5432;
        proxy_connect_timeout 10s;
        proxy_timeout 30m;

        ssl_certificate     /etc/nginx/ssl/db.example.com.crt;
        ssl_certificate_key /etc/nginx/ssl/db.example.com.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
    }
}
```

Tạo certificate (self-signed hoặc Let's Encrypt cho tên miền trỏ về server):

```bash
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/db.example.com.key \
  -out /etc/nginx/ssl/db.example.com.crt \
  -subj "/CN=db.example.com"
```

Client (DBeaver, psql, ứng dụng) khi kết nối qua port 5433 cần bật SSL và chấp nhận certificate (hoặc dùng CA tin cậy).

---

## 7. Cấu hình qua Nginx UI

Nginx UI thường quản lý cấu hình trong thư mục mà Nginx đọc (ví dụ `/etc/nginx/`). Stream config thường nằm trong file riêng (như `stream.conf`) và được include từ `nginx.conf`.

- **Nếu Nginx UI cho phép chỉnh “Main config” / “nginx.conf”**: Thêm block `stream { include /etc/nginx/stream.conf; }` như trên, sau đó chỉnh nội dung `stream.conf` bằng editor trên server hoặc qua UI (nếu UI hỗ trợ stream).
- **Nếu Nginx UI chỉ quản lý site HTTP**: Tạo và chỉnh file stream **thủ công** trên server (ví dụ `/etc/nginx/stream.conf`) rồi thêm `stream { include /etc/nginx/stream.conf; }` vào `nginx.conf`.

Sau mỗi lần sửa:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Nếu Nginx UI chạy trong Docker và mount volume cấu hình, đảm bảo volume có cả `stream.conf` và `nginx.conf` để Nginx trong container đọc đúng.

---

## 8. Firewall và kiểm tra

- **Chỉ mở port proxy** (ví dụ `5433`) nếu cần truy cập từ xa; **không** mở trực tiếp port database (`5432`) ra internet.

Ubuntu/Debian (ufw):

```bash
# Chỉ mở port proxy PostgreSQL (ví dụ 5433)
sudo ufw allow 5433/tcp
# Không mở 5432 ra ngoài
sudo ufw reload
```

CentOS/RHEL (firewalld):

```bash
sudo firewall-cmd --permanent --add-port=5433/tcp
sudo firewall-cmd --reload
```

Kiểm tra:

```bash
# Trên server: Nginx đang listen 5433
ss -tlnp | grep 5433

# Từ client (thay IP_SERVER và user/database)
psql -h IP_SERVER -p 5433 -U postgres -d dev -W
```

---

## 9. Troubleshooting

| Triệu chứng | Gợi ý xử lý |
|-------------|-------------|
| `nginx -t` báo lỗi `unknown directive "stream"` | Chưa load module stream: cài `libnginx-mod-stream` (Ubuntu/Debian) hoặc `nginx-mod-stream` (CentOS); đảm bảo `stream { }` nằm **ngoài** block `http`. |
| Kết nối bị timeout | Kiểm tra firewall (ufw/firewalld) đã mở port proxy (5433); kiểm tra `allow/deny` trong stream không chặn IP client. |
| Connection refused | PostgreSQL có đang chạy và listen trên `127.0.0.1:5432` không: `ss -tlnp \| grep 5432`. |
| Sau khi sửa stream.conf không đổi | Đảm bảo `nginx.conf` có `include /etc/nginx/stream.conf;` trong block `stream { }`, rồi `nginx -t && systemctl reload nginx`. |

---

## Tóm tắt nhanh

| Bước | Hành động |
|------|-----------|
| 1 | Cài module stream (script đã cài `libnginx-mod-stream` trên Ubuntu/Debian). |
| 2 | Tạo `/etc/nginx/stream.conf` với block `stream { server { listen 5433; proxy_pass 127.0.0.1:5432; ... } }`. |
| 3 | Trong `nginx.conf` (ngoài `http`) thêm `stream { include /etc/nginx/stream.conf; }`. |
| 4 | Giữ PostgreSQL listen localhost; không bật `POSTGRES_ALLOW_REMOTE` nếu chỉ dùng proxy. |
| 5 | (Tùy chọn) Thêm `allow`/`deny` theo IP; (tùy chọn) cấu hình SSL trong block `server` stream. |
| 6 | Mở port proxy (5433) trên firewall; test bằng `psql -h IP -p 5433 -U ...`. |

Sau khi hoàn tất, client kết nối tới **port 5433** (hoặc port bạn chọn) trên server, Nginx sẽ chuyển tiếp TCP tới PostgreSQL tại `127.0.0.1:5432`, không cần expose trực tiếp port database ra internet.


stream {
    upstream database_backend {
        server 127.0.0.1:5432;
    }

    server {
        listen 5433; 
        proxy_pass database_backend;
        proxy_connect_timeout 1s;
        proxy_timeout 10m; 
    }
}

Upstream đại diện cho các máy chủ thực tế sẽ xử lý dữ liệu. Trong trường hợp của bạn, đó chính là Database.
Server: Cổng chào (Nơi tiếp nhận)
listen 5433; 
proxy_pass database_backend;
proxy_connect_timeout 1s;
proxy_timeout 10m; 

nc -zv your_server_ip 15432
nc -zv 127.0.0.1 15432

setup xong stream phải restart nginx mới hoạt động ??
systemctl restart nginx

server {
    listen 1986;
    proxy_pass 127.0.0.1:5432;
    proxy_connect_timeout 5s;
    proxy_timeout 60s;
}
nginx -T | grep -n 1986
ss -lntp | grep 1986
nc -zv 127.0.0.1 1986