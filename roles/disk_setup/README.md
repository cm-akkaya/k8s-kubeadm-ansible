# roles/disk_setup

Terraform ile oluşturulan node'larda iki tekrar eden disk sorununu çözer:

1. **Root LVM genişletme** — Golden Template'teki LVM (60GB) Terraform ile
   büyütülen diskin (ör. 100GB) tamamını kullanmaz. Bu rol, root LV'nin
   arkasındaki partition'ı (`growpart`), physical volume'u (`pvresize`) ve
   logical volume'u (`lvextend -l +100%FREE`) büyütüp dosya sistemini
   (`resize2fs`/`xfs_growfs`) genişletir.

2. **İkinci veri diski (Longhorn)** — `/dev/sdb` gibi formatsız ikinci diski
   (yalnızca boşsa) formatlar ve `/mnt/data01`'e kalıcı olarak (fstab/UUID ile)
   mount eder.

## Güvenlik modeli

Rol varsayılan olarak (`disk_setup_confirm: false`) **hiçbir değişiklik
yapmaz** — yalnızca mevcut durumu (`parted`, `vgs`, `blkid`, `findmnt`
çıktıları) `debug` ile raporlar. Gerçek değişiklik yalnızca
`-e disk_setup_confirm=true` verildiğinde ve yalnızca gerçekten gerekliyse
(idempotent) çalışır.

Kritik güvenlik garantisi: veri diski üzerinde `blkid` ile **zaten bir
dosya sistemi tespit edilirse `mkfs` asla çalıştırılmaz** — sadece mevcut
dosya sistemi tipiyle mount edilir. Böylece Longhorn zaten veri yazmış bir
diskin üzerine yanlışlıkla format atılamaz.

## Kullanım

```bash
# 1) Belirli bir node için sadece rapor al (hiçbir şey değişmez)
ansible-playbook playbooks/site.yml --tags disk_setup --limit kaya-worker-08

# Çıktıyı inceleyip "OK" dedikten sonra, SADECE o node'da uygula
ansible-playbook playbooks/site.yml --tags disk_setup --limit kaya-worker-08 \
  -e disk_setup_confirm=true

# Birden fazla node için tek tek onaylamak isterseniz --limit'i değiştirerek
# aynı iki adımı tekrarlayın; disk_setup_confirm=true'yu asla --limit'siz
# (tüm cluster'a) çalıştırmayın.
```

## Varsayılanlar (`defaults/main.yml`)

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `disk_setup_confirm` | `false` | `true` olmadan hiçbir değişiklik yapılmaz |
| `data_disk_device` | `/dev/sdb` | Longhorn için kullanılacak ikinci disk |
| `data_disk_mount` | `/mnt/data01` | Mount noktası |
| `data_disk_fstype` | `ext4` | Yalnızca disk formatsızsa kullanılır |
| `data_disk_mount_opts` | `defaults,noatime` | fstab mount seçenekleri |

## Sınırlamalar / bilinçli tasarım kararları

- Root VG birden fazla physical volume üzerine yayılmışsa (çok node'lu PV
  senaryosu) bu rol LVM büyütme adımını **otomatik atlar** ve uyarı basar;
  elle değerlendirme gerekir.
- Disk/partition adlandırması `sdX`/`sdXn` (VMware/vSphere `sd*` tipi disk)
  varsayımıyla yazılmıştır; NVMe (`nvme0n1p3` gibi) adlandırma bu ortamda
  kullanılmadığından desteklenmemiştir.
- `apt_cache_server` ve `image_registry_cache` rolleri `/mnt/data01`'i
  yalnızca *varsa* kullanır; bu rol çalıştırılmadan önce onlar çalışırsa
  cache verisi `/var/lib/...` altında kalmaya devam eder (zararsız, ama
  ilk kurulumda sıra önemlidir — bkz. `playbooks/site.yml` yorumu).
