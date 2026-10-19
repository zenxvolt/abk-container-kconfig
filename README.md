# cgroup CPU & PID limits untuk GKI android12-5.10 (5.10.236)

Port dari `fix_cgroup_limits_kabi_5.15.167.patch` (repo Droidspaces_Kernel_patch/cgroup_limits)
ke kernel **android12-5.10**, supaya Droidspaces bisa memakai limit CPU (`cpu.cfs_quota_us`,
`cpu.cfs_period_us`) dan limit PID (`pids.max`) tanpa mengubah KMI.

| File | Fungsi |
|---|---|
| `fix_cgroup_limits_kabi_5.10.236.patch` | Patch kernel (12 file) |
| `setup.sh` | Menerapkan patch + mengaktifkan `CONFIG_CFS_BANDWIDTH=y` dan `CONFIG_CGROUP_PIDS=y`, ditambah opsi ekstra `CONFIG_MACVLAN=y`, `CONFIG_IP6_NF_NAT=y`, `CONFIG_IP6_NF_TARGET_MASQUERADE=y`, `CONFIG_USER_NS=y` |

Opsi ekstra (MACVLAN, IPv6 NAT, USER_NS) hanya mengubah defconfig dan tidak berhubungan dengan isi patch.
`old-setup.sh` tidak diperlukan lagi karena opsinya sudah digabung ke `setup.sh`.

## Cara pakai di workflow ABK

1. Buat repo GitHub publik baru (nama bebas), taruh **ketiga file ini di root repo**.
2. Jalankan workflow `kernel-a12-5-10` (atau `kernel-custom`) dan isi:
   - aktifkan opsi custom external modules
   - `custom_external_modules`: `https://github.com/<username>/<nama-repo>;after_patch`
3. Di log harus muncul `cgroup-limits: patch applied`, `added CONFIG_CFS_BANDWIDTH`, `added CONFIG_CGROUP_PIDS`.
   Tiap opsi ekstra juga tercatat satu baris. Bunyinya tergantung isi `gki_defconfig` kernel:
   `added`, `switched on`, `changed ... to =y`, atau `already enabled`. Log diakhiri `cgroup-limits: done`.

`setup.sh` menolak berjalan pada kernel selain 5.10, memakai pencocokan ketat (tanpa fuzz), dan
kalau patch tidak cocok ia berhenti tanpa mengubah apa pun (defconfig juga tidak disentuh).
Menjalankannya dua kali aman.

## Opsi Kconfig yang diaktifkan

Semua opsi ditulis sebagai `=y` di `gki_defconfig`, setelah patch berhasil diterapkan:

- Opsi yang sudah `=y` dibiarkan.
- `# CONFIG_X is not set` diubah menjadi `CONFIG_X=y`.
- `CONFIG_X=m` atau `=n` diganti menjadi `=y` (tidak meninggalkan baris ganda).
- Opsi yang belum ada ditambahkan di akhir file.
- Di akhir ada verifikasi. Kalau ada opsi yang tidak masuk, skrip gagal dengan pesan `::error::`.

Catatan dependensi (bisa berbeda per versi kernel). Kconfig membuang opsi yang dependensinya tidak
terpenuhi tanpa pesan error:

- `CONFIG_IP6_NF_NAT` membutuhkan `CONFIG_IP6_NF_IPTABLES`, `CONFIG_NF_CONNTRACK` dan `CONFIG_NETFILTER_ADVANCED`.
- `CONFIG_IP6_NF_TARGET_MASQUERADE` membutuhkan `CONFIG_IP6_NF_NAT`.
- `CONFIG_CFS_BANDWIDTH` membutuhkan `CONFIG_FAIR_GROUP_SCHED` dan `CONFIG_CGROUP_SCHED`.
- `CONFIG_CGROUP_PIDS` membutuhkan `CONFIG_CGROUPS`.

Kalau suatu opsi hilang setelah build, cek dependensinya di `/proc/config.gz`.

## Setelah flash, cek dari Termux (root)

```sh
su -c "zcat /proc/config.gz | grep -E 'CFS_BANDWIDTH|CGROUP_PIDS'"
su -c "zcat /proc/config.gz | grep -E 'CONFIG_MACVLAN|IP6_NF_NAT|IP6_NF_TARGET_MASQUERADE|CONFIG_USER_NS'"
su -c "grep -E '^(cpu|pids)[[:space:]]' /proc/cgroups"
su -c "ls /dev/cpuctl/ | grep cfs"     # cpu.cfs_quota_us, cpu.cfs_period_us (path bisa berbeda per ROM)
```

Semua opsi di perintah pertama dan kedua harus tampil sebagai `=y`.

## Cara kerja singkat

- `pids` ditaruh di ID subsistem paling belakang, dan array `css_set`/`cgroup` tetap berukuran sama
  seperti KMI beku. State pids disimpan di objek ekstensi yang dialokasikan tepat di belakang struct.
- State CFS bandwidth dipindah dari `cfs_rq`/`task_group` ke objek terpisah. Pointer-nya memakai slot
  `ANDROID_KABI_RESERVE(2)` di `task_group` dan tail padding di `cfs_rq`, jadi offset dan `sizeof`
  `cfs_rq`/`rq` tidak berubah.
- Member baru disembunyikan dari `genksyms` supaya CRC simbol (MODVERSIONS) tetap sama dan modul vendor
  dari firmware stock masih bisa dimuat.

## Yang sudah dan belum diuji

Sudah (di sandbox, source `android12-5.10-2025-05`, 5.10.236):
- Patch bisa diterapkan tanpa fuzz di `android12-5.10-2025-05` `_r1` sampai `_r5` dan HEAD branch.
- Kompilasi bersih (clang 18) untuk 4 kombinasi (PIDS dan CFS_BANDWIDTH masing-masing mati/hidup),
  plus 744 objek di `kernel/ mm/ block/ fs/ net/core drivers/android`.
- Layout `css_set`, `cgroup`, `cgroup_root`, `cfs_rq`, `rq`, `task_group`: semua offset lama dan `sizeof`
  identik dengan kernel asli.
- Teks definisi struct yang dilihat `genksyms` identik dengan kernel asli (perbandingan teks, bukan
  menjalankan `genksyms` itu sendiri).
- Logika penambahan opsi Kconfig di `setup.sh` (semua enam opsi) diuji pada defconfig tiruan:
  kasus opsi hilang, `=m`, `is not set`, sudah `=y`, dan dijalankan dua kali (hasilnya identik, tanpa baris ganda).

**Belum diuji:** boot di perangkat, build asli ABK (clang Android r416183b, LTO/CFI), kombinasi dengan
SUSFS/BakaSU, kelakuan runtime Droidspaces, menjalankan `setup.sh` utuh pada source kernel asli, dan
dampak opsi ekstra (`MACVLAN`, `IP6_NF_NAT`, `IP6_NF_TARGET_MASQUERADE`, `USER_NS`) terhadap KMI dan CRC simbol.
Simpan boot image stock/yang sudah jalan sebelum flash.
