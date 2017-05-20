# Dropbox Uploader

Dropbox Uploader is a **BASH** script which can be used to upload, download, delete, list files (and more!) from **Dropbox**, an online file sharing, synchronization and backup service. 

It's written in BASH scripting language and only needs **cURL**.

Click on the fork link above to read about the original.

***

I needed to put this into production and the original didn't have `set -u`, proper quoting, help, delete after transfer, lftp style logging, wildcard matching, directory recursion, retry logic, or unit testing to show that everything works properly. I implemented them them all.

I implemented APIv2 as soon as it was advertized. AF implemented it later and so far as I know the config files are not compatible. You'll need to reregister or edit the config file to switch.

This is version you get with the Arch Linux [AUR](https://aur.archlinux.org/packages/dropbox-uploader-git/) package.
