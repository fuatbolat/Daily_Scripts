#!/bin/bash
 
# --- Ayarlar ---
INSTALL_DIR="/tmp/azagent"
AGENT_VERSION="4.268.0"
URL="https://dtalm.visualstudio.com/"
PROJECT="Big Data"
POOL="DMZ DOAS LAKE"
TOKEN="4lIFbBJc3w6fa1EK3EQyY7qN7hcna9FRTIDpf2kBpcXo2FJSUKRYJQQJ99CBACAAAAAoa8PhAAASAZDO4YjY"
AGENT_NAME=$(hostname)
 
# --- Hazırlık ---
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1
 
# --- İndirme ve Ayıklama ---
echo "Azure Agent paketi çekiliyor..."
curl -fkSL -o vstsagent.tar.gz "https://download.agent.dev.azure.com/agent/${AGENT_VERSION}/vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz"
tar -zxvf vstsagent.tar.gz
 
# --- Konfigürasyon ---
if [ -x "$(command -v systemctl)" ]; then
    echo "Systemd üzerinden servis kurulumu yapılıyor..."
    ./config.sh --deploymentgroup --deploymentgroupname "$POOL" --acceptteeeula --agent "$AGENT_NAME" --url "$URL" --work _work --projectname "$PROJECT" --auth PAT --token "$TOKEN" --runasservice
    ./svc.sh install
    ./svc.sh start
else
    echo "Eski sistem: nohup ile başlatılıyor..."
    ./config.sh --deploymentgroup --deploymentgroupname "$POOL" --acceptteeeula --agent "$AGENT_NAME" --url "$URL" --work _work --projectname "$PROJECT" --auth PAT --token "$TOKEN"
    nohup ./run.sh > agent.log 2>&1 &
fi
 
echo "İşlem tamamlandı. Agent durumunu Azure üzerinden kontrol edebilirsiniz."