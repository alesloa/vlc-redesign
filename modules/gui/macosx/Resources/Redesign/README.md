# Native VLC redesign assets

Each PDF is a vector representation of the unmodified exported SVG with the same
intrinsic width and height from `modules/gui/redesign/icons`. The source icons and
node provenance are recorded in that folder's README. AppKit draws these files
without changing their paths or aspect ratio. Video, Library, Network, Folder,
and the volume speaker use the horizontal mirror from the reference design at
render time; the asset files remain unchanged.

PDF representations preserve compatibility with the macOS versions supported by
this VLC interface, including versions without native SVG image support.
