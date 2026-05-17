import {
  buildExportPayload,
  clearAllExpenses,
  createId,
  deleteExpense,
  extractImportedExpenseRecords,
  filterExpenses,
  formatCount,
  formatCurrency,
  formatDate,
  getAllExpenses,
  getAircraftOptions,
  getCategoryOptions,
  getExpense,
  getQuickStatusLabel,
  getSavedOptionSettings,
  getStatusBadgeClass,
  getStatusKey,
  getStatusLabel,
  getToday,
  getTripOptions,
  getViewConfig,
  normalizeImportedExpense,
  saveOptionSettings,
  saveExpense,
  sortExpenses,
  summarizeExpenses,
  validateDates,
} from "./storage.js";

const EMPTY_REPORT_VALUE = "__empty__";
const DAILY_BACKUP_STORAGE_KEY = "expenses.lastDailyBackupPrompt";
const REPORT_TYPE_OPTIONS = [
  { value: "expense", label: "Expenses" },
  { value: "incentive", label: "Incentives" },
];
const REPORT_STATUS_OPTIONS = [
  { value: "to-submit", label: "Not Submitted" },
  { value: "submitted", label: "Submitted" },
  { value: "reimbursed", label: "Paid" },
  { value: "archived", label: "Archived" },
];
const OPTION_MANAGER_CONFIGS = {
  category: {
    title: "Categories",
    key: "categoryOptions",
    customKey: "categoryOptionsCustomized",
    placeholder: "Add category",
    hint: "These are only menu choices for future entries. Saved entries keep their existing category.",
    getValues: () => getCategoryOptions(state.expenses),
    normalize: (value) => value.trim(),
  },
  aircraft: {
    title: "Aircraft",
    key: "aircraftOptions",
    customKey: "aircraftOptionsCustomized",
    placeholder: "Add tail number",
    hint: "These feed the Aircraft dropdown without changing saved entries.",
    getValues: () => getAircraftOptions(state.expenses),
    normalize: (value) => value.trim().toUpperCase(),
  },
  trip: {
    title: "Trips",
    key: "tripOptions",
    customKey: "tripOptionsCustomized",
    placeholder: "Add trip",
    hint: "Only the most recent 10 trip names are shown when creating an entry.",
    getValues: () => getTripOptions(state.expenses),
    normalize: (value) => value.trim().toUpperCase(),
    max: 10,
    addToTop: true,
  },
};

const state = {
  currentView: getInitialView(),
  currentRecordType: getInitialRecordType(),
  currentGrouping: getInitialGrouping(),
  expenses: [],
  importMode: "any",
  pendingReportFormat: "csv",
  optionManagerKind: "",
};

const elements = {
  menuButton: document.querySelector("#menu-button"),
  menuPopover: document.querySelector("#menu-popover"),
  menuActions: document.querySelectorAll("[data-menu-action]"),
  recordTypeButtons: document.querySelectorAll("[data-record-type]"),
  summaryButtons: document.querySelectorAll(".status-tile"),
  groupingButtons: document.querySelectorAll("[data-grouping]"),
  summaryToSubmit: document.querySelector("#summary-to-submit"),
  summaryToSubmitCount: document.querySelector("#summary-to-submit-count"),
  summaryAwaiting: document.querySelector("#summary-awaiting"),
  summaryAwaitingCount: document.querySelector("#summary-awaiting-count"),
  summaryReimbursed: document.querySelector("#summary-reimbursed"),
  summaryReimbursedCount: document.querySelector("#summary-reimbursed-count"),
  newEntryLink: document.querySelector("#new-entry-link"),
  listHeading: document.querySelector("#list-heading"),
  listCaption: document.querySelector("#list-caption"),
  expenseList: document.querySelector("#expense-list"),
  expenseCardTemplate: document.querySelector("#expense-card-template"),
  importInput: document.querySelector("#import-input"),
  storageStatus: document.querySelector("#storage-status"),
  reportModal: document.querySelector("#report-modal"),
  reportModalScrim: document.querySelector("#report-modal-scrim"),
  reportOptionsForm: document.querySelector("#report-options-form"),
  reportCloseButton: document.querySelector("#report-close-button"),
  reportCancelButton: document.querySelector("#report-cancel-button"),
  reportExportButton: document.querySelector("#report-export-button"),
  reportPreview: document.querySelector("#report-preview"),
  reportStartDate: document.querySelector("#report-start-date"),
  reportEndDate: document.querySelector("#report-end-date"),
  reportTypeOptions: document.querySelector("#report-type-options"),
  reportStatusOptions: document.querySelector("#report-status-options"),
  reportCategoryOptions: document.querySelector("#report-category-options"),
  reportAirportOptions: document.querySelector("#report-airport-options"),
  reportAircraftOptions: document.querySelector("#report-aircraft-options"),
  reportTripOptions: document.querySelector("#report-trip-options"),
  optionModal: document.querySelector("#option-modal"),
  optionModalScrim: document.querySelector("#option-modal-scrim"),
  optionModalTitle: document.querySelector("#option-modal-title"),
  optionModalCopy: document.querySelector("#option-modal-copy"),
  optionCloseButton: document.querySelector("#option-close-button"),
  optionList: document.querySelector("#option-list"),
  optionAddForm: document.querySelector("#option-add-form"),
  optionNewValue: document.querySelector("#option-new-value"),
  backupReminderModal: document.querySelector("#backup-reminder-modal"),
  backupReminderScrim: document.querySelector("#backup-reminder-scrim"),
  backupReminderSkipButton: document.querySelector("#backup-reminder-skip-button"),
  backupReminderDownloadButton: document.querySelector("#backup-reminder-download-button"),
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", init);
} else {
  init();
}

async function init() {
  bindEvents();
  await refreshExpenses();
  updateStorageStatus();
  maybeShowDailyBackupPrompt();
  registerServiceWorker();
}

function bindEvents() {
  elements.recordTypeButtons.forEach((button) => {
    button.addEventListener("click", () => {
      setCurrentRecordType(button.dataset.recordType);
    });
  });

  elements.summaryButtons.forEach((button) => {
    button.addEventListener("click", () => {
      setCurrentView(button.dataset.view);
    });
  });

  elements.groupingButtons.forEach((button) => {
    button.addEventListener("click", () => {
      setCurrentGrouping(button.dataset.grouping);
    });
  });

  elements.menuButton.addEventListener("click", toggleMenu);
  document.addEventListener("click", closeMenuWhenOutside);
  elements.menuActions.forEach((button) => {
    button.addEventListener("click", handleMenuAction);
  });

  elements.expenseList.addEventListener("click", handleExpenseAction);
  elements.expenseList.addEventListener("change", handleInlineDateUpdate);
  elements.importInput.addEventListener("change", importExpenses);
  elements.reportOptionsForm.addEventListener("submit", handleReportOptionsSubmit);
  elements.reportOptionsForm.addEventListener("change", updateReportPreview);
  elements.reportOptionsForm.addEventListener("input", updateReportPreview);
  elements.reportModalScrim.addEventListener("click", closeReportOptions);
  elements.reportCloseButton.addEventListener("click", closeReportOptions);
  elements.reportCancelButton.addEventListener("click", closeReportOptions);
  elements.optionModalScrim.addEventListener("click", closeOptionManager);
  elements.optionCloseButton.addEventListener("click", closeOptionManager);
  elements.optionAddForm.addEventListener("submit", handleOptionAddSubmit);
  elements.optionList.addEventListener("click", handleOptionListClick);
  elements.backupReminderScrim.addEventListener("click", dismissDailyBackupPrompt);
  elements.backupReminderSkipButton.addEventListener("click", dismissDailyBackupPrompt);
  elements.backupReminderDownloadButton.addEventListener("click", downloadDailyBackup);
  document.addEventListener("keydown", handleDocumentKeydown);
}

async function refreshExpenses(options = {}) {
  try {
    state.expenses = sortExpenses(await getAllExpenses());
    renderSummary();
    renderListPanel();

    if (options.submittedOpenState) {
      restoreSubmittedOpenState(options.submittedOpenState, options.focusExpenseId);
    }
  } catch (error) {
    console.error(error);
    window.alert("Expenses could not load your saved entries.");
  }
}

function renderSummary() {
  const scopedExpenses = getScopedExpenses(state.expenses, state.currentRecordType);
  const summary = summarizeExpenses(scopedExpenses);
  updateSummaryCard(elements.summaryToSubmit, elements.summaryToSubmitCount, summary["to-submit"]);
  updateSummaryCard(elements.summaryAwaiting, elements.summaryAwaitingCount, summary.submitted);
  updateSummaryCard(elements.summaryReimbursed, elements.summaryReimbursedCount, summary.reimbursed);

  elements.recordTypeButtons.forEach((button) => {
    const isActive = button.dataset.recordType === state.currentRecordType;
    button.classList.toggle("active", isActive);
    button.setAttribute("aria-pressed", isActive ? "true" : "false");
  });

  elements.summaryButtons.forEach((button) => {
    const isActive = button.dataset.view === state.currentView;
    button.classList.toggle("active", isActive);
    button.setAttribute("aria-pressed", isActive ? "true" : "false");
  });

  elements.groupingButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.grouping === state.currentGrouping);
  });

  if (elements.newEntryLink) {
    elements.newEntryLink.textContent = "+ New";
    elements.newEntryLink.href = `expense.html?type=${encodeURIComponent(state.currentRecordType)}&view=${encodeURIComponent(state.currentView)}`;
  }
}

function updateSummaryCard(valueElement, countElement, summary) {
  valueElement.textContent = formatCurrency(summary.total);
  countElement.textContent = formatCount(summary.count);
}

