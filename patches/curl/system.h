/*
 * thotlib/internals/h/system.h
 *
 * Forwarding shim: when curl/curl.h does #include "system.h", the
 * compiler finds this file via the thotlib include path.  We detect
 * that context via CURLINC_CURL_H (defined in curl.h's own include guard)
 * and forward to the real curl system detection header.
 *
 * Outside of curl context this file is intentionally empty.
 * The original file had #error "system.h included" as a build trap;
 * that trap is incompatible with libcurl.
 */
#ifdef CURLINC_CURL_H
#  include <curl/system.h>
#endif
