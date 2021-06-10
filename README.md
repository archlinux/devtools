# Devtools - development tools for Arch Linux

This repository contains tools for the Arch Linux distribution for building
and maintaining official repository packages.

## Patches

Patches can be send to arch-projects@archlinux.org or via a pull request on
Github. When sending patches to the mailing list make sure to set a valid
subjectprefix otherwise the email is denied by mailman. Git can be configured
as following.

```
git config format.subjectprefix 'devtools] [PATCH'
```

## Releasing

1. bump the version in the Makefile
2. Commit everything as  ```Version $(date +"%Y%m%d")```
3. Create a new tag ```git tag -s $(date +"%Y%m%d")```
4. Push changes
5. Upload the source tarball with ```make dist upload```
6. Update the package

## License

Devtools is licensed under the terms of the **GPL-3.0-or-later** (see [LICENSE](LICENSE)).
