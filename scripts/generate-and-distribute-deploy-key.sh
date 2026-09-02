#!/usr/bin/env bash
# kaya-ansible controller üzerinde çalıştırılır.
#
# 1) ~/.ssh/platform-k8s-deploy anahtar çiftini (yoksa) üretir.
# 2) Halihazırda çalışan bootstrap key (platform-k8s-ed25519-ssh-key-kubespray)
#    ile bu YENİ public key'i tüm Kubernetes/HAProxy node'larına dağıtır.
#    PasswordAuthentication sshd tarafında kapalı olduğundan (os_hardening
#    rolü) şifreyle giriş yapılamaz; dağıtım yalnızca zaten güvenilen bir
#    key üzerinden mümkündür.
#
# Kullanım:
#   chmod +x scripts/generate-and-distribute-deploy-key.sh
#   ./scripts/generate-and-distribute-deploy-key.sh

set -uo pipefail

DEPLOY_KEY="${HOME}/.ssh/platform-k8s-deploy"
BOOTSTRAP_KEY="${HOME}/.ssh/platform-k8s-ed25519-ssh-key-kubespray"

if [[ ! -f "${BOOTSTRAP_KEY}" ]]; then
  echo "!!! Bootstrap key bulunamadı: ${BOOTSTRAP_KEY}"
  echo "!!! Bu key olmadan şifresiz dağıtım yapılamaz (PasswordAuthentication kapalı)."
  exit 1
fi

if [[ ! -f "${DEPLOY_KEY}" ]]; then
  echo ">>> Yeni anahtar çifti üretiliyor: ${DEPLOY_KEY}"
  ssh-keygen -t ed25519 -f "${DEPLOY_KEY}" -C "platform-k8s-deploy" -N ""
else
  echo ">>> Mevcut anahtar kullanılıyor: ${DEPLOY_KEY}"
fi

NEW_PUBKEY_CONTENT="$(cat "${DEPLOY_KEY}.pub")"

# README.md / kurulan VM bilgisi ile birebir aynı isim + IP listesi
declare -A NODES=(
  [kaya-master-01]=172.17.160.181
  [kaya-master-02]=172.17.160.182
  [kaya-master-03]=172.17.160.183
  [kaya-worker-01]=172.17.160.186
  [kaya-worker-02]=172.17.160.187
  [kaya-worker-03]=172.17.160.188
  [kaya-worker-04]=172.17.160.189
  [kaya-worker-05]=172.17.160.190
  [kaya-worker-06]=172.17.160.203
  [kaya-haproxy-01]=172.17.160.201
  [kaya-haproxy-02]=172.17.160.202
)

FAILED=()

for name in "${!NODES[@]}"; do
  ip="${NODES[$name]}"
  echo ">>> Dağıtılıyor: ${name} (${ip})"

  if ssh -i "${BOOTSTRAP_KEY}" \
      -o BatchMode=yes \
      -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=accept-new \
      "platform@${ip}" \
      "grep -qxF '${NEW_PUBKEY_CONTENT}' ~/.ssh/authorized_keys 2>/dev/null \
        || echo '${NEW_PUBKEY_CONTENT}' >> ~/.ssh/authorized_keys"
  then
    echo "    OK: ${name}"
  else
    echo "    HATA: ${name}"
    FAILED+=("${name} (${ip})")
  fi
done

echo
echo ">>> Doğrulama (yeni key ile şifresiz bağlantı testi):"
for name in "${!NODES[@]}"; do
  ip="${NODES[$name]}"
  if result=$(ssh -i "${DEPLOY_KEY}" -o BatchMode=yes -o ConnectTimeout=5 \
              "platform@${ip}" 'hostname' 2>/dev/null); then
    echo "    OK: ${name} -> ${result}"
  else
    echo "    BAŞARISIZ: ${name}"
    FAILED+=("doğrulama: ${name} (${ip})")
  fi
done

echo
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo ">>> Tamamlandı, tüm node'lar başarılı."
else
  echo "!!! Aşağıdaki node'larda sorun var:"
  printf '    - %s\n' "${FAILED[@]}"
  exit 1
fi