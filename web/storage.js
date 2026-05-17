const DB_NAME = "trip-ledger-db";
const STORE_NAME = "expenses";
const DB_VERSION = 1;

const USD_FORMATTER = new Intl.NumberFormat(undefined, {
  style: "currency",
  currency: "USD",
});

const VIEW_CONFIG = {
  "to-submit": {
    key: "to-submit",
    label: "Not Submitted",
    emptyTitle: "Nothing is waiting to submit.",
    emptyBody: "Tap New to log your next receipt or incentive.",
  },
  submitted: {
    key: "submitted",
    label: "Submitted",
    emptyTitle: "Nothing has been submitted yet.",
    emptyBody: "Mark an expense as submitted and it will show up here.",
  },
  reimbursed: {
    key: "reimbursed",
    label: "Paid",
    emptyTitle: "No paid entries yet.",
    emptyBody: "Once an expense is paid back, it will move here.",
  },
};

const DEFAULT_CATEGORY_OPTIONS = ["Lodging", "Meal", "Flight", "Transport", "Supplies", "Miscellaneous"];
const OPTION_STORAGE_KEY = "expenses-option-settings-v1";

export function getViewConfig(view) {
  return VIEW_CONFIG[view] || VIEW_CONFIG["to-submit"];
}

export async function getAllExpenses() {
  const db = await openDatabase();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, "readonly");
    const request = transaction.objectStore(STORE_NAME).getAll();
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
  });
}

export async function getExpense(id) {
  const db = await openDatabase();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, "readonly");
    const request = transaction.objectStore(STORE_NAME).get(id);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
  });
}

export async function saveExpense(expense) {
  const db = await openDatabase();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, "readwrite");
    const request = transaction.objectStore(STORE_NAME).put(expense);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(expense);
  });
}

export async function deleteExpense(id) {
  const db = await openDatabase();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, "readwrite");
    const request = transaction.objectStore(STORE_NAME).delete(id);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve();
  });
}

export async function clearAllExpenses() {
  const db = await openDatabase();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, "readwrite");
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error);
    transaction.oncomplete = () => resolve();
    transaction.objectStore(STORE_NAME).clear();
  });
}

export function filterExpenses(expenses, view) {
  const activeExpenses = expenses.filter((expense) => !expense.archivedAt);

  if (view === "to-submit") {
    return activeExpenses.filter((expense) => !expense.submittedDate);
  }

  if (view === "submitted") {
    return activeExpenses.filter((expense) => Boolean(expense.submittedDate) && !expense.reimbursedDate);
  }

  if (view === "reimbursed") {
    return activeExpenses.filter((expense) => Boolean(expense.reimbursedDate));
  }

  return activeExpenses;
}

export function summarizeExpenses(expenses) {
  return {
    "to-submit": summarizeList(filterExpenses(expenses, "to-submit")),
    submitted: summarizeList(filterExpenses(expenses, "submitted")),
    reimbursed: summarizeList(filterExpenses(expenses, "reimbursed")),
  };
}

function summarizeList(expenses) {
  return {
    count: expenses.length,
    total: expenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0),
  };
}

export function getStatusKey(expense) {
  if (expense.reimbursedDate) {
    return "reimbursed";
  }

  if (expense.submittedDate) {
    return "submitted";
  }

  return "to-submit";
}

export function getStatusLabel(expense) {
  return getViewConfig(getStatusKey(expense)).label;
}

export function getStatusBadgeClass(expense) {
  if (expense.reimbursedDate) {
    return "badge-status-reimbursed";
  }

  if (expense.submittedDate) {
    return "badge-status-submitted";
  }

  return "badge-status-draft";
}

export function getQuickStatusLabel(expense) {
  if (expense.reimbursedDate) {
    return "";
  }

  if (expense.submittedDate) {
    return "Mark paid today";
  }

  return "Submit";
}

export function createId() {
  return window.crypto?.randomUUID?.() || `expense-${Date.now()}`;
}

export function sortExpenses(expenses) {
  return [...expenses].sort((left, right) => {
    const leftDate = `${left.date}-${left.updatedAt || left.createdAt || ""}`;
    const rightDate = `${right.date}-${right.updatedAt || right.createdAt || ""}`;
    return rightDate.localeCompare(leftDate);
  });
}

