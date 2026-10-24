# Installation rules (make install, and the Debian package).
#
#   ${AMAYA_LIBEXECDIR}/amaya, print     the programs
#   ${CMAKE_INSTALL_BINDIR}/amaya        script that starts the real program
#   ${AMAYA_DATADIR}/                    the run-time tree (THOTDIR):
#       config/ resources/ fonts/ dicopar/ doc/WX/ doc/images/ amaya/ contrib/
#   desktop entry, icon, AppStream metadata and manual page
#
# Amaya looks for its data two directories above its binary (a build
# directory inside the source tree) and otherwise in AMAYA_DATADIR, which is
# compiled in (thotlib/base/registry.c).  `print` must sit next to `amaya`.

install(TARGETS amaya print DESTINATION ${AMAYA_LIBEXECDIR})

configure_file(${CMAKE_SOURCE_DIR}/packaging/amaya.sh.in
               ${CMAKE_BINARY_DIR}/amaya.sh @ONLY)
install(PROGRAMS ${CMAKE_BINARY_DIR}/amaya.sh
        DESTINATION ${CMAKE_INSTALL_BINDIR} RENAME amaya)

# Run-time data, keeping the tree layout (the help pages use relative links
# such as ../../resources/icons)
install(DIRECTORY config resources fonts dicopar
        DESTINATION ${AMAYA_DATADIR}
        PATTERN ".cvsignore" EXCLUDE
        PATTERN "*.in" EXCLUDE
        PATTERN "bundle" EXCLUDE          # macOS application bundle
        PATTERN "*.win" EXCLUDE
        PATTERN "win-thot.rc" EXCLUDE
        PATTERN "amaya.kb-mac" EXCLUDE)
install(DIRECTORY doc/WX doc/images
        DESTINATION ${AMAYA_DATADIR}/doc)

# amaya/: schemas, welcome pages, style sheets, images; not the sources
install(DIRECTORY amaya/
        DESTINATION ${AMAYA_DATADIR}/amaya
        PATTERN "f" EXCLUDE
        PATTERN "generated" EXCLUDE
        PATTERN "mathedit" EXCLUDE
        PATTERN "wxdialog" EXCLUDE
        PATTERN "*.c" EXCLUDE
        PATTERN "*.h" EXCLUDE
        PATTERN "*.cpp" EXCLUDE
        PATTERN "*.ypp" EXCLUDE
        PATTERN "*.libwww" EXCLUDE
        PATTERN "*.S" EXCLUDE
        PATTERN "*.P" EXCLUDE
        PATTERN "*.T" EXCLUDE
        PATTERN "*.A" EXCLUDE
        PATTERN "*.inc" EXCLUDE
        PATTERN "*.sgml" EXCLUDE
        PATTERN "*.fig" EXCLUDE
        PATTERN "*.rc" EXCLUDE
        PATTERN "*.ico" EXCLUDE
        PATTERN "*.bmp" EXCLUDE
        PATTERN "*.cur" EXCLUDE
        PATTERN "*.xbm" EXCLUDE
        PATTERN "Makefile*" EXCLUDE
        PATTERN "CMakeLists.txt" EXCLUDE
        PATTERN ".cvsignore" EXCLUDE)

install(PROGRAMS contrib/firefox-cookies.py
        DESTINATION ${AMAYA_DATADIR}/contrib)

# Desktop integration
install(FILES packaging/amaya.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES resources/icons/misc/logo.png
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/128x128/apps
        RENAME amaya.png)
install(FILES packaging/amaya.metainfo.xml
        DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
install(FILES packaging/amaya.1
        DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
