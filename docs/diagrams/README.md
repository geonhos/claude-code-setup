# Diagrams

The `.mmd` files are the source of truth; the `.svg` files are rendered from them
and embedded in [`../architecture.md`](../architecture.md).
Re-render one with `mmdc -i X.mmd -o X.svg --backgroundColor white`
(or all: `for f in *.mmd; do mmdc -i $f -o ${f%.mmd}.svg --backgroundColor white; done`),
and update the matching Mermaid block in `architecture.md`.
