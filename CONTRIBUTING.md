# Contributing

You're free to fork, change and share this project under the GPL-3.0 licence. Shared versions stay under GPL-3.0, with source code and credits kept.

## Adding a printer
Open a pull request with:
- the printer model and firmware (shown by **Check printer** or in the log), and your Mac and macOS version
- a photo of a real print next to the original image, from the code in the pull request
- the app's log, after removing anything personal such as the printer's Bluetooth name
- whether the PeriPage A6 (203 dpi) still works, or that you couldn't test it

Useful tests: a first print right after connecting, a second print on the same connection, a long image, Cancel, and printing with no paper. Be careful with new status commands: on the A6, one of them shifted the next print (see CHANGELOG.md).

Working on your hardware is required, but doesn't guarantee that a change is accepted. The maintainer can't test printers they don't own, so accepted models are marked "tested by the community".

## Any change
- Run `./test.sh` and `./build.sh`.
- Keep it small and simple, and say what you tested and what you didn't.
- No network access, analytics, accounts or new permissions without discussing it first in an issue.
- By contributing, you agree that your work is released under GPL-3.0.
- Security problems: see SECURITY.md, not a public issue.
