# Security

Please report problems privately with GitHub's "Report a vulnerability" button (Security tab), not in a public issue.

- The app is sandboxed, uses the hardened runtime, and has no network entitlement.
- Images and PDFs are decoded by macOS frameworks (ImageIO, Core Graphics, Core Text). Keep macOS up to date.
- Printer replies are size-limited and cleaned before they are shown or logged.
- `Tests/fuzz.py` mutates sample files to look for crashes and hangs.
- Releases are not notarized by Apple. Check the SHA-256 file or build from source.
- This project has not been independently audited. Only the latest version gets fixes.
