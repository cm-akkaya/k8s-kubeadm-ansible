kubeadm-ansible

Ubuntu üzerinde kubeadm kullanarak HA Kubernetes cluster kurmak, sunucuların temel hardening işlemlerini uygulamak ve cluster yaşam döngüsünü Ansible ile yönetmek için hazırlanmış otomasyon projesidir.

Temel amaç, cluster'a özel bilgileri yalnızca inventory/variable katmanında tutmak; kubeadm, containerd, HAProxy, Keepalived, Cilium ve sistem konfigürasyonlarını Ansible ile otomatik üretmektir.

Bu proje önce lab ortamında geliştirilmiştir. Production kullanımı öncesinde firewall, secret yönetimi, backup/restore, upgrade ve kurum güvenlik standartları ayrıca değerlendirilmelidir.

1. Mimari

                    Kubernetes API VIP :6443
                             |
                 +-----------+-----------+
                 |                       |
             HAProxy-01              HAProxy-02
             Keepalived              Keepalived
                 |                       |
                 +-----------+-----------+
                             |
                 +-----------+-----------+
                 |           |           |
               CP-01       CP-02       CP-03
                 |           |           |
                 +-----------+-----------+
                             |
                 +-----------+-----------+
                 |           |           |
              Worker-01   Worker-02   Worker-03

Bileşen

Seçim

OS

Ubuntu 24.04 LTS

Kubernetes bootstrap

kubeadm

Container runtime

containerd

API HA

HAProxy + Keepalived

CNI

Cilium

Cilium routing

VXLAN tunnel

Cilium IPAM

Kubernetes host-scope

kube-proxy

Etkin, nftables mode

Ansible SSH user

k8sadmin

Lab geliştirmesinde kullanılan örnek sürümler:

Kubernetes : v1.35.7
containerd : 2.2.1
Cilium     : 1.20.0
OS         : Ubuntu 24.04

Bu sürümler kalıcı olarak "latest" kabul edilmemelidir. Her yeni cluster öncesinde hedef sürümler tekrar doğrulanmalıdır.

2. Repository Yapısı

kubeadm-ansible/
├── ansible.cfg
├── inventory/
│   ├── hosts.ini
│   ├── group_vars/
│   │   ├── all.yml
│   │   ├── kubernetes.yml
│   │   └── load_balancers.yml
│   └── host_vars/
│       ├── <load-balancer-01>.yml
│       └── <load-balancer-02>.yml
├── playbooks/
│   ├── preflight.yml
│   ├── reset.yml
│   └── site.yml
└── roles/
    ├── common/
    ├── os_hardening/
    ├── k8s_prerequisites/
    ├── containerd/
    ├── kubernetes_packages/
    ├── haproxy/
    ├── keepalived/
    ├── kubeadm_init/
    ├── control_plane_join/
    ├── cilium/
    ├── worker_join/
    ├── post_checks/
    └── kubeadm_reset/

3. Source of Truth

inventory + group_vars + host_vars
              |
              v
      Ansible roles/templates
              |
              +--> /etc/hosts
              +--> /root/cluster.env
              +--> /root/node.env
              +--> kubeadm YAML
              +--> containerd config
              +--> crictl config
              +--> HAProxy config
              +--> Keepalived config

cluster.env, node.env ve sunucu üzerindeki Kubernetes/HAProxy/Keepalived dosyaları input değildir. Bunlar Ansible'ın ürettiği çıktılardır.

4. Yeni Cluster İçin Değiştirilecek Dosyalar

Dosya

Ne zaman?

İçerik

inventory/hosts.ini

Her cluster

Hostname + management IP

inventory/group_vars/all.yml

Her cluster

VIP, DNS, CIDR, sürümler

inventory/group_vars/kubernetes.yml

Mimari değişirse

CRI, Cilium, kube-proxy tercihleri

inventory/group_vars/load_balancers.yml

Kontrol et

Keepalived VRID/authentication

inventory/host_vars/<lb>.yml

LB topolojisi değişirse

MASTER/BACKUP, priority, peer

Elle değiştirilmemesi gereken generated dosyalar

/root/cluster.env
/root/node.env
/etc/hosts
/etc/containerd/config.toml
/etc/crictl.yaml
/etc/haproxy/haproxy.cfg
/etc/keepalived/keepalived.conf
/etc/kubernetes/admin.conf
/etc/kubernetes-kubeadm-init.yaml
/etc/kubeadm-join-control-plane.yaml
/etc/kubeadm-join-worker.yaml

Manuel değişiklikler bir sonraki Ansible çalıştırmasında üzerine yazılabilir.

