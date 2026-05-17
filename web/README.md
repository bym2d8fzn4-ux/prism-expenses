# Expenses

Expenses is a small installable iPhone-friendly PrismJet expense tracker for work travel.

It lets you:

- Save the amount, expense or incentive date, airport, aircraft, notes, submitted date, and paid date
- Attach a receipt photo from the camera or photo library
- Filter expenses and incentives by submission and paid status
- Group entries by trip, week, airport, aircraft, vendor, or category
- Export a JSON backup so your records are not trapped on one device

## Why this version is a web app

This is the fastest way to get you a usable iPhone app without dealing with the App Store first.

Once this page is hosted online, you can open it in Safari on your iPhone and use **Add to Home Screen**. It will behave like an app and can work offline after the first load.

## Files

- `index.html`: app layout
- `styles.css`: mobile-first styling
- `app.js`: expense storage, photo handling, filters, import/export
- `manifest.webmanifest` and `service-worker.js`: installable/offline support

## Local preview on your Mac

From this folder, run:

```bash
python3 -m http.server 8000
```

Then open:

[http://127.0.0.1:8000](http://127.0.0.1:8000)

## Using it on your iPhone

You have a few easy options:

1. Host these files on a simple static site such as GitHub Pages, Netlify, or Vercel.
2. Open the hosted site in Safari on your iPhone.
3. Tap **Share** then **Add to Home Screen**.

## Important note about storage

Expenses are stored locally in your browser using IndexedDB. That means:

- Your data stays on the device/browser unless you export it
- Clearing browser/site data can remove saved expenses
- Exporting backups regularly is a good idea

## Good next step

If you want, the next step can be publishing this so it works on your phone, or converting it into a native iPhone app later.
