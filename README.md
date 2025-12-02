Option 1: wget -O - https://raw.githubusercontent.com/sythuan92/vps/main/setup.sh | bash
Option 2: wget -O setup.sh https://raw.githubusercontent.com/sythuan92/vps/main/setup.sh && sed -i 's/\r$//' setup.sh && bash setup.sh