5. Inventory

inventory/hosts.ini örneği:

[load_balancers]
lb01 ansible_host=10.10.10.10
lb02 ansible_host=10.10.10.11

[control_plane]
cp01 ansible_host=10.10.10.12
cp02 ansible_host=10.10.10.13
cp03 ansible_host=10.10.10.14

[workers]
worker01 ansible_host=10.10.10.15
worker02 ansible_host=10.10.10.16
worker03 ansible_host=10.10.10.17

[kubernetes:children]
control_plane
workers

Inventory hostname'ları gerçek sunucu hostname'ları ile aynı tutulmalıdır. control_plane grubundaki ilk node otomatik olarak primary control-plane kabul edilir.

6. Cluster Değişkenleri

inventory/group_vars/all.yml örneği:

---
ansible_user: k8sadmin
ansible_become: true
ansible_become_method: sudo
ansible_python_interpreter: /usr/bin/python3

cluster_name: "kubeadm-lab"

api_fqdn: "api.k8s.example.local"
api_vip: "10.10.10.20"
api_port: 6443
vip_prefix: 24

pod_cidr: "172.20.0.0/16"
service_cidr: "172.21.0.0/16"
timezone: "Europe/Istanbul"

kubernetes_minor_version: "v1.35"
kubernetes_version: "v1.35.7"
kubernetes_package_version: "1.35.7-1.1"
containerd_package_version: "2.2.1-1~ubuntu.24.04~noble"
cilium_version: "1.20.0"

primary_control_plane: "{{ groups['control_plane'] | first }}"
k8s_node_ip: "{{ ansible_host }}"
k8s_interface: "{{ ansible_facts['default_ipv4']['interface'] }}"

Her yeni cluster'da özellikle kontrol et:

cluster_name
api_fqdn
api_vip
vip_prefix
pod_cidr
service_cidr
kubernetes_minor_version
kubernetes_version
kubernetes_package_version
containerd_package_version
cilium_version

Normalde elle değiştirilmemesi gereken otomatik değerler:

primary_control_plane: "{{ groups['control_plane'] | first }}"
k8s_node_ip: "{{ ansible_host }}"
k8s_interface: "{{ ansible_facts['default_ipv4']['interface'] }}"

7. Kubernetes ve Cilium Değişkenleri

inventory/group_vars/kubernetes.yml:

---
cri_socket: "unix:///run/containerd/containerd.sock"
kube_proxy_mode: "nftables"
cilium_ipam_mode: "kubernetes"
cilium_routing_mode: "tunnel"
cilium_tunnel_protocol: "vxlan"
cilium_kube_proxy_replacement: false

Aynı mimari kullanılacaksa yeni cluster'da değiştirilmez. CRI, kube-proxy, Cilium IPAM veya routing modeli değişiyorsa yeniden değerlendirilmelidir.

8. Load Balancer Değişkenleri

inventory/group_vars/load_balancers.yml:

---
keepalived_virtual_router_id: 51
keepalived_auth_pass: "CHANGE_ME"

Aynı L2/VLAN üzerinde birden fazla Keepalived yapısı varsa VRID değerleri çakışmamalıdır. Production'da authentication bilgisi plaintext Git variable olarak tutulmamalıdır.

inventory/host_vars/lb01.yml:

---
keepalived_state: "MASTER"
keepalived_priority: 110
keepalived_peer_host: "lb02"

inventory/host_vars/lb02.yml:

---
keepalived_state: "BACKUP"
keepalived_priority: 100
keepalived_peer_host: "lb01"

Host vars dosya adı inventory hostname ile aynı olmalıdır.

9. Network Planlama

Deploy öncesinde:

API VIP kullanılmayan bir IP olmalı.

API FQDN bütün Kubernetes node'larından VIP'e çözülebilmeli.

Pod CIDR fiziksel network, VPN ve diğer route'larla çakışmamalı.

Service CIDR, Pod CIDR ve fiziksel network ile çakışmamalı.

HAProxy node'ları control-plane TCP/6443'e ulaşabilmeli.

Kubernetes node'ları gerekli package/image registry'lerine ulaşabilmeli.

Cilium VXLAN node-to-node trafiği engellenmemeli.

Keepalived için ilgili L2 network üzerinde VRRP çalışabilmeli.

İlk lab sürümünde host firewall bilinçli olarak sade tutulmuştur. Production firewall politikası Kubernetes, etcd, kubelet, Cilium VXLAN, HAProxy ve VRRP birlikte düşünülerek oluşturulmalıdır.

