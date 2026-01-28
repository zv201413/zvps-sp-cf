FROM ubuntu:22.04

# 1. 禁用交互模式并安装基础依赖
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    openssh-server supervisor curl wget sudo ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. 预装 Cloudflared 和 ttyd
RUN curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
    && dpkg -i cloudflared.deb \
    && rm cloudflared.deb

RUN curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64 -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd

# 3. 修复 SSH 权限与目录
RUN mkdir -p /run/sshd /etc/supervisor/conf.d && \
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config && \
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config && \
    ssh-keygen -A

# 4. 用户设置
RUN useradd -m -s /bin/bash zv && \
    echo "zv:105106" | chpasswd && \
    echo "root:105106" | chpasswd && \
    echo "zv ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 5. 【修复点】使用更加稳妥的方式写入配置文件
# 我们直接把内容写进一个临时文件，避免 printf 的转义报错
RUN echo "[supervisord]" > /etc/supervisord.conf && \
    echo "nodaemon=true" >> /etc/supervisord.conf && \
    echo "user=root" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[program:sshd]" >> /etc/supervisord.conf && \
    echo "command=/usr/sbin/sshd -D" >> /etc/supervisord.conf && \
    echo "autorestart=true" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[program:cloudflared]" >> /etc/supervisord.conf && \
    echo "command=bash -c \"/usr/bin/cloudflared tunnel --no-autoupdate run --token \${CF_TOKEN}\"" >> /etc/supervisord.conf && \
    echo "autorestart=true" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[program:ttyd]" >> /etc/supervisord.conf && \
    echo "command=/usr/local/bin/ttyd -p 8080 -W bash" >> /etc/supervisord.conf && \
    echo "autorestart=true" >> /etc/supervisord.conf

# 6. 设置工作目录
WORKDIR /home/zv

# 7. 启动
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisord.conf"]
