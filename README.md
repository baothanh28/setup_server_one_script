# Server Setup Script

Script tự động cài đặt các service cần thiết cho server mới: PostgreSQL, Nginx, Docker, và NginxUI.

## Yêu cầu

- Hệ điều hành: Ubuntu/Debian hoặc CentOS/RHEL
- Quyền root (sudo)
- Kết nối internet

## Cách sử dụng

### 1. Chuẩn bị file cấu hình

```bash
cp env.example .env
```

### 2. Chỉnh sửa file .env

Mở file `.env` và cấu hình các thông số theo nhu cầu:

- **PostgreSQL**: Mật khẩu, database, user, version
- **Nginx**: Worker processes, domain
- **Docker**: User để thêm vào docker group
- **NginxUI**: Port, host, version

### 3. Chạy script cài đặt

```bash
chmod +x install.sh
sudo ./install.sh
```

## Các service được cài đặt

### PostgreSQL
- Cài đặt PostgreSQL từ official repository
- Tự động tạo database và user nếu được cấu hình
- Hỗ trợ remote access (nếu bật trong .env)

### Nginx
- Cài đặt và cấu hình Nginx
- Tự động start và enable service
- Tạo default site nếu cần

### Docker
- Cài đặt Docker Engine từ official repository
- Cấu hình Docker daemon
- Thêm user vào docker group

### NginxUI
- Tải và cài đặt NginxUI từ GitHub releases
- Tạo systemd service
- Cấu hình tự động với Nginx

## Truy cập NginxUI

NginxUI được cấu hình để chỉ lắng nghe trên localhost (127.0.0.1) để tăng cường bảo mật.

### Cách 1: SSH Tunnel (Khuyến nghị)

Từ máy local, tạo SSH tunnel truy cập NginxUI:
```bash
ssh -L 9000:127.0.0.1:9000 user@your_server_ip
```

Tương tự, bạn có thể SSH tunnel để truy cập trực tiếp vào PostgreSQL (nếu cần):
```bash
# Giả sử PostgreSQL listen trên 127.0.0.1:5432 (mặc định trong script cài đặt)
ssh -L 5432:127.0.0.1:5432 user@your_server_ip
```
Sau đó, bạn có thể dùng các tool như DBeaver, TablePlus, psql… để kết nối PostgreSQL với host = localhost, port = 5432 (chính là qua tunnel).

```
Sau đó truy cập: `http://localhost:9000`

### Cách 2: Truy cập trực tiếp trên server
Nếu bạn đã SSH vào server:
```bash
# Sử dụng curl hoặc wget
curl http://127.0.0.1:9000

# Hoặc sử dụng browser với X11 forwarding
# (cần cấu hình X11 forwarding trong SSH)
```

### Cách 3: Reverse Proxy qua Nginx (Cho production)
Cấu hình Nginx reverse proxy để truy cập từ bên ngoài một cách an toàn (với SSL/TLS).

**Default credentials**: admin/admin (thay đổi ngay sau lần đăng nhập đầu tiên)

## Lưu ý bảo mật

1. **Đổi mật khẩu PostgreSQL** ngay sau khi cài đặt
2. **Đổi mật khẩu NginxUI** ngay sau lần đăng nhập đầu tiên
3. **NginxUI chỉ lắng nghe trên localhost** - đây là cấu hình mặc định để tăng cường bảo mật
4. **Cấu hình firewall** để chỉ cho phép truy cập từ IP cần thiết
5. **Không bật POSTGRES_ALLOW_REMOTE** nếu không cần thiết
6. **Nếu cần truy cập NginxUI từ xa**, sử dụng SSH tunnel hoặc cấu hình reverse proxy với SSL/TLS

## Cấu hình Firewall (tùy chọn)

```bash
# Ubuntu/Debian (ufw)
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
# Không cần mở port 9000 vì NginxUI chỉ chạy trên localhost
sudo ufw enable

# CentOS/RHEL (firewalld)
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
# Không cần mở port 9000 vì NginxUI chỉ chạy trên localhost
sudo firewall-cmd --reload
```

## Kiểm tra trạng thái services

```bash
# Kiểm tra tất cả services
systemctl status postgresql
systemctl status nginx
systemctl status docker
systemctl status nginxui

# Xem logs
journalctl -u nginxui -f
```

## Troubleshooting

### PostgreSQL không start
```bash
sudo systemctl status postgresql
sudo journalctl -u postgresql -n 50
```

### Nginx không start
```bash
sudo nginx -t  # Test configuration
sudo systemctl status nginx
```

### Docker không start
```bash
sudo systemctl status docker
sudo journalctl -u docker -n 50
```

### NginxUI không start
```bash
sudo systemctl status nginxui
sudo journalctl -u nginxui -n 50
# Kiểm tra quyền truy cập
sudo ls -la /opt/nginxui
```

## Hỗ trợ


sed -i 's/\r$//' install.sh

Nếu gặp vấn đề, kiểm tra:
1. Logs của từng service
2. File cấu hình .env
3. Quyền truy cập file/directory
4. Kết nối internet

Setup nginx-ui reverse database stream
Setup nginx-ui