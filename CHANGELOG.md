# Changelog

## 1.0
First public release.

Protocol note for PeriPage A6, firmware V1.11: the "everything" information query (10 FF 70 F1) makes the next print start about 5 mm too far right, until something has been printed. Found with blind tests on paper. The separate firmware (10 FF 20 F1) and battery (10 FF 50 F1) queries don't. Earlier tests that blamed joins between rasters were unreliable for this reason, so whether joins matter is not known.

Connection note: on macOS, reopening a channel right after closing it, or about 2 seconds later while the idle link is dropped, gets no answer. The app closes the whole link and waits for the disconnect notification, and reuses an open link for 30 seconds.

Paper: status query 10 FF 40 answered 00 with paper, and 04 (once 06) without. The app treats the 04 flag as out of paper; the 02 flag is unknown. Printing without paper gives no error otherwise.
