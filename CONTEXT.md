# Fathom — Domain Glossary

The words this project uses, with one meaning each. No implementation detail lives here.

## Library

The set of tracks stored on this device, however they arrived. A remote result
that has been downloaded is a Library track and is found like any other file.

## Origin

Whether a track's audio lives on the device or is still only a remote result. A
remote item is not playable: it becomes music by being downloaded, at which point
it is a Library track with a device origin. Every track has exactly one origin.

## Queue

The single ordered list of what plays next. It holds Library tracks only — a
remote result cannot be queued, because it has no audio to play yet. There is one
now-playing at a time.

## Stream

Not a Fathom concept. Fathom does not play from a remote address and keeps no
such path: a remote result is either downloaded or ignored. The word is kept here
only to say that anything reaching for it is reaching for something the app
deliberately does not have.

*(Until recently, playing a remote address straight through, leaving no copy on
the device. It was removed on purpose — a live remote address expires, is
throttled, and staying valid is what makes remote extraction fragile. Being a
fetcher and downloader is what lets Fathom depend on a maintained extractor
instead of owning that fight.)*

## Download

Writing a remote result's audio to the device as an ordinary media file. Once
written it is a Library track and is found by the Library like any other file —
Fathom does not keep it in a private set.

## Fetch

Getting a remote result's audio in order to Download it. A Fetch is the only
thing a remote result is for, and the only remote operation Fathom performs.
Fetching a result is what tapping it does.

## Manifest

The record of which remote tracks have been downloaded, keyed by their remote
identity. It exists so the same track is never fetched twice and so a download
can be recognised after it has become a Library track. It is a convenience, not
a source of truth: delete it and only the badges go, never the files.

## Track

One piece of music, whatever its origin. The name for the thing the Queue holds
and the player plays. A device track is a Track; a remote result is not yet one.

## Remote result

A YouTube Music item found by a Search, before it has been downloaded. It carries
no audio and can be neither queued nor played — it is a thing to Fetch. This is
the distinction the word Origin names.

## Query

The search text currently applied. There is one field and one query; a search
matches the Library first and then remote results, in that order.
## Search

Looking for music, in both origins at once. Local matches come first and remote
results follow them. A local match can be played; a remote result can only be
fetched, which is what tapping one does. Searching is not browsing: it has no
categories, no albums, no playlists.

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

It says the thing in two parts: a line that names what happened, and a second
that explains it when there is an explanation worth reading. The two are separate
because a failure is an outcome plus a cause, and a single line gets the cause
cut off first. A long-running message is the one kind that may carry its own way
out, because the user should not have to wait on something they have stopped
caring about.
