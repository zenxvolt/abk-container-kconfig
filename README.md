# abk-container-kconfig

Modul eksternal untuk [ABK (AnyBase Kernel)](https://github.com/xingguangcuican6666/ABK) yang menambahkan beberapa opsi Kconfig sekaligus ke `gki_defconfig`.

Opsi yang diterapkan:

```
CONFIG_MACVLAN=y
CONFIG_IP6_NF_NAT=y
CONFIG_IP6_NF_TARGET_MASQUERADE=y
CONFIG_USER_NS=y
```

## Cara pakai

1. Buka **Actions** di fork ABK kamu, lalu jalankan workflow `kernel-custom.yml` (atau lewat app ABK).

2. Isi input `custom_external_modules` dengan:

   ```
   https://github.com/zenxvolt/abk-container-kconfig;before_build
   ```

3. Isi parameter build lainnya seperti biasa, lalu jalankan.

Tahap `before_build` dipilih supaya opsi ditulis setelah semua patch bawaan ABK selesai, tepat sebelum kompilasi.

## Mengubah daftar opsi

Edit array `OPTIONS` di `setup.sh`. Satu elemen = satu opsi, misalnya `"CONFIG_NAMA_OPSI=y"`.

Skrip ini idempotent: nilai lama (`=y`, `=m`, atau `# ... is not set`) dihapus dulu sebelum opsi ditulis ulang, dan build akan gagal dengan pesan jelas kalau ada opsi yang tidak masuk.

## Verifikasi setelah build

Di perangkat (perlu root):

```
zcat /proc/config.gz | grep -E 'MACVLAN|IP6_NF_NAT|IP6_NF_TARGET_MASQUERADE|USER_NS'
```

Kalau ada opsi yang hilang atau berstatus `is not set`, biasanya dependensinya belum aktif di kernel. Daftar dependensi umum ada di komentar bagian atas `setup.sh`.

## Keamanan

ABK menjalankan `setup.sh` dari repo modul ini di dalam workflow. Jangan menjalankan modul dari repo yang tidak kamu percayai, dan periksa isi skrip sebelum mengaktifkannya.