function renderListPanel() {
  const currentView = getViewConfig(state.currentView);
  const scopedExpenses = getScopedExpenses(state.expenses, state.currentRecordType);
  const filteredExpenses = filterExpenses(scopedExpenses, state.currentView);
  const total = filteredExpenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0);

  elements.listHeading.textContent = getCurrentViewHeading(currentView);
  elements.listCaption.textContent = `${formatCount(filteredExpenses.length)} • ${formatCurrency(total)}`;
  renderLedgerGroups(filteredExpenses, currentView);
}

function renderExpenses(expenses, currentView) {
  elements.expenseList.innerHTML = "";

  if (!expenses.length) {
    renderEmptyState(currentView);
    return;
  }

  expenses.forEach((expense, index) => {
    const card = buildExpenseCard(expense, index);
    elements.expenseList.appendChild(card);
  });
}

function renderEmptyState(currentView) {
  const emptyState = document.createElement("div");
  emptyState.className = "empty-state";
  emptyState.innerHTML = `
    <p><strong>${currentView.emptyTitle}</strong></p>
    <p>${currentView.emptyBody}</p>
  `;
  elements.expenseList.appendChild(emptyState);
}

function getScopedExpenses(expenses, recordType = state.currentRecordType) {
  return expenses.filter((expense) => getRecordType(expense) === recordType);
}

function getRecordType(expense) {
  return expense.recordType === "incentive" ? "incentive" : "expense";
}

function getCurrentViewHeading(currentView) {
  if (state.currentRecordType !== "incentive") {
    return currentView.label;
  }

  if (state.currentView === "submitted") {
    return "Submitted";
  }

  if (state.currentView === "reimbursed") {
    return "Paid";
  }

  return "Not Submitted";
}

function sortListExpenses(expenses) {
  return sortExpenses(expenses);
}

function renderLedgerGroups(expenses, currentView) {
  elements.expenseList.innerHTML = "";

  if (!expenses.length) {
    renderEmptyState(currentView);
    return;
  }

  buildLedgerGroups(expenses).forEach((group) => {
    elements.expenseList.appendChild(buildLedgerGroup(group));
  });
}

function buildLedgerGroups(expenses) {
  const groups = new Map();

  expenses.forEach((expense) => {
    const descriptor = getGroupDescriptor(expense);
    if (!groups.has(descriptor.key)) {
      groups.set(descriptor.key, {
        ...descriptor,
        expenses: [],
      });
    }

    groups.get(descriptor.key).expenses.push(expense);
  });

  return Array.from(groups.values())
    .map((group) => ({
      ...group,
      expenses: sortReimbursementExpenses(group.expenses),
      total: group.expenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0),
    }))
    .sort((left, right) => {
      if (left.sortKey !== right.sortKey) {
        return right.sortKey.localeCompare(left.sortKey);
      }

      return left.title.localeCompare(right.title, undefined, {
        numeric: true,
        sensitivity: "base",
      });
    });
}

function buildLedgerGroup(group) {
  const section = document.createElement("section");
  const summary = document.createElement("div");
  const summaryMain = document.createElement("div");
  const titleBlock = document.createElement("div");
  const summaryLabel = document.createElement("span");
  const count = document.createElement("span");
  const summaryRight = document.createElement("div");
  const summaryTotal = document.createElement("span");
  const actionButton = buildGroupActionButton(group);
  const chevron = document.createElement("span");
  const content = document.createElement("div");
  const list = document.createElement("div");

  section.className = "expense-group";
  section.dataset.groupKey = group.key;
  summary.className = "expense-group-summary";
  summary.setAttribute("role", "button");
  summary.setAttribute("aria-expanded", "false");
  summary.tabIndex = 0;
  summaryMain.className = "expense-group-summary-main";
  titleBlock.className = "expense-group-title-block";
  summaryLabel.className = "expense-group-summary-label";
  summaryLabel.textContent = group.title;
  count.className = "expense-group-count";
  count.textContent = formatCount(group.expenses.length);
  summaryRight.className = "expense-group-summary-right";
  summaryTotal.className = "expense-group-summary-total";
  summaryTotal.textContent = formatCurrency(group.total);
  chevron.className = "accordion-chevron";
  chevron.setAttribute("aria-hidden", "true");
  chevron.textContent = "›";
  content.className = "expense-group-content";
  list.className = "expense-group-list";

  titleBlock.append(summaryLabel, count);
  summaryMain.append(titleBlock);
  summaryRight.append(summaryTotal);
  if (actionButton) {
    summaryRight.append(actionButton);
  }
  summaryRight.append(chevron);
  summary.append(summaryMain, summaryRight);
  content.hidden = true;
  bindLedgerGroupToggle(summary, section);

  group.expenses.forEach((expense, index) => {
    list.appendChild(buildSubmittedExpenseItem(expense, index));
  });

  content.append(list);
  section.append(summary, content);
  return section;
}

function buildGroupActionButton(group) {
  if (state.currentView === "to-submit") {
    return buildActionButton("submit-group", "Submit", "inline-button group-status-button submit-button");
  }

  if (state.currentView === "submitted") {
    return buildActionButton("reimburse-group", "Paid", "inline-button group-status-button paid-button");
  }

  if (state.currentView === "reimbursed") {
    return buildActionButton("archive-group", "Archive", "inline-button group-status-button archive-button");
  }

  return null;
}

function bindLedgerGroupToggle(summary, section) {
  summary.addEventListener("click", (event) => {
    if (event.target.closest("[data-action]")) {
      return;
    }

    toggleLedgerGroup(section);
  });

  summary.addEventListener("keydown", (event) => {
    if (event.target !== summary) {
      return;
    }

    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }

    event.preventDefault();
    toggleLedgerGroup(section);
  });
}

function toggleLedgerGroup(section) {
  setLedgerGroupOpen(section, !isLedgerGroupOpen(section));
}

function setLedgerGroupOpen(section, isOpen) {
  if (!section) {
    return;
  }

  const summary = section.querySelector(".expense-group-summary");
  const content = section.querySelector(".expense-group-content");

  section.classList.toggle("is-open", isOpen);
  summary?.setAttribute("aria-expanded", isOpen ? "true" : "false");
  if (content) {
    content.hidden = !isOpen;
  }

  if (!isOpen) {
    section.querySelectorAll(".submitted-expense-item[open]").forEach((item) => {
      item.removeAttribute("open");
    });
  }
}

function isLedgerGroupOpen(section) {
  return Boolean(section?.classList.contains("is-open"));
}

function getGroupDescriptor(expense) {
  switch (state.currentGrouping) {
    case "trip": {
      const value = String(expense.tripNumber || "").trim();
      return descriptor(value || "none", value ? `Trip ${value}` : "No Trip", sortDateForExpense(expense));
    }
    case "airport": {
      const value = String(expense.location || "").trim();
      return descriptor(value || "none", value || "No Airport", sortDateForExpense(expense));
    }
    case "aircraft": {
      const value = String(expense.aircraft || "").trim();
      return descriptor(value || "none", value || "No Aircraft", sortDateForExpense(expense));
    }
    case "vendor": {
      const value = String(expense.merchant || "Untitled entry").trim();
      return descriptor(value, value, sortDateForExpense(expense));
    }
    case "category": {
      const value = String(expense.category || "Miscellaneous").trim();
      return descriptor(value, value, sortDateForExpense(expense));
    }
    case "week":
    default:
      return getWeekGroupDescriptor(expense);
  }
}

function getWeekGroupDescriptor(expense) {
  if (state.currentView === "submitted") {
    const date = getExpectedPayoutDate(expense, state.currentRecordType);
    const title = state.currentRecordType === "incentive" ? `Payout ${formatDate(date)}` : formatShortFridayDate(date);
    return descriptor(date, title, date);
  }

  if (state.currentView === "reimbursed") {
    const date = expense.reimbursedDate || expense.submittedDate || expense.date;
    return descriptor(date, `Paid ${formatDate(date)}`, date);
  }

  const monday = getMondayForWeekContaining(expense.date);
  return descriptor(monday, `Week ${formatDate(monday)}`, monday);
}

function descriptor(key, title, sortKey) {
  return {
    key: `${state.currentGrouping}-${String(key).toLowerCase()}`,
    title,
    sortKey: sortKey || "",
  };
}

function sortDateForExpense(expense) {
  if (state.currentView === "submitted") {
    return expense.submittedDate || expense.date || "";
  }

  if (state.currentView === "reimbursed") {
    return expense.reimbursedDate || expense.submittedDate || expense.date || "";
  }

  return expense.date || "";
}

function renderSubmittedExpenseGroups(expenses, currentView, reimbursementSchedule) {
  elements.expenseList.innerHTML = "";

  if (!expenses.length) {
    renderEmptyState(currentView);
    return;
  }

  let cardIndex = 0;
  reimbursementSchedule.groups.forEach((group) => {
    const section = buildSubmittedExpenseGroup(group, cardIndex);
    cardIndex += group.expenses.length;
    elements.expenseList.appendChild(section);
  });
}