export function formatDate(value) {
  if (!value) {
    return "Not set";
  }

  const parts = value.split("-");
  if (parts.length !== 3) {
    return value;
  }

  const [year, month, day] = parts.map(Number);
  return new Date(year, month - 1, day).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export function getToday() {
  const today = new Date();
  const offset = today.getTimezoneOffset();
  return new Date(today.getTime() - offset * 60_000).toISOString().slice(0, 10);
}

export function validateDates(expense) {
  if (expense.submittedDate && expense.submittedDate < expense.date) {
    return "The submitted date cannot be earlier than the expense date.";
  }

  if (expense.reimbursedDate && expense.reimbursedDate < expense.date) {
    return "The paid date cannot be earlier than the expense date.";
  }

  if (
    expense.submittedDate &&
    expense.reimbursedDate &&
    expense.reimbursedDate < expense.submittedDate
  ) {
    return "The paid date cannot be earlier than the submitted date.";
  }

  return "";
}

export async function compressImage(file) {
  const dataUrl = await readFileAsDataUrl(file);
  const image = await loadImage(dataUrl);
  const canvas = document.createElement("canvas");
  const maxDimension = 1600;
  const scale = Math.min(1, maxDimension / Math.max(image.width, image.height));
  canvas.width = Math.max(1, Math.round(image.width * scale));
  canvas.height = Math.max(1, Math.round(image.height * scale));

  const context = canvas.getContext("2d");
  if (!context) {
    throw new Error("Could not get a canvas context.");
  }

  context.drawImage(image, 0, 0, canvas.width, canvas.height);
  return canvas.toDataURL("image/jpeg", 0.82);
}

export function buildExportPayload(expenses) {
  const normalizedExpenses = expenses.map((expense) =>
    normalizeImportedExpense(expense, () => expense.id || createId())
  );

  return {
    app: "Expenses",
    schemaVersion: 2,
    source: "web",
    exportedAt: new Date().toISOString(),
    expenses: normalizedExpenses,
    settings: {
      categoryOptions: getCategoryOptions(normalizedExpenses),
      aircraftOptions: getAircraftOptions(normalizedExpenses),
      tripOptions: getTripOptions(normalizedExpenses),
    },
  };
}

export function getSavedOptionSettings() {
  try {
    const parsed = JSON.parse(window.localStorage?.getItem(OPTION_STORAGE_KEY) || "{}");
    return normalizeOptionSettings(parsed);
  } catch {
    return normalizeOptionSettings({});
  }
}

export function saveOptionSettings(settings) {
  window.localStorage?.setItem(OPTION_STORAGE_KEY, JSON.stringify(normalizeOptionSettings(settings)));
}

export function getCategoryOptions(expenses = []) {
  const settings = getSavedOptionSettings();
  const sourceOptions = settings.categoryOptionsCustomized
    ? settings.categoryOptions
    : [...DEFAULT_CATEGORY_OPTIONS, ...expenses.map((expense) => expense.category)];

  return uniqueOptions(sourceOptions);
}

export function getAircraftOptions(expenses = []) {
  const settings = getSavedOptionSettings();
  const sourceOptions = settings.aircraftOptionsCustomized
    ? settings.aircraftOptions
    : [...settings.aircraftOptions, ...expenses.map((expense) => expense.aircraft)];

  return uniqueOptions(sourceOptions);
}

export function getTripOptions(expenses = []) {
  const settings = getSavedOptionSettings();
  const sourceOptions = settings.tripOptionsCustomized
    ? settings.tripOptions
    : [...settings.tripOptions, ...expenses.map((expense) => expense.tripNumber)];

  return uniqueOptions(sourceOptions).slice(0, 10);
}

export function extractImportedExpenseRecords(payload) {
  if (Array.isArray(payload)) {
    return payload;
  }

  if (!payload || typeof payload !== "object") {
    return [];
  }

  for (const key of ["expenses", "records", "entries", "items"]) {
    if (Array.isArray(payload[key])) {
      return payload[key];
    }
  }

  if (payload.data && typeof payload.data === "object") {
    return extractImportedExpenseRecords(payload.data);
  }

  return [];
}

export function normalizeImportedExpense(rawExpense, createIdFn = createId) {
  const source = rawExpense && typeof rawExpense === "object" ? rawExpense : {};
  const now = new Date().toISOString();
  const date =
    normalizeDateValue(readFirst(source, ["date", "expenseDate", "incentiveDate", "transactionDate", "recordDate"])) ||
    normalizeDateValue(readFirst(source, ["submittedDate", "dateSubmitted", "submittedAt", "submissionDate"])) ||
    normalizeDateValue(readFirst(source, ["reimbursedDate", "paidDate", "datePaid", "reimbursedAt", "reimbursementDate"])) ||
    getToday();

  const submittedDate = normalizeDateValue(
    readFirst(source, ["submittedDate", "dateSubmitted", "submittedAt", "submissionDate", "submitted"])
  );
  const reimbursedDate = normalizeDateValue(
    readFirst(source, ["reimbursedDate", "paidDate", "datePaid", "reimbursedAt", "reimbursementDate", "paid"])
  );

  return {
    id: String(readFirst(source, ["id", "uuid", "identifier", "externalId"]) || createIdFn()),
    recordType: normalizeRecordType(readFirst(source, ["recordType", "type", "entryType", "kind"])),
    amount: normalizeAmount(source),
    merchant: cleanText(readFirst(source, ["merchant", "vendor", "displayMerchant", "name", "title", "description"])) || "Imported entry",
    category: cleanText(readFirst(source, ["category", "categoryName"])) || "Miscellaneous",
    tripNumber: cleanText(readFirst(source, ["tripNumber", "trip", "tripName", "tripId", "tripNo", "tripNumberValue"])),
    date,
    location: cleanText(readFirst(source, ["location", "airport", "airportCode"])),
    aircraft: cleanText(readFirst(source, ["aircraft", "tail", "tailNumber", "tailNumberValue"])).toUpperCase(),
    notes: cleanText(readFirst(source, ["notes", "memo", "comment", "comments"])),
    submittedDate,
    reimbursedDate,
    archivedAt: normalizeDateValue(readFirst(source, ["archivedAt", "archivedDate", "archiveDate"])),
    photoDataUrl: cleanText(
      readFirst(source, ["photoDataUrl", "legacyPhotoDataURL", "receiptImageDataUrl", "receiptPhotoDataUrl"])
    ),
    createdAt: normalizeTimestampValue(readFirst(source, ["createdAt", "createdDate"])) || now,
    updatedAt: normalizeTimestampValue(readFirst(source, ["updatedAt", "updatedDate", "modifiedAt"])) || now,
  };
}

export function formatCurrency(value) {
  return USD_FORMATTER.format(Number(value || 0));
}

export function formatCount(count) {
  return `${count} ${count === 1 ? "entry" : "entries"}`;
}

function readFirst(source, keys) {
  for (const key of keys) {
    if (Object.hasOwn(source, key) && source[key] !== null && source[key] !== undefined && source[key] !== "") {
      return source[key];
    }
  }

  return "";
}

function normalizeRecordType(value) {
  return /incentive/i.test(String(value || "")) ? "incentive" : "expense";
}

function normalizeAmount(source) {
  const cents = readFirst(source, ["amountCents", "totalCents"]);
  if (cents !== "") {
    const parsedCents = Number.parseFloat(String(cents).replace(/[^0-9.-]/g, ""));
    if (Number.isFinite(parsedCents)) {
      return Number((parsedCents / 100).toFixed(2));
    }
  }

  const amount = readFirst(source, ["amount", "totalAmount", "total", "finalTotal", "reimbursementAmount"]);
  const parsedAmount = Number.parseFloat(String(amount || "0").replace(/[^0-9.-]/g, ""));
  return Number.isFinite(parsedAmount) ? Number(parsedAmount.toFixed(2)) : 0;
}

function normalizeDateValue(value) {
  if (!value) {
    return "";
  }

  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return dateToIsoDate(value);
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    const date = new Date(value > 10_000_000_000 ? value : value * 1000);
    return Number.isNaN(date.getTime()) ? "" : dateToIsoDate(date);
  }

  const trimmed = String(value).trim();
  if (!trimmed) {
    return "";
  }

  const isoPrefix = trimmed.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (isoPrefix) {
    return isValidIsoParts(isoPrefix[1], isoPrefix[2], isoPrefix[3])
      ? `${isoPrefix[1]}-${isoPrefix[2]}-${isoPrefix[3]}`
      : "";
  }

  const numericMatch = trimmed.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/);
  if (numericMatch) {
    let year = Number(numericMatch[3]);
    if (year < 100) {
      year += year >= 70 ? 1900 : 2000;
    }

    const month = Number(numericMatch[1]);
    const day = Number(numericMatch[2]);
    return isValidIsoParts(year, month, day)
      ? `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`
      : "";
  }

  const parsed = new Date(trimmed);
  return Number.isNaN(parsed.getTime()) ? "" : dateToIsoDate(parsed);
}

