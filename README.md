# **CODEBUDDY-DOCKER**
一个我也不知道有没有重复造轮子、但是能跑的，把CodeBuddy CLI作为常驻docker服务运行的小项目

## 创建镜像
```sh
# 仓库
https://github.com/lue-trim/codebuddy-docker.git
# node
docker pull docker.m.daocloud.io/node:22-bookworm-slim
docker tag docker.m.daocloud.io/node:22-bookworm-slim node:22-bookworm-slim
# dockerfile
docker pull docker.m.daocloud.io/docker/dockerfile:1
docker tag docker.m.daocloud.io/docker/dockerfile:1 docker/dockerfile:1
# 修改版本号
ARG CODEBUDDY_VERSION=2.184.0
# build
docker compose build
```
## 首次登录
```sh
docker compose run --rm -it --entrypoint codebuddy codebuddy
```
进TUI后执行/`login`登录即可

## 更新
根据官网的最新版本修改`docker-compose.yml`中`CODEBUDDY_VERSION`的取值，再重新创建镜像并部署

## 环境变量
参考`.env.example`
