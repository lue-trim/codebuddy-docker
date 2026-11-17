# **CODEBUDDY-DOCKER**
一个我也不知道有没有重复造轮子、但是能跑的，把CodeBuddy CLI作为常驻docker服务运行的小项目

## 创建镜像
1. 拉取仓库
    ```sh
    https://github.com/lue-trim/codebuddy-docker.git
    ```
1. pull+tag 
    (这是网络位于中国大陆时的用法; 如果能直连dockerhub, 直接跳过这个步骤也行, build的时候会自动拉取)
    ```sh
    # node
    docker pull docker.m.daocloud.io/node:22-bookworm-slim
    docker tag docker.m.daocloud.io/node:22-bookworm-slim node:22-bookworm-slim
    # dockerfile
    docker pull docker.m.daocloud.io/docker/dockerfile:1
    docker tag docker.m.daocloud.io/docker/dockerfile:1 docker/dockerfile:1
    ```
1. 复制一份`.env.example`到`.env`, 按需修改环境变量
    ```sh
    cp .env.example .env
    ```
1. 创建镜像, codebuddy本体会在途中自动安装
    ```sh
    docker compose build
    ```

## 启动
```sh
docker compose up -d
docker compose ps
docker compose logs --tail=40 codebuddy
```
首次启动日志里会打印：
```
CodeBuddy Web UI 初始密码: xxxxxxxxxxxx
```
该密码同时写入 codebuddy-config 卷的 settings.json，重启后沿用

## 访问&登录
浏览器打开 http://127.0.0.1:7890/ ，输入上面的密码。API 调用使用同一个密码作为 Bearer Token：
```sh
curl -H "Authorization: Bearer <密码>" http://127.0.0.1:7890/api/openapi.json
```
首次启动的时候会自动弹出登录界面，直接把号登上去就完事了

API 文档：http://127.0.0.1:7890/api/docs

## 更新
根据官网的最新版本修改`docker-compose.yml`中`CODEBUDDY_VERSION`的取值，再重新创建镜像并部署

## 环境变量
参考`.env.example`
