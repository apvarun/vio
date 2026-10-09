# Third-party notices

Vio's Swift code, build scripts, tests, and documentation use the MIT license
in `LICENSE`. The MIT license does not replace the licenses of bundled dependencies.

## Needle engine

Cactus Compute, Inc. provides the Needle engine under Apache-2.0.

- Bundled files: `Vendor/lib/libneedle.a`, `Vendor/CNeedle/include/needle.h`
- Source: https://github.com/cactus-compute/needle
- Download: https://huggingface.co/Cactus-Compute/needle3
- Asset revision: `2ae11323dc000f5e70c49f7403efa6af12ba9e67`
- License: `Licenses/Apache-2.0.txt`, copied from that asset revision

The bundled engine and header are unmodified upstream files. The upstream
source repository at `af2654dffa4987f7e2cbbacdf59c2f854fd18302` and the pinned
asset repository contain no separate NOTICE file. The source revision records
where we checked notices; it is not a verified build revision for the binary.

## Whistle model

Cactus Compute, Inc. provides the Whistle speech model under Apache-2.0.

- Bundled file: `Resources/whistle.cact`
- Source and download: https://huggingface.co/Cactus-Compute/whistle
- Asset revision: `b358ddadd89b7a713b5aa131f23032d3cca1b251`
- License: `Licenses/Apache-2.0.txt`, identical to the license at that revision

The bundled model is unmodified. Its pinned repository contains no separate
NOTICE file.

`Scripts/assets.json` records download URLs and SHA-256 checksums. App bundles
include these notices, Vio's MIT license, and the Apache-2.0 license in
`Contents/Resources/Licenses/`.