function buildSubmittedExpenseGroup(group, startIndex) {
  const section = document.createElement("details");
  const summary = document.createElement("summary");
  const summaryMain = document.createElement("div");
  const summaryLabel = document.createElement("span");
  const summaryRight = document.createElement("div");
  const summaryTotal = document.createElement("span");
  const chevron = document.createElement("span");
  const content = document.createElement("div");
  const note = document.createElement("p");
  const groupActions = document.createElement("div");
  const list = document.createElement("div");
  const total = group.expenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0);
  const tripGroups = buildTripExpenseGroups(group.expenses);

  section.className = "expense-group";
  section.dataset.groupKey = group.groupKey || group.fridayDate;
  summary.className = "expense-group-summary";
  summaryMain.className = "expense-group-summary-main";
  summaryLabel.className = "expense-group-summary-label";
  summaryLabel.textContent = group.displayLabel;
  summaryRight.className = "expense-group-summary-right";
  summaryTotal.className = "expense-group-summary-total";
  summaryTotal.textContent = formatCurrency(total);
  chevron.className = "accordion-chevron";
  chevron.setAttribute("aria-hidden", "true");
  chevron.textContent = "›";
  content.className = "expense-group-content";
  note.className = "expense-group-note";
  note.textContent = `${formatCount(group.expenses.length)} • ${group.noteText}`;
  groupActions.className = "expense-group-actions";
  list.className = "expense-group-list";

  summaryMain.append(summaryLabel);
  summaryRight.append(summaryTotal, chevron);
  summary.append(summaryMain, summaryRight);
  content.append(note, groupActions, list);
  section.append(summary, content);
  section.addEventListener("toggle", () => {
    if (section.open) {
      return;
    }

    section.querySelectorAll(".submitted-expense-item[open]").forEach((item) => {
      item.removeAttribute("open");
    });
  });

  if (!group.expenses.length) {
    const emptyState = document.createElement("p");
    emptyState.className = "expense-group-empty";
    emptyState.textContent = group.emptyText;
    list.appendChild(emptyState);
    return section;
  }

  groupActions.append(
    buildActionButton(
      "reimburse-group",
      state.currentRecordType === "incentive" ? "Mark payout paid today" : "Mark week paid today",
      "inline-button expense-group-button"
    )
  );

  tripGroups.forEach((tripGroup) => {
    list.appendChild(buildTripExpenseGroup(tripGroup, startIndex));
    startIndex += tripGroup.expenses.length;
  });

  return section;
}

function buildTripExpenseGroup(tripGroup, startIndex) {
  const wrapper = document.createElement("section");
  const header = document.createElement("div");
  const title = document.createElement("h3");
  const caption = document.createElement("p");
  const list = document.createElement("div");
  const total = tripGroup.expenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0);

  wrapper.className = "trip-group";
  header.className = "trip-group-header";
  title.className = "trip-group-title";
  title.textContent = tripGroup.label;
  caption.className = "trip-group-caption";
  caption.textContent = `${formatCount(tripGroup.expenses.length)} • ${formatCurrency(total)}`;
  list.className = "trip-group-list";

  header.append(title, caption);
  wrapper.append(header, list);

  tripGroup.expenses.forEach((expense, index) => {
    list.appendChild(buildSubmittedExpenseItem(expense, startIndex + index));
  });

  return wrapper;
}

function buildSubmittedExpenseItem(expense, index) {
  const item = document.createElement("details");
  const summary = document.createElement("summary");
  const line = document.createElement("div");
  const date = document.createElement("span");
  const title = document.createElement("span");
  const summaryRight = document.createElement("div");
  const amount = document.createElement("span");
  const chevron = document.createElement("span");
  const body = document.createElement("div");
  const meta = document.createElement("p");
  const dateGrid = document.createElement("div");
  const badges = document.createElement("div");
  const location = buildExpenseTextLine("expense-location", expense.location);
  const notes = buildExpenseTextLine("expense-notes", expense.notes);
  const photo = buildExpensePhoto(expense);
  const actions = document.createElement("div");

  item.className = "submitted-expense-item";
  item.dataset.expenseId = expense.id;
  item.style.animationDelay = `${Math.min(index, 6) * 0.04 + 0.05}s`;

  summary.className = "submitted-expense-summary";
  line.className = "submitted-expense-line";
  date.className = "submitted-expense-date";
  date.textContent = formatShortDate(expense.date);
  title.className = "submitted-expense-title";
  title.textContent = expense.merchant;
  summaryRight.className = "submitted-expense-summary-right";
  amount.className = "submitted-expense-summary-amount";
  amount.textContent = formatCurrency(expense.amount || 0);
  chevron.className = "accordion-chevron";
  chevron.setAttribute("aria-hidden", "true");
  chevron.textContent = "›";
  body.className = "submitted-expense-body";
  meta.className = "submitted-expense-meta";
  meta.textContent = buildExpenseMetaText(expense);
  dateGrid.className = "submitted-expense-date-grid";
  dateGrid.append(
    buildInlineDateField("Expense date", "date", expense.date),
    buildInlineDateField("Submitted", "submittedDate", expense.submittedDate),
    buildReadOnlyDateField(
      "Paid",
      expense.reimbursedDate ? formatDate(expense.reimbursedDate) : "Not yet"
    )
  );
  badges.className = "expense-badges";
  badges.append(...buildExpenseBadgeNodes(expense));
  actions.className = "expense-actions";
  actions.append(...buildExpenseActionButtons(expense));

  line.append(date, title);
  summaryRight.append(amount, chevron);
  summary.append(line, summaryRight);
  body.append(meta, dateGrid, badges);

  if (location) {
    body.append(location);
  }

  if (notes) {
    body.append(notes);
  }

  if (photo) {
    body.append(photo);
  }

  body.append(actions);
  item.append(summary, body);
  return item;
}

function buildAwaitingPayoutSchedule(expenses, recordType = state.currentRecordType) {
  const today = getToday();
  const groupsByPayoutDate = new Map();

  expenses.forEach((expense) => {
    const payoutDate =
      recordType === "incentive"
        ? getExpectedIncentivePayoutDate(expense.submittedDate)
        : getExpectedReimbursementFriday(expense.submittedDate);
    const existingGroup = groupsByPayoutDate.get(payoutDate);

    if (existingGroup) {
      existingGroup.expenses.push(expense);
      return;
    }

    groupsByPayoutDate.set(payoutDate, {
      payoutDate,
      expenses: [expense],
    });
  });

  return {
    groups: Array.from(groupsByPayoutDate.values())
      .sort((left, right) => left.payoutDate.localeCompare(right.payoutDate))
      .map((group) => ({
        fridayDate: group.payoutDate,
        groupKey: group.payoutDate,
        displayLabel:
          recordType === "incentive"
            ? formatDate(group.payoutDate)
            : formatShortFridayDate(group.payoutDate),
        expenses: sortReimbursementExpenses(group.expenses),
        noteText: buildReimbursementGroupNote(group.payoutDate, today, recordType),
        emptyText:
          recordType === "incentive"
            ? `No incentives are still waiting for ${formatDate(group.payoutDate)}.`
            : `No expenses are still waiting for ${formatFridayDate(group.payoutDate)}.`,
      })),
  };
}

function sortReimbursementExpenses(expenses) {
  return [...expenses].sort(compareSubmittedExpenseRecency);
}

function normalizeTripSortValue(value) {
  return String(value || "").trim();
}

function compareRecentExpense(left, right) {
  const leftKey = `${left.date || ""}-${left.updatedAt || left.createdAt || ""}`;
  const rightKey = `${right.date || ""}-${right.updatedAt || right.createdAt || ""}`;
  return rightKey.localeCompare(leftKey);
}

function compareSubmittedExpenseRecency(left, right) {
  const leftKey = `${left.submittedDate || ""}-${left.date || ""}-${left.updatedAt || left.createdAt || ""}`;
  const rightKey = `${right.submittedDate || ""}-${right.date || ""}-${right.updatedAt || right.createdAt || ""}`;
  return rightKey.localeCompare(leftKey);
}

function buildTripExpenseGroups(expenses) {
  const sortedByDate = [...expenses].sort(compareExpenseDayAscending);
  const groups = new Map();

  sortedByDate.forEach((expense) => {
    const tripNumber = normalizeTripSortValue(expense.tripNumber);
    const tripKey = tripNumber || "__no_trip__";

    if (!groups.has(tripKey)) {
      groups.set(tripKey, {
        key: tripKey,
        label: tripNumber ? `Trip # ${tripNumber}` : "No Trip #",
        tripNumber,
        firstDate: expense.date,
        expenses: [],
      });
    }

    const group = groups.get(tripKey);
    group.expenses.push(expense);
    if (expense.date < group.firstDate) {
      group.firstDate = expense.date;
    }
  });

  return Array.from(groups.values()).sort((left, right) => {
    if (Boolean(left.tripNumber) !== Boolean(right.tripNumber)) {
      return left.tripNumber ? -1 : 1;
    }

    const firstDateCompare = left.firstDate.localeCompare(right.firstDate);
    if (firstDateCompare !== 0) {
      return firstDateCompare;
    }

    return left.label.localeCompare(right.label, undefined, {
      numeric: true,
      sensitivity: "base",
    });
  });
}

function compareExpenseDayAscending(left, right) {
  const leftKey = `${left.date || ""}-${left.merchant || ""}-${left.updatedAt || left.createdAt || ""}`;
  const rightKey = `${right.date || ""}-${right.merchant || ""}-${right.updatedAt || right.createdAt || ""}`;
  return leftKey.localeCompare(rightKey);
}

function getExpectedReimbursementFriday(submittedDate) {
  const upcomingFriday = getUpcomingFriday(submittedDate);
  const cutoffMonday = getMondayForWeekContaining(upcomingFriday);

  if (submittedDate <= cutoffMonday) {
    return upcomingFriday;
  }

  return addDaysToIsoDate(upcomingFriday, 7);
}

function getExpectedIncentivePayoutDate(submittedDate) {
  const submitted = parseIsoDate(submittedDate);
  if (!submitted) {
    return submittedDate;
  }

  const payoutDate = new Date(submitted.getFullYear(), submitted.getMonth(), 15);
  if (submitted.getDate() <= 15) {
    return toIsoDate(payoutDate);
  }

  payoutDate.setMonth(payoutDate.getMonth() + 1, 15);
  return toIsoDate(payoutDate);
}