function normalizeTimestampValue(value) {
  if (!value) {
    return "";
  }

  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString();
  }

  if (typeof value === "number" && Number.isFinite(value)) {
    const date = new Date(value > 10_000_000_000 ? value : value * 1000);
    return Number.isNaN(date.getTime()) ? "" : date.toISOString();
  }

  const trimmed = String(value).trim();
  if (!trimmed) {
    return "";
  }

  const parsed = new Date(trimmed);
  return Number.isNaN(parsed.getTime()) ? "" : parsed.toISOString();
}

function isValidIsoParts(yearValue, monthValue, dayValue) {
  const year = Number(yearValue);
  const month = Number(monthValue);
  const day = Number(dayValue);
  const candidate = new Date(year, month - 1, day);

  return (
    Number.isInteger(year) &&
    Number.isInteger(month) &&
    Number.isInteger(day) &&
    candidate.getFullYear() === year &&
    candidate.getMonth() === month - 1 &&
    candidate.getDate() === day
  );
}

function dateToIsoDate(date) {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("-");
}

function cleanText(value) {
  return String(value || "").trim();
}

function uniqueOptions(options) {
  return options.reduce((result, option) => {
    const cleaned = cleanText(option);
    if (!cleaned || result.some((candidate) => candidate.toLowerCase() === cleaned.toLowerCase())) {
      return result;
    }

    result.push(cleaned);
    return result;
  }, []);
}

