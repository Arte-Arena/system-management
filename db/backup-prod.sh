#!/bin/bash

# Este script faz o backup do Banco de Dados, registra no banco de dados, 
# via API do Space, para acesso do Super Admin. 
# Envia para o Object Storage e monitora as falhas.

# Data e hora do backup
DATA=$(date +"%Y-%m-%d_%H-%M-%S")

# Diretório de backup
BACKUP_DIR="/home/artearena/backup"

# Credenciais do banco de dados (obtidas das variáveis de ambiente)
MYSQL_BACKUP_USER="${MYSQL_BACKUP_USER:-$USER}"         # Nome de usuário do MySQL para backup
MYSQL_BACKUP_PASSWORD="${MYSQL_BACKUP_PASSWORD:-$PASSWORD}" # Senha do MySQL para backup
MYSQL_BACKUP_DATABASE="${MYSQL_BACKUP_DATABASE:-$DBNAME}" # Nome do banco de dados para backup

# Nome do arquivo de backup
BACKUP_FILE="${BACKUP_DIR}/backup_mysql_${MYSQL_BACKUP_DATABASE}_${DATA}.sql"

# Nome do bucket no Object Storage
BUCKET="arteus"

# Caminho completo para o arquivo no bucket, incluindo os folders
BUCKET_PATH="backup/db/$(basename "$BACKUP_FILE")"

# Função para enviar a requisição para a API
enviar_requisicao_api() {
  local status=$1
  local nome_backup=$(basename "$BACKUP_FILE")
  local data_inicio=$(date +"%Y-%m-%d %H:%M:%S")
  local data_fim=$(date +"%Y-%m-%d %H:%M:%S")
  local tamanho=$(stat -c%s "$BACKUP_FILE")

  # Corpo da requisição em JSON
  local dados_json=$(cat <<EOF
{
  "nome": "$nome_backup",
  "data_inicio": "$data_inicio",
  "data_fim": "$data_fim",
  "status": "$status",
  "tamanho": $tamanho
}
EOF
)

  # Envia a requisição para a API
  curl -X PUT \
    -H "Content-Type: application/json" \
    -H "X-API-KEY: teste" \
    -d "$dados_json" \
    http://localhost:8000/api/super-admin/upsert-backup
}

# Envia a requisição para a API com status "em_andamento"
enviar_requisicao_api "em_andamento"

# Realiza o backup do MySQL
mysqldump -u "$MYSQL_BACKUP_USER" -p"$MYSQL_BACKUP_PASSWORD" "$MYSQL_BACKUP_DATABASE" > "$BACKUP_FILE"

if [[ -f "$BACKUP_FILE" ]]; then
  echo "Backup do MySQL realizado com sucesso em $BACKUP_FILE"

  # Envia o arquivo para o bucket
  s3cmd put "$BACKUP_FILE" s3://"$BUCKET"/"$BUCKET_PATH"

  # Verifica se o upload foi bem-sucedido
  if [ $? -eq 0 ]; then
    echo "Arquivo enviado com sucesso para o bucket!"
    # Envia a requisição para a API com status "sucesso"
    enviar_requisicao_api "sucesso"
  else
    echo "Falha ao enviar o arquivo para o bucket."
    # Envia a requisição para a API com status "falha"
    enviar_requisicao_api "falha"
  fi

else
  echo "Erro ao realizar o backup do MySQL."
  # Envia a requisição para a API com status "falha"
  enviar_requisicao_api "falha"
fi