function getExpectedPayoutDate(expense, recordType = state.currentRecordType) {
  return recordType === "incentive"
    ? getExpectedIncentivePayoutDate(expense.submittedDate)
    : getExpectedReimbursementFriday(expense.submittedDate);
}

function getUpcomingFriday(fromDate = getToday()) {
  const date = parseIsoDate(fromDate);
  if (!date) {
    return fromDate;
  }

  const daysUntilFriday = (5 - date.getDay() + 7) % 7;
  date.setDate(date.getDate() + daysUntilFriday);
  return toIsoDate(date);
}

function buildReimbursementGroupNote(payoutDate, today = getToday(), recordType = state.currentRecordType) {
  const label = recordType === "incentive" ? formatDate(payoutDate) : formatFridayDate(payoutDate);
  const noun = recordType === "incentive" ? "incentive payout" : "payment";

  if (payoutDate < today) {
    return `Expected on ${label} and still awaiting ${noun}.`;
  }

  if (payoutDate === today) {
    return recordType === "incentive" ? "Expected incentive payout today." : "Expected payment today.";
  }

  return `Expected ${noun} on ${label}.`;
}

function getMondayForWeekContaining(value) {
  const date = parseIsoDate(value);
  if (!date) {
    return value;
  }

  const daysSinceMonday = (date.getDay() + 6) % 7;
  date.setDate(date.getDate() - daysSinceMonday);
  return toIsoDate(date);
}

function addDaysToIsoDate(value, days) {
  const date = parseIsoDate(value);
  if (!date) {
    return value;
  }

  date.setDate(date.getDate() + days);
  return toIsoDate(date);
}

function parseIsoDate(value) {
  const [year, month, day] = String(value || "")
    .split("-")
    .map(Number);

  if (!year || !month || !day) {
    return null;
  }

  return new Date(year, month - 1, day);
}

function toIsoDate(date) {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("-");
}

function formatFridayDate(value) {
  return `Fri ${formatDate(value)}`;
}

function formatShortFridayDate(value) {
  return `Fri ${formatShortDate(value)}`;
}

function formatPayoutGroupLabel(value, recordType = state.currentRecordType) {
  return recordType === "incentive" ? formatDate(value) : formatFridayDate(value);
}

