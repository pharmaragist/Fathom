# Fathom — Domain Glossary

The words this project uses, with one meaning each. No implementation detail lives here.

## Library

The set of tracks stored on this device, however they arrived. A stream that has
been downloaded is a Library track and is found like any other file.

## Origin

Whether a track's audio lives on the device or on YouTube Music. It decides how
artwork is read and how the player gets an address when playback starts. Every
track has exactly one origin.

## Queue

The single ordered list of what plays next. It accepts tracks of either origin.
There is one now-playing at a time regardless of origin.

## Stream

Playing a track straight from a remote address, leaving no copy on the device.

## Download

Writing a track's audio to the device as an ordinary media file. Once written it
is a Library track and is found by the Library like any other file — Fathom does
not keep it in a private set.

## Manifest

The record of which remote tracks have been downloaded, keyed by their remote
identity. It exists so the same track is never fetched twice and so a download
can be recognised after it has become a Library track. It is a convenience, not
a source of truth: delete it and only the badges go, never the files.

## Track

One playable piece of music, whatever its origin. The name for the thing the
Queue holds and the player plays.

## Query

The search text currently applied. There is one field and one query; a search
matches the Library first and then remote results, in that order.

## Search

Looking for tracks, in both origins at once. Local matches come first and remote
results follow them. Searching is not browsing: it has no categories, no
albums, no playlists.

## Preset

A saved equalizer curve with its preamp. Built-in, user-saved and imported
presets are all presets and are addressed the same way. Built-in names are
reserved.

## Low-end mode

A rendering choice, not a quality one: the app keeps every feature but stops
paying for blur, so cards become flat translucent panels. It changes how a
surface is drawn, never what it does. A track that plays one way plays the same
way with it on.

## Glass

The frosted surface the app's floating cards are made of. There is one such
card, worn by every panel, sheet and message; "glass" names the look, not a
component. With Low-end mode on the same card is drawn flat instead — the shape,
placement and content are identical, only the blur is gone.

## Destination

A place the shell can show: the Library or the Equalizer. There are two, and
they are not screens pushed on top of each other — both are always loaded, and
moving between them slides one past the other. A destination is entered by the
rail or by a swipe, and those are the only two ways; neither is "going back".

## Toast

A short message the shell shows below the header: something just happened, said
once, then gone. It is not a place to put a control and not a permanent notice —
anything that has to survive is held by the service that owns it, and the toast
is only the announcement.
