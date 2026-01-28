FROM ghcr.io/vevc/ubuntu:25.11.15

USER root

# 1-1. 安装基础工具
RUN apt-get update && apt-get install -y \
    supervisor procps wget curl passwd sudo openssh-server net-tools && \
    rm -rf /var/lib/apt/lists/*

# 2. 安装 Cloudflared
RUN curl -L --retry 3 --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && \
    dpkg -i cloudflared.deb && rm cloudflared.deb

# 3. 安装 GOST v2.12.0 (处理 .tar.gz 格式)
RUN wget --tries=3 https://github.com/ginuerzh/gost/releases/download/v2.12.0/gost_2.12.0_linux_amd64.tar.gz && \
    tar -xvf gost_2.12.0_linux_amd64.tar.gz && \
    mv gost /usr/local/bin/gost && \
    chmod +x /usr/local/bin/gost && \
    rm gost_2.12.0_linux_amd64.tar.gz

# 1-4. 安装 WARP-GO v1.0.8 (处理 .tar.gz 格式)
RUN wget --tries=3 https://github.com/Fangliding/warp-go/releases/download/v1.0.8/warp-go_1.0.8_linux_amd64.tar.gz && \
    tar -xvf warp-go_1.0.8_linux_amd64.tar.gz && \
    mv warp-go /usr/local/bin/warp-go && \
    chmod +x /usr/local/bin/warp-go && \
    rm warp-go_1.0.8_linux_amd64.tar.gz

# 2. 设置默认环境变量
ENV SSH_USER=zv
ENV SSH_PASSWORD=admin123
ENV CF_TUNNEL_TOKEN=""
# 设置全局代理环境变量 (让终端里的 curl, wget 默认走 GOST)
ENV http_proxy=http://127.0.0.1:10000
ENV https_proxy=http://127.0.0.1:10000

# 3. 固化全局配置
RUN echo "alias sctl='supervisorctl -c /home/\${SSH_USER:-zv}/boot/supervisord.conf'" >> /etc/bash.bashrc && \
    # 允许 root SSH 登录 (解决之前你遇到的密码错误问题)
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 4. 编写入口启动脚本
RUN printf "#!/bin/bash\n\
export USER_HOME=\"/home/\${SSH_USER:-zv}\"\n\
export BOOT_DIR=\"\${USER_HOME}/boot\"\n\
export AGS_DIR=\"\${USER_HOME}/agsbx\"\n\
mkdir -p \"\${BOOT_DIR}\" \"\${AGS_DIR}\" /var/run/sshd /var/log/supervisor\n\
\n\
# 创建用户并配置权限\n\
if ! id \"\${SSH_USER}\" &>/dev/null; then\n\
    useradd -m -s /bin/bash \"\${SSH_USER}\"\n\
fi\n\
echo \"\${SSH_USER} ALL=(ALL:ALL) NOPASSWD: ALL\" >> /etc/sudoers\n\
echo \"\${SSH_USER}:\${SSH_PASSWORD}\" | chpasswd\n\
echo \"root:\${SSH_PASSWORD}\" | chpasswd\n\
chown -R \${SSH_USER}:\${SSH_USER} \${USER_HOME}\n\
\n\
# 生成 SSH 主机密钥\n\
ssh-keygen -A\n\
\n\
# 动态生成 Supervisor 配置 (核心四进程)\n\
printf \"[supervisord]\n\
nodaemon=true\n\
user=root\n\
\n\
[program:sshd]\n\
command=/usr/sbin/sshd -D\n\
autostart=true\n\
autorestart=true\n\
\n\
[program:cloudflared]\n\
command=/usr/bin/cloudflared tunnel --no-autoupdate run --token \${CF_TUNNEL_TOKEN}\n\
autostart=true\n\
autorestart=true\n\
\n\
[program:warp-go]\n\
command=/usr/local/bin/warp-go --proxy-port 40000\n\
user=\${SSH_USER}\n\
directory=\${AGS_DIR}\n\
autostart=true\n\
autorestart=true\n\
\n\
[program:gost]\n\
command=/usr/local/bin/gost -L :10000 -F socks5://127.0.0.1:40000\n\
user=\${SSH_USER}\n\
autostart=true\n\
autorestart=true\n\
\" > \"\${BOOT_DIR}/supervisord.conf\"\n\
\n\
# 启动进程管理\n\
exec /usr/bin/supervisord -c \"\${BOOT_DIR}/supervisord.conf\"\n" > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
