# Hướng dẫn Setup Cloudflare với Server

Tài liệu này mô tả cách kết nối server của bạn với Cloudflare để sử dụng DNS, proxy, SSL/TLS và bảo vệ DDoS.

## Mục lục

1. [Tạo tài khoản và thêm domain](#1-tạo-tài-khoản-và-thêm-domain)
2. [Cập nhật Nameservers tại nhà đăng ký domain](#2-cập-nhật-nameservers-tại-nhà-đăng-ký-domain)
3. [Thêm DNS Records trỏ về server](#3-thêm-dns-records-trỏ-về-server)
4. [Bật Cloudflare Proxy (Orange Cloud)](#4-bật-cloudflare-proxy-orange-cloud)
5. [Cấu hình SSL/TLS](#5-cấu-hình-ssltls)
6. [Cấu hình Nginx với Cloudflare](#6-cấu-hình-nginx-với-cloudflare)
7. [Một số tùy chọn bảo mật và hiệu năng](#7-một-số-tùy-chọn-bảo-mật-và-hiệu-năng)

---

## 1. Tạo tài khoản và thêm domain

1. Truy cập [Cloudflare](https://www.cloudflare.com) và đăng ký/đăng nhập.
2. Chọn **Add a site**.
3. Nhập domain của bạn (ví dụ: `example.com`) và chọn plan (Free plan đủ cho hầu hết nhu cầu).
4. Cloudflare sẽ quét DNS records hiện tại. Kiểm tra và chỉnh sửa nếu cần.
5. Nhấn **Continue** để xem **Nameservers** mà Cloudflare cung cấp (dạng `xxx.ns.cloudflare.com` và `yyy.ns.cloudflare.com`).

---

## 2. Cập nhật Nameservers tại nhà đăng ký domain

Để Cloudflare quản lý DNS và proxy traffic, bạn cần trỏ domain sang nameservers của Cloudflare:

1. Đăng nhập vào trang quản lý domain tại nhà đăng ký (GoDaddy, Namecheap, FPT, Viettel, v.v.).
2. Tìm mục **Nameservers** / **DNS Settings**.
3. Chọn **Custom Nameservers** (hoặc tương đương) và nhập 2 nameservers mà Cloudflare đã cung cấp, ví dụ:
   - `xxx.ns.cloudflare.com`
   - `yyy.ns.cloudflare.com`
4. Lưu thay đổi. Việc propagate có thể mất từ vài phút đến 48 giờ (thường 15–30 phút).

---

## 3. Thêm DNS Records trỏ về server

Trong Cloudflare Dashboard: **Websites** → chọn domain → **DNS** → **Records**.

### Record cơ bản cho web (HTTP/HTTPS)

| Type | Name | Content | Proxy status | TTL |
|------|------|---------|--------------|-----|
| **A** | `@` | `IP_CUA_SERVER` | Proxied (orange cloud) | Auto |
| **A** | `www` | `IP_CUA_SERVER` | Proxied (orange cloud) | Auto |

- Thay `IP_CUA_SERVER` bằng IP public của server (ví dụ: `103.xxx.xxx.xxx`).
- **Proxied** (biểu tượng mây màu cam): traffic đi qua Cloudflare → bảo vệ DDoS, cache, SSL.
- **DNS only** (mây xám): chỉ DNS, traffic đi thẳng tới server.

### Subdomain (ví dụ: NginxUI, API)

| Type | Name | Content | Proxy status |
|------|------|---------|--------------|
| A | `nginxui` | `IP_CUA_SERVER` | Proxied hoặc DNS only |
| A | `api` | `IP_CUA_SERVER` | Proxied |

Sau khi thêm/sửa record, chờ vài phút rồi kiểm tra:

```bash
# Kiểm tra DNS đã trỏ đúng chưa
nslookup example.com
dig example.com
```

---

## 4. Bật Cloudflare Proxy (Orange Cloud)

- Trong danh sách DNS Records, bấm vào **Proxy status** (biểu tượng mây) để bật **Proxied** (mây cam) cho các record A/AAAA của web.
- Khi bật Proxied:
  - IP server của bạn được ẩn (client chỉ thấy IP Cloudflare).
  - Traffic đi qua Cloudflare → có DDoS protection, CDN, SSL.
  - Server chỉ cần chấp nhận kết nối từ IP của Cloudflare (xem mục 6).

---

## 5. Cấu hình SSL/TLS

Trong Cloudflare: **SSL/TLS**.

### Chế độ khuyến nghị: **Full (strict)**

1. Chọn **SSL/TLS** → **Overview**.
2. Chọn **Full (strict)**:
   - Cloudflare ↔ Visitor: HTTPS (Cloudflare cung cấp certificate).
   - Cloudflare ↔ Origin (server): HTTPS, Cloudflare chỉ chấp nhận certificate hợp lệ từ server.

### Certificate trên server (để dùng Full strict)

Server cần có certificate (ví dụ từ Let's Encrypt). Nếu đã dùng Nginx và certbot:

```bash
# Cài certbot (Ubuntu/Debian)
sudo apt update
sudo apt install certbot python3-certbot-nginx -y

# Lấy certificate (Nginx cần tạm dừng hoặc certbot tự cấu hình)
sudo certbot --nginx -d example.com -d www.example.com
```

Sau đó trong Nginx, site sẽ dùng SSL và Cloudflare có thể kết nối HTTPS tới origin.

### Chế độ khác

- **Flexible**: Visitor → Cloudflare (HTTPS), Cloudflare → Server (HTTP). Đơn giản nhưng traffic từ Cloudflare tới server không mã hóa.
- **Full**: Cả hai đoạn đều HTTPS nhưng Cloudflare chấp nhận self-signed certificate trên server.

---

## 6. Cấu hình Nginx với Cloudflare

### Nhận IP thật của client (qua CF-Connecting-IP)

Khi bật Proxy, Nginx nhận request từ IP của Cloudflare. Để có IP thật của visitor, dùng header `CF-Connecting-IP`.

Thêm vào block `http` hoặc `server` trong cấu hình Nginx (ví dụ `/etc/nginx/nginx.conf` hoặc file site):

```nginx
# Đặt real IP từ Cloudflare
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 131.0.72.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
real_ip_header CF-Connecting-IP;
```

Danh sách IP Cloudflare cập nhật: [Cloudflare IP Ranges](https://www.cloudflare.com/ips/)

```bash
# Test và reload Nginx
sudo nginx -t && sudo systemctl reload nginx
```

### Chỉ cho phép traffic từ Cloudflare (tùy chọn bảo mật)

Nếu bạn chỉ muốn web truy cập qua Cloudflare, có thể cấu hình firewall trên server chỉ cho phép kết nối 80/443 từ [IP ranges của Cloudflare](https://www.cloudflare.com/ips/). Lưu ý: cần cập nhật khi Cloudflare thay đổi IP.

---

## 7. Một số tùy chọn bảo mật và hiệu năng

### Firewall Rules (Security → WAF)

- Tạo rule chặn theo country, IP, hoặc User-Agent nếu cần.
- Có thể bật **Under Attack Mode** khi bị tấn công (challenge trước khi vào site).

### Caching (Caching → Configuration)

- **Caching Level**: Standard hoặc Cache Everything (cho static).
- **Browser Cache TTL**: tùy nhu cầu.
- **Purge Cache**: xóa cache khi cập nhật nội dung.

### Page Rules / Cache Rules

- Ví dụ: cache mạnh cho `*.example.com/static/*` hoặc bypass cache cho `/api/*`.

### Tắt proxy cho từng subdomain

- Nếu có service (ví dụ SSH, game server, custom port) cần trỏ thẳng về server, tạo record A/AAAA tương ứng và tắt proxy (mây xám) cho record đó. Lưu ý: khi đó traffic không đi qua Cloudflare, server phải tự bảo vệ và mở firewall cho port tương ứng.

---

## Tóm tắt nhanh

| Bước | Hành động |
|------|-----------|
| 1 | Thêm site lên Cloudflare, lấy nameservers |
| 2 | Đổi nameservers tại nhà đăng ký domain |
| 3 | Thêm A record `@` và `www` trỏ về IP server, bật Proxied |
| 4 | SSL/TLS: chọn Full (strict), cài certificate trên server (certbot) |
| 5 | Nginx: thêm `set_real_ip_from` + `real_ip_header CF-Connecting-IP` |
| 6 | (Tùy chọn) Firewall, Cache, Page Rules |

Sau khi hoàn tất, traffic đến domain sẽ đi qua Cloudflare trước khi tới Nginx trên server của bạn, giúp ẩn IP server, bảo vệ DDoS và dùng SSL từ Cloudflare đến người dùng.




#type2
Bước 1: Cấu hình trên Cloudflare (DNS)
Trước tiên, bạn cần trỏ tên miền từ Cloudflare về địa chỉ IP của máy chủ (VPS) đang chạy Nginx.

Truy cập vào mục DNS > Records.

Trỏ Domain chính: Tạo một bản ghi A, Name là @, Content là IP_CỦA_SERVER.

Trỏ Subdomain:

Nếu bạn chỉ có vài subdomain: Tạo bản ghi A, Name là tên subdomain (ví dụ: app), Content là IP_CỦA_SERVER.

Nếu bạn muốn "quất" hết tất cả subdomain về Nginx: Tạo bản ghi Wildcard bằng cách đặt Name là *.

Proxied: Đảm bảo biểu tượng đám mây có màu Cam (Proxy status: Proxied) để hưởng các tính năng bảo mật của Cloudflare.

Bước 2: Cấu hình Nginx để điều hướng Subdomain
Bây giờ là lúc yêu cầu Nginx "phân loại" khách truy cập dựa trên subdomain họ gõ.

Truy cập vào thư mục cấu hình: cd /etc/nginx/sites-available/.

Tạo một file cấu hình mới cho mỗi subdomain (hoặc gom chung vào một file tùy bạn). Ví dụ: nano my_subdomains.conf.

Ví dụ mẫu cấu hình điều hướng:
Nginx
# Subdomain 1: Trỏ vào một thư mục chứa code HTML/PHP
server {
    listen 80;
    server_name app.domain.com;

    location / {
        root /var/www/app_folder;
        index index.html;
    }
}

# Subdomain 2: Điều hướng (Proxy) về một ứng dụng đang chạy ở port khác (VD: Node.js, Docker)
server {
    listen 80;
    server_name api.domain.com;

    location / {
        proxy_pass http://127.0.0.1:3000; # Port ứng dụng của bạn
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
Kích hoạt cấu hình:

Tạo link liên kết: ln -s /etc/nginx/sites-available/my_subdomains.conf /etc/nginx/sites-enabled/.

Kiểm tra lỗi cú pháp: nginx -t.

Restart Nginx: systemctl restart nginx.

Bước 3: Xử lý SSL (HTTPS)
Vì bạn dùng Cloudflare, bạn có hai lựa chọn chính để tránh lỗi "Mixed Content" hoặc "Insecure":

Chế độ Flexible: Cloudflare mã hóa từ trình duyệt đến Cloudflare, còn từ Cloudflare đến Nginx là HTTP (Port 80). Dễ làm nhưng kém bảo mật hơn.

Chế độ Full/Strict (Khuyên dùng): * Bạn cài SSL (Let's Encrypt hoặc Cloudflare Origin Certificate) ngay trên Server Nginx.

Khi đó, Nginx sẽ lắng nghe ở listen 443 ssl;.

[!TIP]
Nếu dùng Cloudflare, bạn nên vào mục SSL/TLS trên dashboard của họ và chọn Full. Sau đó dùng Certbot trên server để cấp chứng chỉ cho từng subdomain là xong.

Lưu ý quan trọng về Bảo mật
Khi đã dùng Cloudflare, bạn nên cấu hình Nginx chỉ chấp nhận kết nối từ các dải IP của Cloudflare. Điều này ngăn chặn hacker "vượt rào" tấn công trực tiếp vào IP server của bạn mà không đi qua lớp bảo vệ của Cloudflare.




Chú ý đang mở Flex mode để có thể connect nhanh đến server dev

Chế độ Flexible: Cloudflare mã hóa từ trình duyệt đến Cloudflare, còn từ Cloudflare đến Nginx là HTTP (Port 80). Dễ làm nhưng kém bảo mật hơn.


# Cách setup site trên nginx ui
## Hướng dẫn tạo site mới trên Nginx UI

1. **Truy cập Nginx UI:**
   - Mở trình duyệt và nhập địa chỉ:  
     `http://<IP_SERVER>:9000`  
     (_Ví dụ: `http://192.168.1.100:9000` hoặc sử dụng IP của VPS/server của bạn_)

2. **Đăng nhập:**
   - Nếu là lần đầu vào, tài khoản thường là:
     - username: `admin`
     - password: `admin`
   _Đổi mật khẩu ngay sau khi đăng nhập để bảo mật._

3. **Tạo Site/Site mới:**
   - Chọn tab **Sites** trên menu.
   - Nhấn nút **Add Site** hoặc **Create**.
   - **Domain:** Nhập tên domain/subdomain bạn quản lý (ví dụ: `api.domain.com`, `*.domain.com`)
   - **Root Path:** Nhập thư mục chứa mã nguồn (ví dụ: `/var/www/app_folder`)
   - **Port forwarding (nếu cần Proxy đến app khác):**
     - Chọn `Reverse Proxy`
     - Target: `http://127.0.0.1:PORT` (_VD: `http://127.0.0.1:3000` nếu app Node.js chạy cổng 3000_)
   - **SSL:**
     - Nếu đã có certificate (Let’s Encrypt), bật SSL (Enable SSL), nhập đường dẫn crt/key.
     - Hoặc chọn chức năng auto generate Let’s Encrypt (nếu Nginx UI hỗ trợ).
     - Nếu chưa setup chứng chỉ, có thể tạo site ở HTTP trước, rồi sau này cập nhật.
   -  Ở đây bạn sẽ thấy full block nginx config.
   -  Bạn thêm vào trong location /:
   -  proxy_set_header Host $host;
   -  proxy_set_header X-Real-IP $remote_addr;
   -  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   -  Ví dụ hoàn chỉnh sẽ thành:
   -  Save → Reload Nginx


default_type text/plain;
return 200 "health ok";

server {
    listen 80;
    listen [::]:80;

    server_name luckystack.dev *.luckystack.dev;

    location /health {
        default_type text/plain;
        return 200 "health ok";
    }

    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
4. **Kiểm tra cấu hình:**
   - Vào tab **Test Config** hoặc dùng lệnh (nếu thao tác ngoài UI):  
     `nginx -t`

5. **Restart Nginx/nginx proxy container:**
   - Trên Nginx UI: nhấn **Reload/Restart Nginx**.
   - Hoặc ngoài console:  
     `docker compose restart nginx-ui`  
     hoặc  
     `systemctl restart nginx` (nếu chạy dạng service thường).

6. **Cấu hình trỏ DNS:**
   - Đảm bảo tên miền/subdomain vừa tạo đã trỏ về IP server trên Cloudflare (record type A hoặc CNAME phù hợp).

### Ghi chú
- Nếu dùng Cloudflare, site mới cần thêm trên Cloudflare Dashboard và bật proxy (mây cam) để tận dụng bảo vệ của Cloudflare.
- Nếu cấu hình proxy app (Node/PHP/khác), đảm bảo port chỉ mở nội bộ hoặc giới hạn, không expose thẳng ra ngoài public.
- Nên backup file cấu hình sau khi tạo site mới.

[!TIP]
Nếu muốn import file cấu hình đã có sẵn từ `/etc/nginx/sites-available/`, bạn có thể dùng tính năng import/conf management của Nginx UI hoặc thêm config thủ công.


Chú ý  tường lửa của nhà cung cấp mạng (vhost) Cần mở port