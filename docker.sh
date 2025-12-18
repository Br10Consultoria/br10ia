#!/bin/bash
#==============================================================================
#  OK Inteligencia Artificial
#  Formacao ISP AI Starter - Provedores Inteligentes
#==============================================================================
#
#  Script:   01-docker.sh
#  Funcao:   Instala Docker e configura Swarm
#  Versao:   2.0.0
#
#  COMO EXECUTAR:
#    1. Acesse o servidor via SSH: ssh root@IP_DO_SERVIDOR
#    2. Copie todo o conteudo deste script
#    3. Cole no terminal e pressione Enter
#
#==============================================================================

[ "$EUID" -ne 0 ] && { echo "Execute como root: sudo bash $0"; exit 1; }

#==============================================================================
# FUNCOES
#==============================================================================

get_ip() { 
    hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1.1.1.1 2>/dev/null | awk '/src/{print $7}'
}

docker_clean() {
    echo "[INFO] Limpando ambiente Docker..."
    for stack in $(docker stack ls --format '{{.Name}}' 2>/dev/null); do 
        docker stack rm "$stack" 2>/dev/null
    done
    sleep 5
    docker service rm $(docker service ls -q 2>/dev/null) 2>/dev/null
    sleep 3
    docker stop $(docker ps -aq 2>/dev/null) 2>/dev/null
    docker rm -f $(docker ps -aq 2>/dev/null) 2>/dev/null
    docker swarm leave --force 2>/dev/null
    sleep 2
    for net in $(docker network ls --format '{{.Name}}' 2>/dev/null | grep -v -E '^(bridge|host|none)$'); do 
        docker network rm "$net" 2>/dev/null
    done
    docker rmi -f $(docker images -aq 2>/dev/null) 2>/dev/null
    docker system prune -af 2>/dev/null
    docker network prune -f 2>/dev/null
    echo "[OK] Ambiente limpo"
}

#==============================================================================
# INSTALACAO DO DOCKER
#==============================================================================

echo
echo "=============================================================================="
echo "  ETAPA 1/3: Instalacao do Docker"
echo "=============================================================================="
echo

if ! command -v docker &>/dev/null; then
    echo "[INFO] Instalando Docker..."
    apt-get update && apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker && systemctl start docker
    echo "[OK] Docker instalado"
else
    echo "[OK] Docker ja instalado: $(docker --version | cut -d' ' -f3 | tr -d ',')"
fi

#==============================================================================
# CONFIGURACAO DO SWARM
#==============================================================================

echo
echo "=============================================================================="
echo "  ETAPA 2/3: Configuracao do Docker Swarm"
echo "=============================================================================="
echo

SERVER_IP=$(get_ip)
[ -z "$SERVER_IP" ] && { read -p "IP do servidor: " SERVER_IP; [ -z "$SERVER_IP" ] && exit 1; }
echo "[OK] IP do servidor: $SERVER_IP"

if docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "[AVISO] Swarm ja ativo. Recriar vai apagar containers, imagens e networks (volumes mantidos)."
    echo -n "Recriar do zero? (s/N): "
    read -r R
    if [[ "$R" =~ ^[Ss]$ ]]; then
        echo -n "Digite CONFIRMAR para prosseguir: "
        read -r C
        [ "$C" = "CONFIRMAR" ] && docker_clean || { echo "Cancelado."; exit 0; }
    else
        echo "[OK] Swarm mantido sem alteracoes"
    fi
fi

if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    docker swarm init --advertise-addr="$SERVER_IP" || exit 1
    echo "[OK] Swarm inicializado"
fi

# Cria rede overlay
if ! docker network ls --format '{{.Name}}' | grep -q "^network_public$"; then
    docker network create --driver=overlay network_public
    echo "[OK] Rede network_public criada"
else
    echo "[OK] Rede network_public ja existe"
fi

#==============================================================================
# ESTRUTURA DE DIRETORIOS
#==============================================================================

echo
echo "=============================================================================="
echo "  ETAPA 3/3: Estrutura de Diretorios"
echo "=============================================================================="
echo

mkdir -p /storage/docker
mkdir -p /storage/traefik/{data,logs,config}
mkdir -p /storage/portainer/{data,logs,config}
mkdir -p /storage/minio/{data,logs,config}
mkdir -p /storage/postgres/{data,logs,config}
mkdir -p /storage/redis/{data,logs,config}
mkdir -p /storage/n8n/{data,logs,config,nodes}
mkdir -p /storage/chatwoot/{data,logs,config,storage}
echo "[OK] Diretorios criados"

# Permissoes por servico
chown -R 1000:1000 /storage/n8n        # n8n: UID 1000 (node)
chown -R 999:1000 /storage/redis       # Redis: UID 999 (redis)
chown -R 999:999 /storage/postgres     # PostgreSQL: UID 999
chown -R 1000:1000 /storage/chatwoot   # Chatwoot: UID 1000
echo "[OK] Permissoes configuradas"

#==============================================================================
# RESUMO
#==============================================================================

echo
echo "=============================================================================="
echo "  Docker Swarm - Instalacao Concluida"
echo "=============================================================================="
echo
echo "  Docker:   $(docker --version | cut -d' ' -f3 | tr -d ',')"
echo "  Swarm IP: ${SERVER_IP}"
echo "  Hostname: $(hostname -f)"
echo
echo "=============================================================================="
echo "  PROXIMO PASSO:"
echo "=============================================================================="
echo
echo "  Execute: bash 02-traefik.sh"
echo
echo "=============================================================================="
echo
docker swarm join-token worker 2>/dev/null