function formatShortDate(value) {
  const date = parseIsoDate(value);
  if (!date) {
    return value;
  }

  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

function buildExpenseCard(expense, index) {
  const fragment = elements.expenseCardTemplate.content.cloneNode(true);
  const card = fragment.querySelector(".expense-card");
  const merchant = fragment.querySelector(".expense-merchant");
  const meta = fragment.querySelector(".expense-meta");
  const amount = fragment.querySelector(".expense-amount");
  const badges = fragment.querySelector(".expense-badges");
  const location = fragment.querySelector(".expense-location");
  const notes = fragment.querySelector(".expense-notes");
  const photo = fragment.querySelector(".expense-photo");
  const timeline = fragment.querySelector(".expense-timeline");
  const actions = fragment.querySelector(".expense-actions");

  card.dataset.expenseId = expense.id;
  card.style.animationDelay = `${Math.min(index, 6) * 0.04 + 0.05}s`;

  merchant.textContent = expense.merchant;
  meta.textContent = buildExpenseMetaText(expense);
  amount.textContent = formatCurrency(expense.amount || 0);

  badges.replaceChildren(...buildExpenseBadgeNodes(expense));

  location.hidden = !expense.location;
  location.textContent = expense.location || "";

  notes.hidden = !expense.notes;
  notes.textContent = expense.notes || "";

  photo.hidden = !expense.photoDataUrl;
  if (expense.photoDataUrl) {
    photo.src = expense.photoDataUrl;
  } else {
    photo.removeAttribute("src");
  }

  timeline.replaceChildren(...buildExpenseTimelineNodes(expense));
  actions.replaceChildren(...buildExpenseActionButtons(expense));

  return fragment;
}

function buildExpenseBadgeNodes(expense) {
  const statusBadge = document.createElement("span");
  const categoryBadge = document.createElement("span");
  const tripBadge = document.createElement("span");
  const badges = [];

  statusBadge.className = `badge ${getStatusBadgeClass(expense)}`;
  statusBadge.textContent = getStatusLabel(expense);
  categoryBadge.className = "badge badge-category";
  categoryBadge.textContent = expense.category;
  badges.push(statusBadge, categoryBadge);

  if (expense.tripNumber) {
    tripBadge.className = "badge badge-trip";
    tripBadge.textContent = `Trip # ${expense.tripNumber}`;
    badges.push(tripBadge);
  }

  return badges;
}

function buildExpenseTimelineNodes(expense) {
  return [
    buildTimelineCell("Expense", formatDate(expense.date)),
    buildTimelineCell("Submitted", expense.submittedDate ? formatDate(expense.submittedDate) : "Not yet"),
    buildTimelineCell("Paid", expense.reimbursedDate ? formatDate(expense.reimbursedDate) : "Not yet"),
  ];
}

function buildExpenseActionButtons(expense) {
  const buttons = [];
  const quickStatusLabel = getQuickStatusLabel(expense);

  if (quickStatusLabel) {
    buttons.push(buildActionButton("quick-status", quickStatusLabel));
  }

  buttons.push(buildActionButton("edit", "Edit"));
  buttons.push(buildActionButton("delete", "Delete", "inline-button danger-inline"));
  return buttons;
}

function buildActionButton(action, label, className = "inline-button") {
  const button = document.createElement("button");
  button.type = "button";
  button.dataset.action = action;
  button.className = className;
  button.textContent = label;
  return button;
}

function buildExpenseTextLine(className, value) {
  if (!value) {
    return null;
  }

  const element = document.createElement("p");
  element.className = className;
  element.textContent = value;
  return element;
}

function buildExpensePhoto(expense) {
  if (!expense.photoDataUrl) {
    return null;
  }

  const photo = document.createElement("img");
  photo.className = "expense-photo";
  photo.alt = "Receipt photo";
  photo.src = expense.photoDataUrl;
  return photo;
}

function buildExpenseMetaText(expense) {
  const parts = [formatDate(expense.date), expense.category, expense.location, expense.aircraft];

  if (expense.tripNumber) {
    parts.push(`Trip ${expense.tripNumber}`);
  }

  return parts.filter(Boolean).join(" • ");
}

function buildInlineDateField(label, field, value) {
  const wrapper = document.createElement("label");
  const title = document.createElement("span");
  const input = document.createElement("input");

  wrapper.className = "submitted-expense-date-field";
  title.className = "submitted-expense-date-label";
  title.textContent = label;
  input.className = "submitted-expense-date-input";
  input.type = "date";
  input.value = value || "";
  input.required = true;
  input.dataset.action = "update-date";
  input.dataset.field = field;

  wrapper.append(title, input);
  return wrapper;
}

function buildReadOnlyDateField(label, value) {
  const wrapper = document.createElement("div");
  const title = document.createElement("span");
  const text = document.createElement("span");

  wrapper.className = "submitted-expense-date-field";
  title.className = "submitted-expense-date-label";
  title.textContent = label;
  text.className = "submitted-expense-date-value";
  text.textContent = value;

  wrapper.append(title, text);
  return wrapper;
}

function buildTimelineCell(label, value) {
  const wrapper = document.createElement("div");
  const dt = document.createElement("dt");
  const dd = document.createElement("dd");
  dt.textContent = label;
  dd.textContent = value;
  wrapper.append(dt, dd);
  return wrapper;
}

async function handleExpenseAction(event) {
  const actionButton = event.target.closest("[data-action]");
  if (!actionButton) {
    return;
  }

  const action = actionButton.dataset.action;

  if (["submit-group", "reimburse-group", "archive-group"].includes(action)) {
    event.preventDefault();
    event.stopPropagation();
    const group = actionButton.closest("[data-group-key]");
    const groupKey = group?.dataset.groupKey;
    if (!groupKey) {
      return;
    }

    await updateExpenseGroup(action, groupKey);
    return;
  }

  const expenseContainer = actionButton.closest("[data-expense-id]");
  const id = expenseContainer?.dataset.expenseId;
  const expense = state.expenses.find((entry) => entry.id === id);
  if (!expense) {
    return;
  }

  if (action === "edit") {
    const targetUrl = new URL("./expense.html", window.location.href);
    targetUrl.searchParams.set("id", expense.id);
    targetUrl.searchParams.set("view", state.currentView);
    targetUrl.searchParams.set("type", getRecordType(expense));
    window.location.href = targetUrl.toString();
    return;
  }

  if (action === "delete") {
    const confirmed = window.confirm(`Delete ${expense.merchant}?`);
    if (!confirmed) {
      return;
    }

    try {
      const submittedOpenState = captureSubmittedOpenState();
      await deleteExpense(id);
      await refreshExpenses({ submittedOpenState });
    } catch (error) {
      console.error(error);
      window.alert("Expenses could not delete this entry.");
    }
    return;
  }

  if (action === "quick-status") {
    const today = getToday();
    const updatedExpense = {
      ...expense,
      submittedDate: expense.submittedDate || today,
      reimbursedDate: expense.reimbursedDate || (expense.submittedDate ? today : ""),
      updatedAt: new Date().toISOString(),
    };

    if (expense.submittedDate && !expense.reimbursedDate) {
      updatedExpense.reimbursedDate = today;
    }

    try {
      const submittedOpenState = captureSubmittedOpenState();
      await saveExpense(updatedExpense);
      await refreshExpenses({ submittedOpenState });
    } catch (error) {
      console.error(error);
      window.alert("Expenses could not update the entry status.");
    }
  }
}

async function updateExpenseGroup(action, groupKey) {
  const group = buildLedgerGroups(
    filterExpenses(getScopedExpenses(state.expenses, state.currentRecordType), state.currentView)
  ).find((candidate) => candidate.key === groupKey);

  if (!group?.expenses.length) {
    return;
  }

  const actionLabel = {
    "submit-group": "submit",
    "reimburse-group": "mark paid",
    "archive-group": "archive",
  }[action];
  const confirmed = window.confirm(`Are you sure you want to ${actionLabel} all ${formatCount(group.expenses.length)} in ${group.title}?`);

  if (!confirmed) {
    return;
  }

  const today = getToday();
  const submittedOpenState = captureSubmittedOpenState();

  try {
    await Promise.all(
      group.expenses.map((expense) => {
        const updated = {
          ...expense,
          updatedAt: new Date().toISOString(),
        };

        if (action === "submit-group") {
          updated.submittedDate = updated.submittedDate || today;
        } else if (action === "reimburse-group") {
          updated.submittedDate = updated.submittedDate || today;
          updated.reimbursedDate = today;
          updated.archivedAt = "";
        } else if (action === "archive-group") {
          updated.archivedAt = today;
        }

        return saveExpense(updated);
      })
    );
    await refreshExpenses({ submittedOpenState });
  } catch (error) {
    console.error(error);
    window.alert("Expenses could not update that group.");
  }
}

async function handleInlineDateUpdate(event) {
  const input = event.target.closest('[data-action="update-date"]');
  if (!input) {
    return;
  }

  const expenseContainer = input.closest("[data-expense-id]");
  const id = expenseContainer?.dataset.expenseId;
  const expense = state.expenses.find((entry) => entry.id === id);
  if (!expense) {
    return;
  }

  const field = input.dataset.field;
  const nextValue = input.value;
  const previousValue = expense[field] || "";

  if (!field) {
    return;
  }

  if (!nextValue) {
    input.value = previousValue;
    window.alert("That date cannot be blank.");
    return;
  }

  if (nextValue === previousValue) {
    return;
  }

  const updatedExpense = {
    ...expense,
    [field]: nextValue,
    updatedAt: new Date().toISOString(),
  };
  const validationError = validateDates(updatedExpense);

  if (validationError) {
    input.value = previousValue;
    window.alert(validationError);
    return;
  }

  const submittedOpenState = captureSubmittedOpenState();

  try {
    await saveExpense(updatedExpense);
    await refreshExpenses({
      submittedOpenState,
      focusExpenseId: expense.id,
    });
  } catch (error) {
    console.error(error);
    input.value = previousValue;
    window.alert("Expenses could not update that date.");
  }
}

function captureSubmittedOpenState() {
  if (state.currentView !== "submitted") {
    return null;
  }

  return {
    groups: Array.from(elements.expenseList.querySelectorAll(".expense-group.is-open"), (group) => group.dataset.groupKey),
    expenses: Array.from(
      elements.expenseList.querySelectorAll(".submitted-expense-item[open]"),
      (item) => item.dataset.expenseId
    ),
  };
}

function restoreSubmittedOpenState(openState, focusExpenseId = "") {
  if (!openState || state.currentView !== "submitted") {
    return;
  }

  const groupsByKey = new Map(
    Array.from(elements.expenseList.querySelectorAll(".expense-group"), (group) => [
      group.dataset.groupKey,
      group,
    ])
  );
  const expensesById = new Map(
    Array.from(elements.expenseList.querySelectorAll(".submitted-expense-item"), (item) => [
      item.dataset.expenseId,
      item,
    ])
  );

  openState.groups.filter(Boolean).forEach((key) => {
    setLedgerGroupOpen(groupsByKey.get(key), true);
  });

  if (focusExpenseId) {
    const focusedExpense = expensesById.get(focusExpenseId);
    const parentGroup = focusedExpense?.closest(".expense-group");
    setLedgerGroupOpen(parentGroup, true);
    focusedExpense?.setAttribute("open", "");
  }

  openState.expenses.filter(Boolean).forEach((id) => {
    const item = expensesById.get(id);
    const parentGroup = item?.closest(".expense-group");

    if (!item || !isLedgerGroupOpen(parentGroup)) {
      return;
    }

    item.setAttribute("open", "");
  });
}

function setCurrentView(view, options = {}) {
  state.currentView = getViewConfig(view).key;
  renderSummary();
  renderListPanel();

  if (options.updateHistory !== false) {
    const nextUrl = new URL(window.location.href);
    nextUrl.searchParams.set("view", state.currentView);
    nextUrl.searchParams.set("type", state.currentRecordType);
    window.history.replaceState({}, "", nextUrl);
  }
}

function setCurrentGrouping(grouping, options = {}) {
  state.currentGrouping = normalizeGrouping(grouping);
  renderSummary();
  renderListPanel();
  window.localStorage.setItem("expenses.grouping", state.currentGrouping);

  if (options.updateHistory !== false) {
    const nextUrl = new URL(window.location.href);
    nextUrl.searchParams.set("grouping", state.currentGrouping);
    window.history.replaceState({}, "", nextUrl);
  }
}

function getInitialView() {
  const view = new URLSearchParams(window.location.search).get("view");
  return getViewConfig(view).key;
}

function getInitialRecordType() {
  const value = new URLSearchParams(window.location.search).get("type");
  return value === "incentive" ? "incentive" : "expense";
}

function getInitialGrouping() {
  const value = new URLSearchParams(window.location.search).get("grouping") || window.localStorage.getItem("expenses.grouping");
  return normalizeGrouping(value);
}

function normalizeGrouping(value) {
  return ["trip", "week", "airport", "aircraft", "vendor", "category"].includes(value) ? value : "week";
}

function setCurrentRecordType(recordType, options = {}) {
  state.currentRecordType = recordType === "incentive" ? "incentive" : "expense";
  renderSummary();
  renderListPanel();

  if (options.updateHistory !== false) {
    const nextUrl = new URL(window.location.href);
    nextUrl.searchParams.set("view", state.currentView);
    nextUrl.searchParams.set("type", state.currentRecordType);
    window.history.replaceState({}, "", nextUrl);
  }
}

function toggleMenu(event) {
  event.stopPropagation();
  const isOpening = elements.menuPopover.hidden;
  elements.menuPopover.hidden = !isOpening;
  elements.menuButton.setAttribute("aria-expanded", isOpening ? "true" : "false");
}

function closeMenuWhenOutside(event) {
  if (elements.menuPopover.hidden || event.target.closest(".home-menu")) {
    return;
  }

  elements.menuPopover.hidden = true;
  elements.menuButton.setAttribute("aria-expanded", "false");
}

function handleMenuAction(event) {
  const action = event.currentTarget.dataset.menuAction;
  elements.menuPopover.hidden = true;
  elements.menuButton.setAttribute("aria-expanded", "false");

  if (action === "import-backup") {
    state.importMode = "backup";
    elements.importInput.accept = ".json,application/json";
    elements.importInput.click();
  } else if (action === "import-csv") {
    state.importMode = "csv";
    elements.importInput.accept = ".csv,text/csv";
    elements.importInput.click();
  } else if (action === "export-backup") {
    exportExpenses();
  } else if (action === "export-csv") {
    openReportOptions("csv");
  } else if (action === "export-pdf") {
    openReportOptions("pdf");
  } else if (action === "clear") {
    clearAllEntries();
  } else if (action === "archive") {
    const archivedCount = state.expenses.filter((expense) => expense.archivedAt).length;
    window.alert(archivedCount ? `${archivedCount} archived entries are saved and included in backup exports.` : "No archived entries yet.");
  } else if (action === "categories") {
    manageOptions("category");
  } else if (action === "aircraft") {
    manageOptions("aircraft");
  } else if (action === "trips") {
    manageOptions("trip");
  }
}

function exportExpenses(options = {}) {
  const filenamePrefix = options.filenamePrefix || "expenses-manual-backup";
  const payload = buildExportPayload(state.expenses);
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  downloadBlob(blob, `${filenamePrefix}-${getToday()}.json`);
  markDailyBackupPromptHandled();
}

function maybeShowDailyBackupPrompt() {
  if (!state.expenses.length || window.localStorage.getItem(DAILY_BACKUP_STORAGE_KEY) === getToday()) {
    return;
  }

  elements.backupReminderModal.hidden = false;
  syncModalOpenState();
  elements.backupReminderDownloadButton.focus({ preventScroll: true });
}

function markDailyBackupPromptHandled() {
  window.localStorage.setItem(DAILY_BACKUP_STORAGE_KEY, getToday());
}

function closeDailyBackupPrompt() {
  elements.backupReminderModal.hidden = true;
  syncModalOpenState();
}

function dismissDailyBackupPrompt() {
  markDailyBackupPromptHandled();
  closeDailyBackupPrompt();
}

function downloadDailyBackup() {
  exportExpenses({ filenamePrefix: "expenses-daily-backup" });
  closeDailyBackupPrompt();
}

function openReportOptions(format) {
  state.pendingReportFormat = format === "pdf" ? "pdf" : "csv";
  elements.reportOptionsForm.reset();
  elements.reportExportButton.textContent = state.pendingReportFormat === "pdf" ? "Export PDF" : "Export CSV";
  populateReportOptions();
  updateReportPreview();
  elements.reportModal.hidden = false;
  syncModalOpenState();
  elements.reportOptionsForm.focus({ preventScroll: true });
}

function closeReportOptions() {
  elements.reportModal.hidden = true;
  syncModalOpenState();
}

function handleDocumentKeydown(event) {
  if (event.key !== "Escape") {
    return;
  }

  if (!elements.reportModal.hidden) {
    closeReportOptions();
  } else if (!elements.optionModal.hidden) {
    closeOptionManager();
  } else if (!elements.backupReminderModal.hidden) {
    dismissDailyBackupPrompt();
  }
}

function syncModalOpenState() {
  const isModalOpen =
    !elements.reportModal.hidden || !elements.optionModal.hidden || !elements.backupReminderModal.hidden;
  document.body.classList.toggle("modal-open", isModalOpen);
}

function populateReportOptions() {
  populateReportCheckboxGroup(elements.reportTypeOptions, "recordType", REPORT_TYPE_OPTIONS);
  populateReportCheckboxGroup(elements.reportStatusOptions, "status", REPORT_STATUS_OPTIONS);
  populateReportCheckboxGroup(
    elements.reportCategoryOptions,
    "category",
    getReportFieldOptions((expense) => expense.category, "No Category")
  );
  populateReportCheckboxGroup(
    elements.reportAirportOptions,
    "airport",
    getReportFieldOptions((expense) => expense.location, "No Airport")
  );
  populateReportCheckboxGroup(
    elements.reportAircraftOptions,
    "aircraft",
    getReportFieldOptions((expense) => expense.aircraft, "No Aircraft")
  );
  populateReportCheckboxGroup(
    elements.reportTripOptions,
    "trip",
    getReportFieldOptions((expense) => expense.tripNumber, "No Trip")
  );
}

function populateReportCheckboxGroup(container, name, options) {
  container.replaceChildren();

  if (!options.length) {
    const empty = document.createElement("p");
    empty.className = "report-empty-filter";
    empty.textContent = "No saved values yet.";
    container.appendChild(empty);
    return;
  }

  options.forEach((option) => {
    container.appendChild(buildReportCheckbox(name, option.value, option.label));
  });
}

function buildReportCheckbox(name, value, label) {
  const wrapper = document.createElement("label");
  const input = document.createElement("input");
  const text = document.createElement("span");

  wrapper.className = "report-checkbox";
  input.type = "checkbox";
  input.name = name;
  input.value = encodeReportValue(value);
  input.checked = true;
  text.textContent = label;
  wrapper.append(input, text);
  return wrapper;
}

function getReportFieldOptions(getValue, emptyLabel) {
  const options = new Map();

  state.expenses.forEach((expense) => {
    const value = normalizeReportValue(getValue(expense));
    options.set(value, value || emptyLabel);
  });

  return Array.from(options, ([value, label]) => ({ value, label }))
    .sort((left, right) => {
      if (!left.value) {
        return 1;
      }

      if (!right.value) {
        return -1;
      }

      return left.label.localeCompare(right.label, undefined, {
        numeric: true,
        sensitivity: "base",
      });
    });
}

function handleReportOptionsSubmit(event) {
  event.preventDefault();

  const options = getReportOptions();
  const dateError = getReportDateError(options);
  if (dateError) {
    window.alert(dateError);
    return;
  }

  const expenses = filterReportExpenses(options);
  if (!expenses.length) {
    window.alert("No entries match those report options.");
    return;
  }

  if (state.pendingReportFormat === "pdf") {
    exportPdfReport(expenses);
  } else {
    exportCsvReport(expenses);
  }

  closeReportOptions();
}

function updateReportPreview() {
  const options = getReportOptions();
  const dateError = getReportDateError(options);
  if (dateError) {
    elements.reportPreview.textContent = dateError;
    return;
  }

  const expenses = filterReportExpenses(options);
  const total = expenses.reduce((sum, expense) => sum + Number(expense.amount || 0), 0);
  elements.reportPreview.textContent = `${formatCount(expenses.length)} • ${formatCurrency(total)} selected`;
}

function getReportOptions() {
  return {
    startDate: elements.reportStartDate.value,
    endDate: elements.reportEndDate.value,
    recordTypes: getCheckedReportValues("recordType"),
    statuses: getCheckedReportValues("status"),
    categories: getCheckedReportValues("category"),
    airports: getCheckedReportValues("airport"),
    aircraft: getCheckedReportValues("aircraft"),
    trips: getCheckedReportValues("trip"),
    hasCategoryChoices: hasReportChoices("category"),
    hasAirportChoices: hasReportChoices("airport"),
    hasAircraftChoices: hasReportChoices("aircraft"),
    hasTripChoices: hasReportChoices("trip"),
  };
}

function getCheckedReportValues(name) {
  return Array.from(
    elements.reportOptionsForm.querySelectorAll(`input[name="${name}"]:checked`),
    (input) => decodeReportValue(input.value)
  );
}

function hasReportChoices(name) {
  return Boolean(elements.reportOptionsForm.querySelector(`input[name="${name}"]`));
}

function getReportDateError(options) {
  if (options.startDate && options.endDate && options.startDate > options.endDate) {
    return "Start date cannot be after end date.";
  }

  return "";
}

function filterReportExpenses(options) {
  return state.expenses.filter((expense) => {
    const expenseDate = expense.date || "";
    if (options.startDate && expenseDate < options.startDate) {
      return false;
    }

    if (options.endDate && expenseDate > options.endDate) {
      return false;
    }

    if (!options.recordTypes.includes(getRecordType(expense))) {
      return false;
    }

    if (!options.statuses.includes(getReportStatusKey(expense))) {
      return false;
    }

    if (options.hasCategoryChoices && !options.categories.includes(normalizeReportValue(expense.category))) {
      return false;
    }

    if (options.hasAirportChoices && !options.airports.includes(normalizeReportValue(expense.location))) {
      return false;
    }

    if (options.hasAircraftChoices && !options.aircraft.includes(normalizeReportValue(expense.aircraft))) {
      return false;
    }

    if (options.hasTripChoices && !options.trips.includes(normalizeReportValue(expense.tripNumber))) {
      return false;
    }

    return true;
  });
}

function getReportStatusKey(expense) {
  return expense.archivedAt ? "archived" : getStatusKey(expense);
}

function getReportStatusLabel(expense) {
  return expense.archivedAt ? "Archived" : getStatusLabel(expense);
}

function encodeReportValue(value) {
  return normalizeReportValue(value) || EMPTY_REPORT_VALUE;
}

function decodeReportValue(value) {
  return value === EMPTY_REPORT_VALUE ? "" : value;
}

function normalizeReportValue(value) {
  return String(value || "").trim();
}

function exportCsvReport(expenses) {
  const rows = buildCsvReportRows(expenses);
  const csv = rows.map((row) => row.map(csvEscape).join(",")).join("\n");
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  downloadBlob(blob, `expenses-report-${getToday()}.csv`);
}

function exportPdfReport(expenses) {
  const rows = expenses;
  const total = rows.reduce((sum, expense) => sum + Number(expense.amount || 0), 0);
  const reportWindow = window.open("", "_blank");

  if (!reportWindow) {
    window.alert("Your browser blocked the PDF report window. Allow pop-ups for this site and try again.");
    return;
  }

  reportWindow.document.write(buildPrintableReportHtml(rows, total));
  reportWindow.document.close();
  reportWindow.focus();
  reportWindow.setTimeout(() => reportWindow.print(), 250);
}

function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function buildCsvReportRows(expenses) {
  const header = [
    "Type",
    "Status",
    "Expected payout date",
    "Amount",
    "Vendor",
    "Category",
    "Trip #",
    "Expense date",
    "Submitted date",
    "Paid date",
    "Archived date",
    "Airport",
    "Aircraft",
    "Notes",
  ];

  const rows = sortExpenses(expenses).map((expense) => {
    const recordType = getRecordType(expense);
    return [
      recordType === "incentive" ? "Incentive" : "Expense",
      getReportStatusLabel(expense),
      expense.submittedDate ? getExpectedPayoutDate(expense, recordType) : "",
      Number(expense.amount || 0).toFixed(2),
      expense.merchant || "",
      expense.category || "",
      expense.tripNumber || "",
      expense.date || "",
      expense.submittedDate || "",
      expense.reimbursedDate || "",
      expense.archivedAt || "",
      expense.location || "",
      expense.aircraft || "",
      expense.notes || "",
    ];
  });

  return [header, ...rows];
}

function csvEscape(value) {
  const escaped = String(value ?? "").replace(/"/g, "\"\"");
  return /[",\n\r]/.test(escaped) ? `"${escaped}"` : escaped;
}

function buildPrintableReportHtml(expenses, total) {
  const generatedDate = formatDate(getToday());
  const homeUrl = new URL("./index.html", window.location.href).toString();
  const rows = sortExpenses(expenses)
    .map((expense) => `
      <tr>
        <td>
          <strong>${escapeHtml(expense.merchant || "Untitled entry")}</strong>
          <span>${escapeHtml([expense.category, expense.location, expense.aircraft].filter(Boolean).join(" • "))}</span>
        </td>
        <td>${escapeHtml(formatDate(expense.date))}</td>
        <td>${escapeHtml(getReportStatusLabel(expense))}</td>
        <td class="amount">${escapeHtml(formatCurrency(expense.amount))}</td>
      </tr>
    `)
    .join("");

  return `<!doctype html>
    <html>
      <head>
        <title>Expenses Report</title>
        <style>
          body { margin: 0; padding: 32px; color: #111; font-family: Avenir Next, Helvetica, Arial, sans-serif; background: #f7f0e6; }
          .report-nav { position: sticky; top: 0; z-index: 10; display: flex; justify-content: space-between; gap: 12px; margin: -12px 0 20px; padding: 10px; border-radius: 999px; background: rgba(255, 251, 245, .92); box-shadow: 0 12px 28px rgba(0,0,0,.12); backdrop-filter: blur(14px); }
          .report-nav a, .report-nav button { display: inline-flex; align-items: center; justify-content: center; min-height: 42px; padding: 0 18px; border: 0; border-radius: 999px; color: #111; background: white; font: inherit; font-weight: 800; text-decoration: none; cursor: pointer; }
          .report-nav button { background: #ee7100; color: white; }
          .hero { border-radius: 24px; padding: 28px; color: white; background: linear-gradient(135deg, #050505, #251406); }
          .eyebrow { margin: 0 0 8px; color: #e8be84; font-size: 12px; font-weight: 800; letter-spacing: 2px; text-transform: uppercase; }
          h1 { margin: 0; font-family: Iowan Old Style, Palatino, serif; font-size: 42px; font-weight: 400; }
          .summary { margin-top: 10px; color: rgba(255,255,255,.78); }
          table { width: 100%; margin-top: 24px; border-collapse: collapse; background: white; border-radius: 18px; overflow: hidden; }
          th, td { padding: 14px 16px; border-bottom: 1px solid #eadfce; text-align: left; vertical-align: top; }
          th { color: #6c6257; font-size: 11px; letter-spacing: 1.5px; text-transform: uppercase; }
          td span { display: block; margin-top: 4px; color: #6c6257; font-size: 12px; }
          .amount { color: #ee7100; font-weight: 800; text-align: right; white-space: nowrap; }
          @media print { body { background: white; padding: 0; } .report-nav { display: none; } .hero { break-inside: avoid; } }
        </style>
      </head>
      <body>
        <nav class="report-nav" aria-label="Report actions">
          <a href="${escapeHtml(homeUrl)}">Back to Expenses</a>
          <button type="button" onclick="window.print()">Save PDF</button>
        </nav>
        <section class="hero">
          <p class="eyebrow">PrismJet</p>
          <h1>Expenses Report</h1>
          <div class="summary">${expenses.length} ${expenses.length === 1 ? "entry" : "entries"} • ${escapeHtml(formatCurrency(total))} • Generated ${escapeHtml(generatedDate)}</div>
        </section>
        <table>
          <thead>
            <tr><th>Entry</th><th>Date</th><th>Status</th><th class="amount">Amount</th></tr>
          </thead>
          <tbody>${rows || "<tr><td colspan=\"4\">No entries to export.</td></tr>"}</tbody>
        </table>
      </body>
    </html>`;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function clearAllEntries() {
  const entryCount = state.expenses.length;

  if (!entryCount) {
    window.alert("There are no saved entries to delete.");
    return;
  }

  const confirmed = window.confirm(
    `Delete all ${entryCount} saved ${entryCount === 1 ? "entry" : "entries"} from this device? Make sure you have exported a backup first.`
  );
  if (!confirmed) {
    return;
  }

  const finalConfirmed = window.confirm(
    "This will remove every saved expense and incentive from this device. This cannot be undone unless you import a backup."
  );
  if (!finalConfirmed) {
    return;
  }

  try {
    await clearAllExpenses();
    state.expenses = [];
    renderSummary();
    renderListPanel();
    window.alert("All saved entries have been deleted from this device.");
  } catch (error) {
    console.error(error);
    window.alert("Expenses could not delete all saved entries.");
  }
}

function manageOptions(kind) {
  const config = getOptionManagerConfig(kind);
  if (!config) {
    return;
  }

  state.optionManagerKind = kind;
  elements.optionModalTitle.textContent = config.title;
  elements.optionModalCopy.textContent = config.hint;
  elements.optionNewValue.placeholder = config.placeholder;
  elements.optionNewValue.value = "";
  renderOptionManagerList();
  elements.optionModal.hidden = false;
  syncModalOpenState();
}

function closeOptionManager() {
  elements.optionModal.hidden = true;
  state.optionManagerKind = "";
  syncModalOpenState();
}

function handleOptionAddSubmit(event) {
  event.preventDefault();

  const config = getOptionManagerConfig(state.optionManagerKind);
  if (!config) {
    return;
  }

  const nextValue = config.normalize(elements.optionNewValue.value);
  if (!nextValue) {
    return;
  }

  const currentValues = getOptionManagerValues(config);
  if (currentValues.some((value) => valuesMatch(value, nextValue))) {
    window.alert(`${nextValue} is already in ${config.title}.`);
    return;
  }

  const nextValues = config.addToTop
    ? [nextValue, ...currentValues]
    : [...currentValues, nextValue];

  saveOptionManagerValues(config, nextValues);
  elements.optionNewValue.value = "";
  renderOptionManagerList();
}

function handleOptionListClick(event) {
  const deleteButton = event.target.closest("[data-option-delete]");
  if (!deleteButton) {
    return;
  }

  const config = getOptionManagerConfig(state.optionManagerKind);
  if (!config) {
    return;
  }

  const valueToDelete = deleteButton.dataset.optionDelete;
  const nextValues = getOptionManagerValues(config).filter((value) => !valuesMatch(value, valueToDelete));
  saveOptionManagerValues(config, nextValues);
  renderOptionManagerList();
}

function renderOptionManagerList() {
  const config = getOptionManagerConfig(state.optionManagerKind);
  if (!config) {
    return;
  }

  const values = getOptionManagerValues(config);
  elements.optionList.replaceChildren();

  if (!values.length) {
    const empty = document.createElement("p");
    empty.className = "option-empty-state";
    empty.textContent = `No ${config.title.toLowerCase()} yet. Add one below.`;
    elements.optionList.appendChild(empty);
    return;
  }

  values.forEach((value) => {
    const row = document.createElement("div");
    const label = document.createElement("span");
    const deleteButton = document.createElement("button");

    row.className = "option-row";
    label.textContent = value;
    deleteButton.type = "button";
    deleteButton.className = "option-delete-button";
    deleteButton.dataset.optionDelete = value;
    deleteButton.setAttribute("aria-label", `Delete ${value}`);
    deleteButton.textContent = "-";
    row.append(deleteButton, label);
    elements.optionList.appendChild(row);
  });
}

function getOptionManagerConfig(kind) {
  return OPTION_MANAGER_CONFIGS[kind] || null;
}

function getOptionManagerValues(config) {
  return uniqueOptionManagerValues(config.getValues().map((value) => config.normalize(value)), config.max);
}

function saveOptionManagerValues(config, values) {
  const settings = getSavedOptionSettings();
  settings[config.key] = uniqueOptionManagerValues(values.map((value) => config.normalize(value)), config.max);
  settings[config.customKey] = true;
  saveOptionSettings(settings);
}

function uniqueOptionManagerValues(values, max) {
  const uniqueValues = values.reduce((result, value) => {
    const cleaned = String(value || "").trim();
    if (!cleaned || result.some((candidate) => valuesMatch(candidate, cleaned))) {
      return result;
    }

    result.push(cleaned);
    return result;
  }, []);

  return Number.isFinite(max) ? uniqueValues.slice(0, max) : uniqueValues;
}

function valuesMatch(left, right) {
  return String(left || "").trim().toLowerCase() === String(right || "").trim().toLowerCase();
}

async function importExpenses(event) {
  const [file] = event.target.files || [];
  if (!file) {
    return;
  }

  try {
    const text = await file.text();
    if (state.importMode === "csv" || isCsvExpenseImport(file, text)) {
      const importedExpenses = parseCsvExpenseImport(text);

      if (!importedExpenses.length) {
        window.alert("That CSV file did not contain any entries I could import.");
        return;
      }

      for (const importedExpense of importedExpenses) {
        await saveExpense(await resolveCsvExpenseForSave(importedExpense));
      }

      await refreshExpenses();
      window.alert(`Imported or updated ${formatCount(importedExpenses.length)} from CSV.`);
      return;
    }

    const parsed = JSON.parse(text);
    const importedExpenses = extractImportedExpenseRecords(parsed);

    if (!importedExpenses.length) {
      window.alert("That backup file did not contain any entries.");
      return;
    }

    mergeImportedSettings(parsed);

    for (const rawExpense of importedExpenses) {
      await saveExpense(normalizeImportedExpense(rawExpense, createId));
    }

    await refreshExpenses();
    window.alert(`Imported ${formatCount(importedExpenses.length)}.`);
  } catch (error) {
    console.error(error);
    window.alert("Expenses could not import that file. Use an Expenses JSON backup or an accounting CSV export.");
  } finally {
    state.importMode = "any";
    elements.importInput.accept = ".json,application/json,.csv,text/csv";
    elements.importInput.value = "";
  }
}

function mergeImportedSettings(payload) {
  const incoming = payload?.settings || payload?.options || {};
  if (!incoming || typeof incoming !== "object") {
    return;
  }

  const existing = getSavedOptionSettings();
  saveOptionSettings({
    categoryOptions: [
      ...existing.categoryOptions,
      ...(incoming.categoryOptions || incoming.categories || []),
    ],
    aircraftOptions: [
      ...existing.aircraftOptions,
      ...(incoming.aircraftOptions || incoming.aircraft || []),
    ],
    tripOptions: [
      ...existing.tripOptions,
      ...(incoming.tripOptions || incoming.trips || []),
    ],
  });
}

function isCsvExpenseImport(file, text) {
  if (/\.csv$/i.test(file.name || "")) {
    return true;
  }

  const firstLine = text.trim().split(/\r?\n/, 1)[0] || "";
  return /date z/i.test(firstLine) && /vendor/i.test(firstLine) && /total amount/i.test(firstLine);
}

function parseCsvExpenseImport(text) {
  const rows = parseCsvRows(text);
  if (!rows.length) {
    return [];
  }

  const headers = rows[0].map((header) => header.trim());
  return rows
    .slice(1)
    .map((values, index) => buildCsvExpenseRecord(headers, values, index))
    .filter(Boolean);
}

function parseCsvRows(text) {
  const rows = [];
  const normalizedText = text.replace(/^\uFEFF/, "");
  let currentRow = [];
  let currentField = "";
  let inQuotes = false;

  for (let index = 0; index < normalizedText.length; index += 1) {
    const character = normalizedText[index];
    const nextCharacter = normalizedText[index + 1];

    if (character === "\"") {
      if (inQuotes && nextCharacter === "\"") {
        currentField += "\"";
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (character === "," && !inQuotes) {
      currentRow.push(currentField);
      currentField = "";
      continue;
    }

    if ((character === "\n" || character === "\r") && !inQuotes) {
      if (character === "\r" && nextCharacter === "\n") {
        index += 1;
      }
      currentRow.push(currentField);
      if (currentRow.some((value) => value.trim())) {
        rows.push(currentRow);
      }
      currentRow = [];
      currentField = "";
      continue;
    }

    currentField += character;
  }

  currentRow.push(currentField);
  if (currentRow.some((value) => value.trim())) {
    rows.push(currentRow);
  }

  return rows;
}

function buildCsvExpenseRecord(headers, values, rowIndex) {
  const row = Object.fromEntries(headers.map((header, index) => [header, values[index] || ""]));
  const amount = parseCurrencyAmount(getCsvValue(row, ["Amount", "Total amount", "Total Amount"]));
  const legacyTotalAmount = parseCurrencyAmount(getCsvValue(row, ["Total amount", "Total Amount"]));
  const merchant = String(getCsvValue(row, ["Vendor", "Merchant", "Description"])).trim();
  const date = normalizeCsvDate(
    getCsvValue(row, ["Expense date", "Incentive date", "Date Z", "Date"])
  );

  if (!date) {
    return null;
  }

  if (!(amount > 0)) {
    return null;
  }

  const rawCategory = String(getCsvValue(row, ["Category"])).trim();
  const tripNumber = String(getCsvValue(row, ["Trip #", "Trip", "Trip number", "Trip Number"])).trim();
  const submittedDate = normalizeCsvDate(getCsvValue(row, ["Submitted date", "Date submitted", "Submitted"]));
  const reimbursedDate = normalizeCsvDate(
    getCsvValue(row, ["Paid date", "Date paid", "Reimbursed date", "Date reimbursed"])
  );
  const recordTypeSource = String(getCsvValue(row, ["Type", "Record type", "Record Type"]));
  const statusSource = String(getCsvValue(row, ["Status"]));
  const archivedDate = normalizeCsvDate(getCsvValue(row, ["Archived date", "Archived At", "archivedAt"]));
  const normalizedAmount = Number(amount.toFixed(2));
  const normalizedDate = date;
  const merchantName = merchant || `Imported expense ${rowIndex + 1}`;
  const idSeed = [
    normalizedDate,
    merchantName,
    rawCategory,
    rowIndex,
  ].join("|");
  const legacyIds = [];

  if (legacyTotalAmount > 0) {
    legacyIds.push(
      buildImportedCsvId(
        [
          normalizedDate,
          merchantName,
          rawCategory,
          Number(legacyTotalAmount.toFixed(2)).toFixed(2),
          rowIndex,
        ].join("|")
      )
    );
  }

  legacyIds.push(
    buildImportedCsvId(
      [
        normalizedDate,
        merchantName,
        rawCategory,
        normalizedAmount.toFixed(2),
        rowIndex,
      ].join("|")
    )
  );

  return {
    expense: {
      id: buildImportedCsvId(idSeed),
      recordType: /incentive/i.test(recordTypeSource) ? "incentive" : "expense",
      amount: normalizedAmount,
      merchant: merchantName,
      category: mapCsvCategory(rawCategory, merchant),
      tripNumber,
      date: normalizedDate,
      location: String(getCsvValue(row, ["Airport", "Location"])).trim(),
      aircraft: String(getCsvValue(row, ["Aircraft", "Tail number", "Tail Number"])).trim().toUpperCase(),
      notes: String(getCsvValue(row, ["Notes", "Memo"])).trim(),
      submittedDate,
      reimbursedDate,
      archivedAt: archivedDate || (/archived/i.test(statusSource) ? getToday() : ""),
      photoDataUrl: "",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    legacyIds: [...new Set(legacyIds)].filter((id) => id !== buildImportedCsvId(idSeed)),
  };
}

async function resolveCsvExpenseForSave(importedExpense) {
  const existingExpense =
    (await getExpense(importedExpense.expense.id)) ||
    (await findExistingCsvExpense(importedExpense.legacyIds));

  if (!existingExpense) {
    return importedExpense.expense;
  }

  return {
    ...existingExpense,
    recordType: importedExpense.expense.recordType || existingExpense.recordType || "expense",
    amount: importedExpense.expense.amount,
    merchant: importedExpense.expense.merchant,
    category: importedExpense.expense.category,
    tripNumber: importedExpense.expense.tripNumber || existingExpense.tripNumber || "",
    location: importedExpense.expense.location || existingExpense.location || "",
    aircraft: importedExpense.expense.aircraft || existingExpense.aircraft || "",
    notes: importedExpense.expense.notes || existingExpense.notes || "",
    date: importedExpense.expense.date,
    submittedDate: importedExpense.expense.submittedDate || existingExpense.submittedDate || "",
    reimbursedDate: importedExpense.expense.reimbursedDate || existingExpense.reimbursedDate || "",
    archivedAt: importedExpense.expense.archivedAt || existingExpense.archivedAt || "",
    updatedAt: new Date().toISOString(),
  };
}

function getCsvValue(row, aliases) {
  for (const alias of aliases) {
    if (Object.hasOwn(row, alias)) {
      return row[alias];
    }
  }

  const normalizedAliases = aliases.map(normalizeCsvHeader);
  const match = Object.entries(row).find(([header]) =>
    normalizedAliases.includes(normalizeCsvHeader(header))
  );
  return match?.[1] || "";
}

function normalizeCsvHeader(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
}

async function findExistingCsvExpense(legacyIds) {
  for (const legacyId of legacyIds) {
    const expense = await getExpense(legacyId);
    if (expense) {
      return expense;
    }
  }

  return null;
}

function parseCurrencyAmount(value) {
  const normalized = String(value || "").replace(/[^0-9.-]/g, "");
  const amount = Number.parseFloat(normalized);
  return Number.isFinite(amount) ? amount : 0;
}

function normalizeCsvDate(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed) {
    return "";
  }

  const isoMatch = trimmed.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (isoMatch) {
    return trimmed;
  }

  const numericMatch = trimmed.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$/);
  if (!numericMatch) {
    return "";
  }

  const month = Number(numericMatch[1]);
  const day = Number(numericMatch[2]);
  let year = Number(numericMatch[3]);

  if (year < 100) {
    year += year >= 70 ? 1900 : 2000;
  }

  if (
    !Number.isInteger(month) ||
    !Number.isInteger(day) ||
    !Number.isInteger(year) ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > 31
  ) {
    return "";
  }

  const candidate = new Date(year, month - 1, day);
  if (
    candidate.getFullYear() !== year ||
    candidate.getMonth() !== month - 1 ||
    candidate.getDate() !== day
  ) {
    return "";
  }

  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function mapCsvCategory(rawCategory, merchant) {
  const categoryText = `${rawCategory} ${merchant}`.toLowerCase();

  if (/(hotel|lodging|marriott|inn|resort|suites)/.test(categoryText)) {
    return "Lodging";
  }

  if (/(meal|coffee|restaurant|bbq|ramen|bar|grill|cafe|breakfast|lunch|dinner)/.test(categoryText)) {
    return "Meal";
  }

  if (/(airline|flight|american airlines|delta|southwest|united|jetblue|alaska)/.test(categoryText)) {
    return "Flight";
  }

  if (/(uber|lyft|ground|transport|taxi|parking|rental|fuel|ramp fee|facility fee|shuttle|aviation)/.test(categoryText)) {
    return "Transport";
  }

  if (/(supplies|office|staples|fedex|ups)/.test(categoryText)) {
    return "Supplies";
  }

  return "Miscellaneous";
}

function buildImportedCsvId(seed) {
  let hash = 5381;
  for (let index = 0; index < seed.length; index += 1) {
    hash = (hash * 33) ^ seed.charCodeAt(index);
  }
  return `csv-${(hash >>> 0).toString(36)}`;
}

async function updateStorageStatus() {
  if (!elements.storageStatus) {
    return;
  }

  const baseMessage = "Saved on this device. Export a backup regularly for safety.";

  if (!navigator.storage?.persisted || !navigator.storage?.persist) {
    elements.storageStatus.textContent = baseMessage;
    return;
  }

  try {
    let persisted = await navigator.storage.persisted();
    if (!persisted) {
      persisted = await navigator.storage.persist();
    }

    if (persisted) {
      elements.storageStatus.textContent =
        "Saved on this device with persistent browser storage when supported. Backups are still a good habit.";
      return;
    }
  } catch (error) {
    console.error("Could not determine storage persistence.", error);
  }

  elements.storageStatus.textContent = baseMessage;
}

function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) {
    return;
  }

  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./service-worker.js").catch((error) => {
      console.error("Service worker registration failed", error);
    });
  });
}