function normalizeOptionSettings(settings) {
  const hasCategoryOptions = Array.isArray(settings?.categoryOptions) || Array.isArray(settings?.categories);
  const hasAircraftOptions = Array.isArray(settings?.aircraftOptions) || Array.isArray(settings?.aircraft);
  const hasTripOptions = Array.isArray(settings?.tripOptions) || Array.isArray(settings?.trips);
  const hasCategoryCustomizationFlag = typeof settings?.categoryOptionsCustomized === "boolean";
  const hasAircraftCustomizationFlag = typeof settings?.aircraftOptionsCustomized === "boolean";
  const hasTripCustomizationFlag = typeof settings?.tripOptionsCustomized === "boolean";

  return {
    categoryOptions: uniqueOptions(settings?.categoryOptions || settings?.categories || []),
    aircraftOptions: uniqueOptions(settings?.aircraftOptions || settings?.aircraft || []),
    tripOptions: uniqueOptions(settings?.tripOptions || settings?.trips || []).slice(0, 10),
    categoryOptionsCustomized: hasCategoryCustomizationFlag
      ? settings.categoryOptionsCustomized
      : hasCategoryOptions,
    aircraftOptionsCustomized: hasAircraftCustomizationFlag
      ? settings.aircraftOptionsCustomized
      : hasAircraftOptions,
    tripOptionsCustomized: hasTripCustomizationFlag
      ? settings.tripOptionsCustomized
      : hasTripOptions,
  };
}

function openDatabase() {
  return new Promise((resolve, reject) => {
    const request = window.indexedDB.open(DB_NAME, DB_VERSION);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(STORE_NAME)) {
        database.createObjectStore(STORE_NAME, { keyPath: "id" });
      }
    };
  });
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error);
    reader.onload = () => resolve(reader.result);
    reader.readAsDataURL(file);
  });
}

function loadImage(dataUrl) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onerror = () => reject(new Error("Could not load image."));
    image.onload = () => resolve(image);
    image.src = dataUrl;
  });
}
