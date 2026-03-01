# Plan
* 1. Option A – 🔥 Drone CI (cực nhẹ)
* 2. Docker context remote

# Plan details
##  Docker context remote
* 1. Tạo docker context remote
    docker context create my-server --docker "host=ssh://user@your-server-ip"
    docker context use my-server
    docker ps
* 2. Build 
    docker build -t myapp:latest .
    docker --context my-server image load < <(docker save myapp:latest)

    docker context use my-server
    docker compose up -d --build

* 3. Thoát
    docker context use default