# Murmur Workspace and Branching

## Canonical root
`/home/uprootiny/fie/murmur`

## Non-canonical paths
Ignore `/tmp/*` scaffolds and temporary repos.

## Branching
- Keep changes small and merge-friendly.
- Use short-lived branches like `stability/healthy-build`.

## Verification flow
1) `swift build -c release`
2) `swift test`
3) Run app and check logs in:
   `~/Library/Application Support/Murmur/Logs/murmur.log`
