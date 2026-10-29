#!/bin/zsh
set -euo pipefail

# A minimal SPDX software bill of materials for a release. Knittany has no third-party
# dependencies: it's built only on Apple's frameworks.

PROJECT_ROOT="${0:A:h:h}"
VERSION="${KNITTANY_VERSION:?Set KNITTANY_VERSION}"
OUTPUT_PATH="${1:-$PROJECT_ROOT/dist/releases/Knittany-$VERSION.spdx.json}"
COMMIT="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || print unknown)"
CREATED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "${OUTPUT_PATH:h}"
cat > "$OUTPUT_PATH" <<SBOM
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "Knittany-$VERSION",
  "documentNamespace": "https://github.com/beauregardhenry/knittany/sbom/Knittany-$VERSION-$COMMIT",
  "creationInfo": {
    "created": "$CREATED",
    "creators": [
      "Person: Beau Henry",
      "Tool: Knittany-generate-sbom"
    ]
  },
  "packages": [
    {
      "name": "Knittany",
      "SPDXID": "SPDXRef-Package-Knittany",
      "versionInfo": "$VERSION",
      "supplier": "Person: Beau Henry",
      "downloadLocation": "https://github.com/beauregardhenry/knittany/tree/v$VERSION",
      "filesAnalyzed": false,
      "licenseConcluded": "NOASSERTION",
      "licenseDeclared": "NOASSERTION",
      "copyrightText": "Copyright 2026 Beau Henry",
      "externalRefs": [
        {
          "referenceCategory": "PACKAGE-MANAGER",
          "referenceType": "purl",
          "referenceLocator": "pkg:github/beauregardhenry/knittany@$VERSION"
        }
      ]
    }
  ],
  "relationships": [
    {
      "spdxElementId": "SPDXRef-DOCUMENT",
      "relationshipType": "DESCRIBES",
      "relatedSpdxElement": "SPDXRef-Package-Knittany"
    }
  ]
}
SBOM

plutil -convert json -o /dev/null "$OUTPUT_PATH"
print "$OUTPUT_PATH"
