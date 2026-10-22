# iOS release notes (App Store Connect "What's New")

**Use this file for App Store Connect What's New — NOT `CHANGELOG.md`.**

`CHANGELOG.md` is written for the Android sideload audience (GitHub Releases)
and deliberately contains things App Store review rejects. Guideline 2.3.10
("Accurate Metadata") flagged 0.5.1 (36) because the notes named another
platform and carried engine/implementation detail.

## Rules for this file

- **Never name another platform.** No "Android", no "on Android it's...".
  Every iOS user has an Android phone; it is not a comparison they asked for.
- **No engine names.** "MPV", "libmpv", "Media3", "ExoPlayer" are Android
  implementation detail. Describe the behaviour instead: "plays", "the
  fallback player".
- **No internal identifiers.** No `SystemCodec`, `Activity`, `HTTP 400`,
  pixel widths, dB figures, class or function names, or commit details.
- **Only ship what iOS users got.** A large part of each changelog entry is
  Android-only. If it is not visible or reachable on iOS, it does not go here.
- Lead with user-visible behaviour, one line per change, ~4000 character cap.

## Which build each section describes

A section must only claim what is **actually in that build**, not what is on
`main`. TestFlight 43 was commit `9d75ae3`; the shipped 0.5.2 is build 49
(commit `a550985`). Anything committed after the section's build belongs in
the *next* section.

An earlier draft of this file advertised chapter markers in 0.5.1, which was
true of the intended build but not of the one that was reviewed. Verify with
`git log <build-commit>..main` before writing a section, not `git log v0.5.1..main`.

---

## 0.5.2

New:
• Five app icons to choose from in Settings → Appearance. Pick the original logo
  and wordmark, the logo on its own, or the logo in red, green or cyan; the
  change applies straight away, with no reinstall. The wordmark-free logo is
  handy when your device already prints the app name underneath the icon.
• An optional second metadata catalogue in Settings → Metadata, for titles the
  main catalogue does not carry. It needs no account, key or sign-in and matches
  films by name, release code or numeric ID, with poster art and details like
  any other match. It is off until you switch it on, covers films only, and
  titles that already match are unaffected.

Fixed:
• The icon picker could fail to open on smaller screens.
• The file browser no longer offers a Delete option on iPhone and iPad, where it
  had no effect.
• Pulling down to refresh the list of shared folders no longer reports that the
  folder could not be read.
• Every shared folder on the server now appears in the list, not just folders
  with common names.
• Restoring a purchase now asks the App Store directly and re-reads what your
  account owns, instead of relying on a delayed notification.
• Folders now come before files when you browse a shared folder, each in
  alphabetical order.

---

## 0.5.1

• In-app SMB on iPhone and iPad — browse shares, pin folders to Home and
  play, without leaving the app.

• Fixed a freeze that could make a title's details page hang for up to a
  minute on iPhone and iPad.

• Chapter markers now appear on the seekbar, with previous/next chapter
  buttons either side of play/pause. They now work on network shares and
  in-app SMB as well as local files.

• Browsing an SMB share is faster and more reliable: files open first
  time, bookmarked folders reconnect to the right share, printer and
  parent-folder entries no longer appear in listings, and saved servers
  show green when reachable. Servers saved without a name now show their
  address.

• Resume position and audio track selection now survive switching audio
  track, so playback no longer restarts from the beginning.

• Episode and movie artwork appears in more places and loads faster.

• Adjustable episode-list thumbnails (Settings → Layout), and titles stay
  readable offline.

• Changing a poster or backdrop now applies everywhere that title appears.

• Fixed artwork and layout issues on larger iPad screens.
