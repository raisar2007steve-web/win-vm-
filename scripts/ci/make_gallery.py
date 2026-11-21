#!/usr/bin/env python3
"""Build a self-contained HTML gallery for simulator screenshots."""
import html
import os
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: make_gallery.py <screenshots-dir> <index.html>")
        return 2

    source, destination = sys.argv[1], sys.argv[2]
    os.makedirs(source, exist_ok=True)
    images = sorted(name for name in os.listdir(source) if name.lower().endswith((".png", ".jpg", ".jpeg")))

    cards = []
    for name in images:
        title = os.path.splitext(name)[0].replace("-", " ").replace("_", " ")
        cards.append(
            f'<figure><img src="screenshots/{html.escape(name)}" alt="{html.escape(title)}" loading="lazy">'
            f"<figcaption>{html.escape(title)}</figcaption></figure>"
        )

    body = "\n".join(cards) if cards else '<p class="empty">No screenshots were captured for this run.</p>'
    document = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Notes — simulator test report</title>
<style>
  :root {{ color-scheme: light dark; }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 32px 24px 64px;
    font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #f5f5f7; color: #1d1d1f;
  }}
  @media (prefers-color-scheme: dark) {{
    body {{ background: #0b0b0d; color: #f5f5f7; }}
    figure {{ background: #1c1c1f !important; }}
    figcaption {{ color: #a1a1a6 !important; }}
  }}
  header {{ max-width: 1180px; margin: 0 auto 28px; }}
  h1 {{ font-size: 30px; letter-spacing: -0.02em; margin: 0 0 8px; }}
  p.sub {{ color: #6e6e73; margin: 0; font-size: 14px; }}
  .grid {{
    max-width: 1180px; margin: 0 auto;
    display: grid; gap: 20px;
    grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
  }}
  figure {{
    margin: 0; padding: 14px; border-radius: 18px; background: #fff;
    box-shadow: 0 1px 3px rgba(0,0,0,.08), 0 10px 30px rgba(0,0,0,.05);
  }}
  img {{ width: 100%; height: auto; display: block; border-radius: 12px; background: #000; }}
  figcaption {{ margin-top: 10px; font-size: 12px; color: #6e6e73; text-align: center; text-transform: capitalize; }}
  .empty {{ max-width: 1180px; margin: 0 auto; color: #6e6e73; }}
</style>
</head>
<body>
<header>
  <h1>Notes — live simulator test report</h1>
  <p class="sub">Screenshots captured on an iOS Simulator during the GitHub Actions run. {len(images)} image(s).</p>
</header>
<main class="grid">
{body}
</main>
</body>
</html>
"""
    os.makedirs(os.path.dirname(destination) or ".", exist_ok=True)
    with open(destination, "w") as handle:
        handle.write(document)
    print(f"Wrote gallery with {len(images)} screenshots to {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
