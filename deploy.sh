#!/bin/bash

IMAGE_NAME="hhxxc/ezbookkeeping:latest-snapshot"
PROXY_IMAGE_NAME=""

# 尝试的镜像代理源（按顺序）
MIRRORS=(
    "docker.m.daocloud.io"
    "dockerhub.icu"
    "dockerpull.org"
    "docker.1panel.live"
)

echo "Stopping and removing old container..."
docker stop ezbookkeeping 2>/dev/null
docker rm ezbookkeeping 2>/dev/null
docker rmi $IMAGE_NAME 2>/dev/null

echo "Trying to pull image..."

# 先尝试官方源
if docker pull $IMAGE_NAME; then
    echo "Successfully pulled from official registry"
else
    echo "Official registry failed, trying mirrors..."
    for mirror in "${MIRRORS[@]}"; do
        echo "Trying mirror: $mirror"
        if docker pull "$mirror/$IMAGE_NAME"; then
            docker tag "$mirror/$IMAGE_NAME" $IMAGE_NAME
            docker rmi "$mirror/$IMAGE_NAME" 2>/dev/null
            echo "Successfully pulled from $mirror"
            break
        fi
    done
fi

# 检查是否拉取成功
if ! docker image inspect $IMAGE_NAME >/dev/null 2>&1; then
    echo "ERROR: Failed to pull image from all sources"
    exit 1
fi

echo "Starting new container..."
docker run -d \
    --name ezbookkeeping \
    --user "1000:1000" \
    -p 9180:15080 \
    -e EBK_GLOBAL_MODE=production \
    -e EBK_LLM_TRANSACTION_FROM_AI_IMAGE_RECOGNITION=true \
    -e EBK_LLM_IMAGE_RECOGNITION_LLM_PROVIDER=openai_compatible \
    -e EBK_LLM_IMAGE_RECOGNITION_OPENAI_COMPATIBLE_BASE_URL=https://api.siliconflow.cn/v1 \
    -e EBK_LLM_IMAGE_RECOGNITION_OPENAI_COMPATIBLE_MODEL_ID=Pro/Qwen2-VL-7B-Instruct \
    -e EBKCFP_LLM_IMAGE_RECOGNITION_OPENAI_COMPATIBLE_API_KEY=/volume2/docker/giliconcloude_key.txt \
    -v /volume2/docker/ezbk:/ezbookkeeping/data \
    -v /volume2/docker/giliconcloude_key.txt:/volume2/docker/giliconcloude_key.txt:ro \
    --restart=no \
    $IMAGE_NAME

echo "Done. Container status:"
docker ps -f name=ezbookkeeping
