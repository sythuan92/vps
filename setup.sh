#!/bin/bash

# ==============================================================================
# ULTIMATE TRADING VPS SETUP SCRIPT
# Target: Ubuntu 20.04 / 22.04
# Optimized for: Binance API, High Frequency Trading, WebSocket Stability
# ==============================================================================

# Màu sắc cho dễ nhìn
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> BẮT ĐẦU THIẾT LẬP HỆ THỐNG ĐUA TOP VOLUME...${NC}"

# 1. KIỂM TRA QUYỀN ROOT
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Lỗi: Vui lòng chạy script bằng quyền root (sudo).${NC}"
  exit 1
fi

# 2. CẬP NHẬT HỆ THỐNG & CÀI ĐẶT CÔNG CỤ CƠ BẢN
echo -e "${YELLOW}[1/6] Update hệ thống & Cài đặt tools...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y
# Cài đặt các gói cần thiết:
# - chrony: Đồng bộ thời gian cực chuẩn (Bắt buộc cho Trading)
# - htop: Theo dõi tài nguyên
# - curl/git/wget: Tải code
# - haveged: Tăng entropy (giúp mã hóa SSL/TLS nhanh hơn khi handshake)
apt-get install -y curl wget git htop unzip ca-certificates gnupg lsb-release chrony haveged

# Kích hoạt đồng bộ thời gian ngay lập tức
systemctl enable chrony
systemctl start chrony
# Ép buộc đồng bộ ngay để tránh lệch giờ dù chỉ 1ms
chronyc makestep

# 3. TẠO SWAP RAM THÔNG MINH (Chống Crash cho VPS 1-2GB RAM)
echo -e "${YELLOW}[2/6] Cấu hình Swap (RAM ảo)...${NC}"
# Kiểm tra nếu chưa có swap thì mới tạo
if grep -q "swap" /etc/fstab; then
    echo -e "${GREEN}Swap đã tồn tại. Bỏ qua.${NC}"
else
    # Tạo 2GB Swap
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    
    # Tinh chỉnh Swappiness: Chỉ dùng Swap khi RAM thật còn dưới 10%
    # Giúp bot luôn chạy trên RAM thật (nhanh nhất), Swap chỉ là bảo hiểm.
    sysctl vm.swappiness=10
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    echo -e "${GREEN}Đã tạo Swap 2GB an toàn.${NC}"
fi

# 4. TỐI ƯU KERNEL & MẠNG (PHẦN QUAN TRỌNG NHẤT)
echo -e "${YELLOW}[3/6] Tối ưu Network Stack cho Trading (TCP BBR & Kernel Tuning)...${NC}"

# Backup file config cũ
cp /etc/sysctl.conf /etc/sysctl.conf.bak

# Ghi đè các tham số tối ưu vào sysctl.conf
cat <<EOF > /etc/sysctl.conf
# --- TỐI ƯU BBR (Tăng tốc đường truyền quốc tế) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- TỐI ƯU KẾT NỐI (Keep-Alive & Session) ---
# Giảm thời gian check kết nối chết (Mặc định 2 tiếng -> Giảm xuống 60s)
# Giúp phát hiện mất mạng nhanh để bot Reconnect ngay.
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 6

# --- TỐI ƯU BUFFER (Chống nghẽn khi thị trường bão) ---
# Tăng vùng đệm để chứa lượng data khổng lồ từ WebSocket khi Pump/Dump
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# --- TỐI ƯU PHẢN HỒI ---
# Tắt tính năng "ngủ" của TCP. Luôn giữ kết nối ở trạng thái sẵn sàng cao nhất.
net.ipv4.tcp_slow_start_after_idle = 0
# Cho phép tái sử dụng socket nhanh (Recovery nhanh khi crash)
net.ipv4.tcp_tw_reuse = 1
# Giảm thời gian chờ đóng kết nối
net.ipv4.tcp_fin_timeout = 15
# Tăng giới hạn hàng đợi backlog (tránh từ chối kết nối khi quá tải)
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
# Tăng dải Port (mở được nhiều kết nối ra ngoài hơn)
net.ipv4.ip_local_port_range = 1024 65535

# Bảo vệ chống tấn công cơ bản (Syn Flood)
net.ipv4.tcp_syncookies = 1
EOF

# Áp dụng ngay lập tức
sysctl -p
echo -e "${GREEN}Network đã được tối ưu hoá tối đa!${NC}"

# 5. TĂNG GIỚI HẠN FILE (Ulimit)
echo -e "${YELLOW}[4/6] Tăng giới hạn File Descriptors...${NC}"
# Mặc định Linux chỉ cho mở 1024 file. Bot trade ghi log và mở socket nhiều sẽ bị lỗi.
bash -c 'echo "* soft nofile 65535" >> /etc/security/limits.conf'
bash -c 'echo "* hard nofile 65535" >> /etc/security/limits.conf'
bash -c 'echo "root soft nofile 65535" >> /etc/security/limits.conf'
bash -c 'echo "root hard nofile 65535" >> /etc/security/limits.conf'

# 6. CÀI ĐẶT DOCKER
echo -e "${YELLOW}[5/6] Cài đặt Docker Engine...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}Docker cài đặt thành công.${NC}"
else
    echo -e "${GREEN}Docker đã có sẵn.${NC}"
fi

# 7. DỌN DẸP
echo -e "${YELLOW}[6/6] Dọn dẹp rác hệ thống...${NC}"
apt-get autoremove -y
apt-get clean

echo -e "============================================================"
echo -e "${GREEN}   CÀI ĐẶT HOÀN TẤT - HỆ THỐNG SẴN SÀNG CHIẾN ĐẤU!   ${NC}"
echo -e "============================================================"
echo -e "Thông số hiện tại:"
echo -e "- Congestion Control: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') (Phải là bbr)"
echo -e "- Swap: $(free -h | grep Swap | awk '{print $2}')"
echo -e "- Time Sync: Chrony Active"
echo -e "============================================================"
echo -e "Hãy upload Docker Image và chạy lệnh: docker run ..."
echo -e "============================================================"
