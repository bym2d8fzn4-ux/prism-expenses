# Prism Expenses

Prism Expenses is maintained as one product with two parallel app surfaces:

- `web/` contains the static web app published with GitHub Pages.
- `ios/` contains the native SwiftUI iPhone app.
- `docs/` contains the shared product and data notes that both apps should follow.

The goal is for the web app and iOS app to share the same backup format, status logic, categories, trip/aircraft fields, and visual direction while still using platform-native implementation patterns.

## Local Web Preview

```sh
cd web
python3 -m http.server 4173
```

Then open `http://localhost:4173`.

## GitHub Pages

This repo is configured to publish the static `web/` folder through GitHub Pages using `.github/workflows/pages.yml`.

After pushing to a public GitHub repository, enable Pages in the repository settings if GitHub does not enable it automatically:

`Settings -> Pages -> Build and deployment -> Source: GitHub Actions`
