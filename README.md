# Repository for Kivitendo with Docker.

## Roadmap

- [ ] **Shave the last ~180 MB off the image via a minimal `tlmgr` TeX install (later).**
  The image is currently ~1.07 GB (down from 2.5 GB). The Debian base and the
  Perl/Apache/pg-client layer are already at their practical floor; TeXLive
  (~240 MB) is the only substantial lever left. Replace the Debian `texlive-*`
  packages with a minimal `tlmgr` install shipping only the `.sty`/class files
  the templates use — could drop TeX from ~240 MB to ~60 MB.
  - Enumerate required packages with `scripts/installation_check.pl --latex`
    (all master templates) **and** against the real `druckvorlagen/cvs`
    templates (git-ignored, mounted at runtime — must be supplied to test).
  - Known-needed so far: inputenc, fontenc, eurosym, transparent, fontspec,
    embedfile, longtable, colortbl, graphicx, hyperref, geometry, ulem,
    xstring, scrartcl (KOMA), latexsym, textcomp, iftex, ifthen, german.
  - Re-run `installation_check.pl --latex` until all green.