10. Sürüm Yönetimi

Şu üç Kubernetes değeri birlikte yönetilmelidir:

kubernetes_minor_version
kubernetes_version
kubernetes_package_version

Örneğin Kubernetes v1.35.x kurulacaksa package repository minor değeri de v1.35 olmalıdır.

containerd_package_version hedef Ubuntu sürümünün Docker repository'sinde mevcut olmalıdır. Cilium sürümü hedef Kubernetes sürümü ile uyumlu olmalıdır.

Sürümleri açıkça pinlemek cluster'ın tekrar üretilebilirliğini artırır.

11. Ansible Controller Gereksinimleri

Playbook Kubernetes network'üne erişebilen bir Linux/WSL Ansible controller'dan çalıştırılabilir.

Controller tüm node'lara SSH ile erişebilmeli.

k8sadmin SSH key ile bağlanabilmeli.

k8sadmin gerekli sudo/become yetkisine sahip olmalı.

Hedef sistemlerde Python 3 bulunmalı.

Inventory IP'leri controller'dan erişilebilir olmalı.

İlk test:

ansible all -m ping

Bütün node'larda pong beklenir.

12. Preflight

ansible-inventory --graph

ansible all -m ping

ansible-playbook playbooks/site.yml --syntax-check

ansible-playbook playbooks/preflight.yml

Preflight sonunda unreachable=0 ve failed=0 beklenir.

13. Deploy

ansible-playbook playbooks/site.yml

Genel sıra:

Preflight
  -> common
  -> OS hardening
  -> Kubernetes prerequisites
  -> containerd
  -> kubelet/kubeadm/kubectl
  -> HAProxy/Keepalived
  -> primary control-plane kubeadm init
  -> secondary control-plane join
  -> Cilium
  -> worker join
  -> post checks

site.yml --check, gerçek cluster bootstrap testi olarak kabul edilmemelidir. kubeadm init/join, paket kurulumu ve service durumları birbirine bağlıdır.

14. Minimal Deploy Sonrası Kontroller

kubectl get nodes -o wide

3 control-plane ve tüm worker node'ların Ready olması beklenir.

kubectl get pods -A -o wide

kubectl -n kube-system get pods -l k8s-app=cilium -o wide

kubectl -n kube-system rollout status daemonset/cilium --timeout=300s

API VIP:

nc -zv -w 3 <API_VIP> 6443

15. Idempotency Testi

İlk başarılı kurulumdan sonra playbook tekrar çalıştırılmalıdır:

ansible-playbook playbooks/site.yml

İkinci çalıştırmada gereksiz changed sonuçlarının mümkün olduğunca az olması beklenir. Var olan cluster'da kubeadm init ve join işlemleri tekrar yapılmamalıdır.

16. Cluster Reset

UYARI: Reset playbook mevcut Kubernetes cluster durumunu siler. Hedef inventory mutlaka doğrulanmalıdır.

Önce:

ansible-playbook playbooks/reset.yml --syntax-check

ansible-playbook playbooks/reset.yml --list-hosts

Lab reset:

ansible-playbook playbooks/reset.yml

Reset sırası:

Workers
  -> secondary control-planes
  -> primary control-plane
  -> HAProxy/Keepalived stop

Kontroller:

ansible kubernetes -b -m shell -a 'systemctl is-active kubelet || true'

ansible load_balancers -b -m shell -a 'systemctl is-active haproxy keepalived || true'

Eski CNI dosyası kontrolü:

ansible kubernetes -b -m shell -a 'find /etc/cni/net.d -mindepth 1 -maxdepth 1 -type f -printf "%f\n"'

/etc/cni/net.d dizininin yeniden oluşması tek başına sorun değildir. Önemli olan eski CNI config dosyalarının kalmamasıdır.

17. Bilinen Sorunlar ve Öğrenilenler

crictl endpoint

crictl açıkça containerd socket'e yönlendirilmelidir:

runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false

Kontrol:

sudo crictl info

HAProxy config değişiyor fakat VIP:6443 çalışmıyor

Lab sırasında HAProxy config değişmesine rağmen servis restart edilmediğinde VIP:6443 bağlantısı başarısız oldu. HAProxy template değişikliği restart handler tetiklemeli ve config restart öncesi validate edilmelidir.

sudo haproxy -c -f /etc/haproxy/haproxy.cfg

nc -zv -w 3 <API_VIP> 6443

containerd Unhold hatası

Paket ilk kez kurulurken dpkg_selections ile önceden selection: install uygulanması hata verebilir.

Doğru sıra:

Docker repository
  -> apt update
  -> pinned containerd install/upgrade
  -> hold containerd
  -> containerd config

Pinned install task'ı gerektiğinde held package değişikliğine izin verecek şekilde yönetilmelidir.

Deprecated apt_repository

Repository tanımlarında apt_repository/apt_key yerine ansible.builtin.deb822_repository kullanılmaktadır. python3-debian common role tarafından kurulmalıdır ve repository değişikliğinden sonra apt cache güncellenmelidir.

Kontrol:

rg -n "apt_repository|apt_key" roles

İdeal durumda sonuç dönmez.

Cilium ve hardening

Cilium network davranışını etkileyebilecek rp_filter, firewall ve benzeri kernel/network hardening ayarları CNI datapath ile birlikte değerlendirilmelidir. İlk lab sürümünde bu alan bilinçli olarak muhafazakâr tutulmuştur.

18. Güvenlik

Mevcut yaklaşım:

SSH key tabanlı erişim

root yerine k8sadmin

sudo/become ile yetki yükseltme

swap kapalı

gerekli kernel module/sysctl ayarları

containerd systemd cgroup

pinned Kubernetes/containerd paketleri

Production geliştirmeleri:

Ansible Vault veya harici secret manager

host firewall policy

CIS Ubuntu/Kubernetes değerlendirmesi

auditd ve Kubernetes audit logging

etcd snapshot/restore otomasyonu

certificate expiration monitoring

RBAC standardizasyonu

Pod Security politikaları

image/registry security

upgrade ve rollback prosedürü

Git'e plaintext olarak özellikle şunlar commit edilmemelidir:

Keepalived authentication secret
kubeadm join token
kubeadm certificate key
SSH private key
registry credentials

19. Yeni Cluster Checklist

Altyapı

2 load balancer hazır

3 control-plane hazır

Worker node'lar hazır

Ubuntu sürümü doğrulandı

IP'ler statik

API VIP boş

API FQDN planlandı

NTP/time synchronization çalışıyor

Network

Node subnet belirlendi

Pod CIDR çakışmıyor

Service CIDR çakışmıyor

API VIP çakışmıyor

HAProxy -> control-plane TCP/6443 erişimi var

Cilium node-to-node trafiği mümkün

Ansible

inventory/hosts.ini güncellendi

group_vars/all.yml güncellendi

Kubernetes/containerd/Cilium sürümleri doğrulandı

Load balancer variables kontrol edildi

SSH key erişimi çalışıyor

ansible all -m ping başarılı

syntax-check başarılı

preflight başarılı

Deployment

site.yml başarılı

Control-plane node'ları Ready

Worker node'ları Ready

CoreDNS Running

Cilium Running

kube-proxy Running

HAProxy aktif

Keepalived VIP aktif

API VIP:6443 erişilebilir

ikinci site.yml idempotency testi yapıldı

20. Faydalı Komutlar

ansible-inventory --graph
ansible all -m ping
ansible all -m setup -a 'filter=ansible_default_ipv4'
ansible-playbook playbooks/site.yml --syntax-check
ansible-playbook playbooks/preflight.yml
ansible-playbook playbooks/site.yml

kubectl get nodes -o wide
kubectl get pods -A -o wide
sudo crictl info
sudo systemctl status containerd

21. Çoklu Cluster İçin Sonraki Adım

Repository olgunlaştığında inventory yapısı şu modele taşınabilir:

inventories/
├── lab/
│   ├── hosts.ini
│   ├── group_vars/
│   └── host_vars/
├── production/
│   ├── hosts.ini
│   ├── group_vars/
│   └── host_vars/
└── customer-x/
    ├── hosts.ini
    ├── group_vars/
    └── host_vars/

Böylece roles/ ve playbooks/ cluster'a göre değiştirilmez; sadece inventory seçilir.

Ek geliştirme olarak Keepalived MASTER/BACKUP, priority ve peer bilgilerinin inventory sırasından otomatik türetilmesiyle LB host_vars ihtiyacı azaltılabilir.

22. Referanslar

Kubernetes kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/

kubeadm reset: https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-reset/

Kubernetes package repositories: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/

Cilium kubeadm: https://docs.cilium.io/en/stable/installation/k8s-install-kubeadm/

Docker Ubuntu: https://docs.docker.com/engine/install/ubuntu/

Ansible: https://docs.ansible.com/

Cluster'a özel IP, hostname, Kubernetes sürümü, VIP veya CIDR bilgileri role/playbook içerisinde hard-code edilmemelidir. Mümkün olduğunca inventory altındaki variable katmanı kullanılmalıdır.
