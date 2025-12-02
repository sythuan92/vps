Option 1: wget -O - https://raw.githubusercontent.com/sythuan92/vps/main/setup.sh | bash
Option 2: wget -O setup.sh https://raw.githubusercontent.com/sythuan92/vps/main/setup.sh && sed -i 's/\r$//' setup.sh && bash setup.sh


TẠI VPS 
docker compose up -d
docker compose logs -f
docker compose pull
Tại pc
Build ảnh mới: 
docker build -t sythuan/binance-bot-pro:latest .
Đẩy lên Cloud:
docker push sythuan/binance-bot-pro:latest
