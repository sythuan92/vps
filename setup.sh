#!/bin/bash

# ====================================================
# SCRIPT TỐI ƯU VPS CHO TRADING BOT (DOCKER READY)
# Chức năng: Update, Tạo Swap RAM, Tối ưu TCP/BBR, Cài Docker
# ====================================================

echo ">>> BẮT ĐẦU CÀI ĐẶT HỆ THỐNG..."

# 1. CẬP NHẬT HỆ THỐNG VÀ CÀI GÓI CƠ BẢN
# ----------------------------------------------------
echo "[1/5] Cập nhật Ubuntu và cài đặt gói cần thiết..."
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y
apt-get install -y curl wget git htop unzip ca-certificates gnupg lsb-release

# Cài đặt đồng bộ thời gian (Rất quan trọng cho Bot Trade để khớp lệnh chính xác)
apt-get install -y chrony
systemctl enable chrony
systemctl start chrony

# 2. TẠO SWAP RAM (QUAN TRỌNG CHO VPS 1GB-2GB RAM)
# ----------------------------------------------------
# Bot chạy Docker rất tốn RAM, nếu không có Swap sẽ bị crash (OOM Kill)
echo "[2/5] Kiểm tra và tạo Swap RAM (2GB)..."
if grep -q "swap" /etc/fstab; then
    echo "Swap đã tồn tại. Bỏ qua."
else
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    echo "Đã tạo Swap 2GB thành công."
fi

# 3. TỐI ƯU MẠNG (TCP BBR & KERNEL TUNING) - ĐUA TỐC ĐỘ
# ----------------------------------------------------
echo "[3/5] Tối ưu Network (TCP BBR & Kernel settings)..."

# Bật TCP BBR (Congestion Control) - Giảm độ trễ gói tin đi quốc tế
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi

# Tối ưu các tham số mạng cho High Frequency Trading (API/WebSocket)
cat <<EOF >> /etc/sysctl.conf
# Tăng giới hạn file mở (cho nhiều kết nối socket)
fs.file-max = 65535
# Cho phép tái sử dụng socket đang ở trạng thái TIME-WAIT (quan trọng khi spam request)
net.ipv4.tcp_tw_reuse = 1
# Giảm thời gian chờ đóng kết nối
net.ipv4.tcp_fin_timeout = 15
# Tăng vùng đệm TCP (TCP Buffer) để nhận dữ liệu market nhanh hơn
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
# Không để kết nối rơi vào trạng thái ngủ (idle)
net.ipv4.tcp_slow_start_after_idle = 0
EOF

# Áp dụng thay đổi ngay lập tức
sysctl -p

# 4. CÀI ĐẶT DOCKER & DOCKER COMPOSE
# ----------------------------------------------------
echo "[4/5] Cài đặt Docker Engine..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    # Xoá file script cài đặt cho gọn
    rm get-docker.sh
    echo "Docker đã được cài đặt."
else
    echo "Docker đã có sẵn."
fi

# 5. DỌN DẸP
# ----------------------------------------------------
echo "[5/5] Dọn dẹp hệ thống..."
apt-get autoremove -y
apt-get clean

echo "===================================================="
echo " HOÀN TẤT! VPS ĐÃ SẴN SÀNG."
echo " - Swap: 2GB (Đã kích hoạt)"
echo " - Network: TCP BBR (Đã kích hoạt)"
echo " - Docker: Ready"
echo " Bây giờ bạn chỉ cần chạy lệnh: docker run ..."
echo "===================================================="
