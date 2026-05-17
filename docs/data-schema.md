# Shared Data Schema

Both the web app and iOS app should preserve these fields in backup JSON exports.

```json
{
  "app": "Expenses",
  "exportedAt": "2026-05-17T00:00:00.000Z",
  "expenses": [
    {
      "id": "uuid-or-legacy-id",
      "recordType": "expense",
      "amount": 123.45,
      "merchant": "Vendor",
      "category": "Meal",
      "tripNumber": "12345",
      "date": "2026-05-17",
      "location": "PHX",
      "aircraft": "N123PJ",
      "notes": "",
      "submittedDate": "2026-05-18",
      "reimbursedDate": "",
      "archivedAt": "",
      "photoDataUrl": "",
      "createdAt": "2026-05-17T00:00:00.000Z",
      "updatedAt": "2026-05-17T00:00:00.000Z"
    }
  ],
  "settings": {
    "categoryOptions": ["Lodging", "Meal", "Flight", "Transport", "Supplies", "Miscellaneous"],
    "aircraftOptions": [],
    "tripOptions": []
  }
}
```

## Status Logic

- `Not Submitted`: `submittedDate` is empty.
- `Submitted`: `submittedDate` is set and `reimbursedDate` is empty.
- `Paid`: `reimbursedDate` is set.
- `Archived`: `archivedAt` is set. Archived records should be excluded from the normal dashboard but included in exports when requested.

## Week Grouping

- Not Submitted: group by the week containing the expense date.
- Submitted expenses: group by expected reimbursement Friday.
- Submitted incentives: group by expected incentive payout date.
- Paid: group by paid date.
