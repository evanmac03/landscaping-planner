# Business operations

A second module in this project: estimating and proposals, a cost book, the sales pipeline, jobs
and crews, job costing, billing and invoices, and the analytics that come out of them. It is the
half of a landscape business that DynaScape's Manage360 covers, and it is here rather than in a
separate product for one reason:

**The drawing already measures the garden.** `CadSolid.area_m2()`, the entity lengths, the counts
- the drafting module has been computing the takeoff since its first commit. Manage360's whole
value is *measure → price → propose → build → bill*, and a separate product would mean a designer
measuring the plan twice, once to draw it and once to price it. So the estimate is priced *from
the drawing*, and this module's spine is the line between them.

What it deliberately is not:

- **Not an accounting ledger.** Double-entry bookkeeping, bank reconciliation, payroll and tax
  filing are a different discipline with legal obligations attached. This module produces the
  *documents* a ledger needs - invoices, payments, credits - and hands them to whatever does the
  books, which is the adapter in §9, not a reimplementation.
- **Not a real-time multiplayer game.** Business records need durability, history and an audit
  trail; `MultiplayerSynchronizer` provides none of those, and §11 says what to use instead and
  what to keep it for.
- **Not a float arithmetic machine.** §2.1 is the longest decision in this document for a reason.

---

## 1. Shape of the module

```
scripts/biz/          the domain: money, cost book, estimate, job, billing, invoice
scripts/biz/ledger/   the accounting adapters
scenes/biz/           the panels
resources/costbook/   the shipped starter cost book
tests/test_biz_*.gd   the tests
tools/                importers and demo tools
addons/biz_tools/     the cost book editor dock (last, as with the vis tools)
user://biz/           the live store (see §11)
```

REQ-B1 The business module shall depend on the drafting module's measurements, and the drafting
module shall not depend on the business module. A plan that cannot be drawn without a cost book is
a plan that cannot be drawn.

REQ-B2 The business module shall be a **mode**: the app shall boot, draw, present and plot with no
business data present at all, and a scene the landscape module loads shall name no business type.
[The presentation mode's rule, REQ-V7.1, applied to a second mode.]

REQ-B3 Business state shall be stored as JSON documents under `user://biz/`, one record per file
(§11), and shall be loadable, inspectable and diffable without Godot.

---

## 2. The decisions, and why

Each of these is a fork where the obvious answer is wrong, so each carries its reason. This section
is the one to read before writing a line of the module.

### 2.1 Money is integer minor units. Never a float.

Money is an `int` counted in **minor units** (cents, pence, yen), and quantities are an `int` in
**thousandths** of their unit (`quantity_milli`, enough for 0.001 m2 of paving and 2.750 hours of
labour). Every multiplication is then exact until the single, deliberate, documented rounding at
the end of a line, and only *display* ever touches a decimal point - in one function,
`Money.format()`.

The reason is not that the build's floats are too small. **That was the argument, and it was
tested and found false** (§15.1): `1e8 + 1.0 == 1e8` is false in this project's Godot, so GDScript
floats here are 64-bit and hold cents exactly to about ninety trillion dollars. The reason is what
money has to do that a float cannot promise:

1. **A column must foot.** The amounts printed on an invoice have to sum to the subtotal printed
   under them, to the cent, because a customer adding up the column is the customer who calls the
   office. Carrying full precision and rounding once at the end of the arithmetic - the natural
   thing to do with floats - produces an invoice whose own column disagrees with its own total.
2. **A tax component must reproduce somebody else's arithmetic.** A tax authority publishes a
   worked example to the cent; 9.975% of 1,234.56 computed in binary floating point does not have
   to land on it. Basis-point integers do, every time.
3. **A credit must mirror its charge.** Rounding halves in the same direction for both signs is a
   property an integer rule states outright (`round half away from zero`) and a float pipeline
   arrives at by accident.
4. **It must be the same answer on any build.** A single-precision build of Godot would put the
   ceiling at 16,777,216 cents, and a project that stores money in floats could not be moved
   between build configurations without an audit. This module's numbers do not depend on the
   `precision` build flag, which is a flag nobody in the office will ever hear about.

`Money` is therefore a pair of `cents` (64-bit whatever the float width) and a currency code, with
one rounding primitive, and an **invalid** value that is contagious like a NaN, so an unreadable
price poisons the total it feeds and the estimate refuses to foot rather than pricing something at
nothing.

### 2.1a Storage: cents as integers, and the one place JSON needs care

A record stores money as `{"cents": 25000001, "currency": "CAD"}` - an integer, exactly as
`JSON.stringify` writes it, because that writer is exact. Godot's **JSON parser** hands every
number back as a float, so a reader must convert with `int()` rather than trusting the type it is
given (measured: a JSON integer round-trips exactly through `int()` on this build, and would stop
doing so above about ninety trillion dollars). The `to_dict`/`from_dict` pair of every
money-carrying model does that conversion in one place, and a test round-trips a large contract
through the real file format rather than through the objects, because the file is where a loss
would happen.

### 2.2 An estimate line carries its own prices.

A cost book changes: bark mulch is $48/yd³ this spring and $54 next. A proposal that quotes
$48 must still cost $48 when it is opened in two years, or a report about it will disagree with the
paper the customer signed. So a line stores the **resolved** unit cost and unit price it was
priced with, plus the cost book version it came from for provenance.

The same instinct as the still exporter's rule that a written picture must not silently change
when the code does. A quoted number is a promise.

### 2.3 The cost book is JSON, not a `.tres`.

A cost book is edited by an office manager, reviewed by an owner, merged by hand after two people
edit it, and versioned in git next to the estimates that cite it. JSON does all four; a `Resource`
gives editor widgets at the cost of uids, whitespace churn and merge conflicts that are not
readable. `Resource` is the right tool for runtime assets the editor must understand; a price list
is data.

### 2.4 The drawing is the takeoff.

A line may carry a `takeoff`: the entity ids it was measured from, what was measured (area, length,
count), and the measurement itself. Pricing a planting bed is then `area_m2 × rate`, and the
quantity has a lineage back to the geometry that produced it, so a revised plan can be re-priced
and *diffed* against the old estimate: "the bed grew by 4.2 m², that is $310".

This is the feature. Everything else in this document is in service of it.

### 2.5 Godot is the client; a service is the authority. MultiplayerSynchronizer is for presence.

The request names `MultiplayerSynchronizer` for cloud collaboration. It is the wrong tool for the
record store and the right tool for one small thing:

- A synchronizer replicates **properties of scene nodes** over a **live session**. There is no
  durability: a disconnection loses whatever was in flight, and nothing is on disk at either end
  until someone writes it. There is no history, no per-record revision, no authorisation, and no
  policy for what happens when two people change the same price in the same minute.
- Business records need exactly the opposite: written first, audited always, merged deliberately.
  §11 specifies a store with per-record revisions, an append-only journal, and a conflict policy
  that **refuses to auto-merge money**.
- Where a synchronizer *is* the right answer: a presence node - who has which estimate open, which
  row their cursor is in. That is transient, losing it costs nothing, and it makes two people
  working the same estimate feel like one room. That is the whole of its job here.

The honest structure is therefore: **local-first JSON store + an HTTP service for multi-user**, with
Godot as a client. Which is also how every other business tool the user has ever used works.

### 2.6 The invoice comes out of the PDF writer this project already has.

`scripts/draft/pdf_writer.gd` writes PDF by hand, and `sheet_exporter.gd` composes real pages with
it: title blocks, rules, a scale bar, text at true paper millimetres. An invoice is a simpler page
than a landscape plan. So the invoice sheet is the **same writer**, the same paper conventions, and
the same "a plotted document is a real A4/Letter page" discipline - not a second PDF dependency.
(The one thing it lacks is an image XObject, so a company *logo* is deferred and named in §15.)

And an invoice also exports as **JSON** (§9), which is the form the ledger adapter posts and the
form another tool can read. PDF is for the customer; JSON is for the machines.

### 2.7 A funnel is not a graph.

`GraphNode`/`GraphEdit` is an editor widget for node-link diagrams: ports, connections, dragging.
A funnel is not that - it is a stack of decreasing bars with a count and a value per stage, and
what a salesperson checks on a Monday is the *conversion* between two of those bars. So the funnel
is drawn by hand in `_draw()`; the pipeline is a board of cards in columns; and a graph earns its
place only for **document lineage** (lead → estimate → revision → contract → change orders →
invoices), which is a real directed graph - and even that is drawn as lanes, because the office
never needs to drag a node in it.

REQ-B4 A funnel, a conversion figure or any other analytic shall be a pure function of the event
history, and shall be reproducible for any date range. Nothing shall be a live accumulator that
only knows the present.

### 2.8 Routing is a heuristic that states its assumption.

The travelling-salesman optimum is a research problem, drive times are a guess without a routing
service, and a crew that is sent the wrong way twice stops trusting the software. So the route is
nearest-neighbour plus 2-opt over a drive-time matrix the office supplies (or a stated constant
speed), it is **deterministic** - the same stops give the same order, every run - and it *proposes*
an order that the office can drag. The assumption is printed with the route, not buried in it.

### 2.9 Profitability has stated definitions, or it has arguments.

Two people can compute "profit" for the same job and get different numbers, honestly, because the
words are ambiguous. So this module fixes them:

- **Direct cost** = labour (timesheet duration × that crew member's *loaded* rate on that date,
  recorded rather than looked up) + materials (PO *receipts*, not orders) + subcontractor invoices
  + equipment at its internal day rate. Not overhead.
- **Revenue** = billed, on an **accrual** basis: recognised when the invoice is issued, not when
  the money arrives. "Paid" is shown separately, because a job can be profitable and uncollected,
  and that is a different emergency.
- **Gross margin** = (billed − direct cost) / billed. **Overhead is not allocated to jobs.** It
  lives in the estimate's markup, so it is reflected in the price, and it is reported at company
  level where it can be measured.
- Every figure names its window and its basis. A report that cannot state its basis is refused
  rather than printed (REQ-B20).

### 2.10 Everything is a revision, and a sent document is frozen.

A proposal is revision *N* with a content hash. Revision 3 sent to the customer is immutable - not
"usually not edited", immutable, because the approved revision *is* the contract. A change order is
a small estimate attached to a job, and the **contract sum = base + approved change orders**, with
pending ones visibly *not* in it, so nobody bills a number the customer has not agreed to.

### 2.11 Tax is per line, and may compound.

A line carries a tax code; a code is a list of components, each with a rate and whether it
compounds on the previous ones. Ontario's 13% HST is one component; British Columbia's GST + PST
are two, neither compounding; and a jurisdiction that levies a local tax on the tax-inclusive
amount is why `compounds` exists rather than being assumed away. (Quebec's QST is *not* compounded
on GST since 2013, and a table that got that wrong would overcharge every Quebec customer by
half a percent.) A tax-exempt customer is a property of the *customer*, and the
exception is recorded rather than achieved by deleting the tax. [The default site is 45°N 75°W, so
this is not hypothetical.]

### 2.12 Every mutation is journalled.

`events.jsonl` per job: who, when, what, and for money fields the before and after. This is the
audit trail a business needs ("who changed the price, and when"), and it is the only tractable
undo for business state - document-level snapshots, the drafting module's approach, would need to
copy a whole job per edit.

---

## 3. Folder structure

```
scripts/biz/
  money.gd             minor units, currencies, rounding, formatting, parsing
  tax.gd               tax codes, compound components, tax on a total
  work_unit.gd         the units a cost book prices in
  cost_item.gd         one priced thing (material, labour, equipment, sub, fee)
  cost_kit.gd          a recipe of items with quantities
  cost_book.gd         the catalogue: items, kits, versions, provenance
  estimate.gd          lines, roll-ups, revisions, freezing
  takeoff.gd           drawing -> measurement -> line (phase 3)
  lead.gd, pipeline.gd stages, transitions, funnel metrics (phase 4)
  job.gd, job_cost.gd  a contracted job and its cost report (phase 5/6)
  crew.gd, schedule.gd, route.gd, time_entry.gd (phase 5)
  purchase_order.gd, change_order.gd (phase 6)
  billing.gd           schedules, milestones, percentage completion (phase 7)
  invoice.gd           invoice documents and line generation (phase 7)
  invoice_sheet.gd     the page, through pdf_writer.gd (phase 7)
  analytics.gd         funnel, win/loss, profitability, utilisation (phase 9)
  store.gd             records, revisions, the journal (phase 10)
  sync.gd              HTTP transport and the conflict policy (phase 10)
  ledger/
    ledger_adapter.gd  the interface every backend implements
    file_ledger.gd     JSON + CSV/IIF, always works
    invoice_ninja.gd   token auth, self-hosted or cloud
    akaunting.gd       HTTP Basic, ACL
resources/costbook/    the shipped starter book
scenes/biz/            one scene per panel
tests/test_biz_*.gd
user://biz/            costbook.json, jobs/<id>/, events.jsonl, invoices/
```

---

## 4. Data models

Every model is a plain class in `scripts/biz/` with `to_dict()`/`from_dict()` and no Godot node
inheritance: they are records, they are tested pure, and the `to_dict()` form is the storage form.

### 4.1 Money

```gdscript
class_name Money
extends RefCounted
## An amount in minor units, and the currency it is in.
##
## Integer, because this build's floats are 32-bit: dollars-and-cents in a float loses cents at
## 1.6 million dollars and cannot represent $167,772.17 at all (REQ-B10).

## Minor units per major unit, by currency. Two is usual; yen has none, and a currency that
## appears here with the wrong exponent is a rounding bug in every invoice.
const EXPONENTS := {"CAD": 2, "USD": 2, "EUR": 2, "GBP": 2, "JPY": 0}

## The invalid amount: what an unreadable price becomes. It is contagious, like a NaN, so a bad
## line poisons the total it feeds and the estimate refuses to foot rather than quietly pricing
## something at zero.
const INVALID_CENTS := -9223372036854775808

var cents: int = 0
var currency: StringName = &"CAD"
```

| field | type | meaning |
|---|---|---|
| `cents` | `int` | the amount in minor units; `INVALID_CENTS` means unreadable |
| `currency` | `StringName` | ISO code, which decides the display exponent |

### 4.2 Tax code

| field | type | meaning |
|---|---|---|
| `id` | `StringName` | e.g. `HST-ON`, `GST-QST`, `EXEMPT` |
| `name` | `String` | as it must appear on an invoice |
| `components` | `Array[Dictionary]` | `{name, rate_ppm, compounds}` - parts per million, so 5% is `50000` |
| `recoverable` | `bool` | whether the business reclaims it (reporting only) |

`rate_ppm` is parts per million (1e-6) because a tax rate is exact and 0.1 + 0.2 is
not. Rounding happens once per component in order, with compounding on the *rounded* previous
component, so the invoice's own arithmetic is the arithmetic of the tax authority's example.

### 4.3 Cost item

| field | type | meaning |
|---|---|---|
| `id` | `StringName` | stable, human-typable (`MULCH-BARK-BULK`) |
| `name` | `String` | "Bark mulch, bulk" |
| `kind` | `int` | MATERIAL / LABOR / EQUIPMENT / SUBCONTRACT / FEE / OTHER |
| `unit` | `StringName` | the `WorkUnit` priced in (§4.4) |
| `rate` | `Money` | **cost** per unit, never the selling price |
| `waste_ppm` | `int` | waste factor, parts per million (bulk mulch 80000 = 8%) |
| `cost_code` | `StringName` | the phase this normally belongs to |
| `tax_code` | `StringName` | default tax for lines from this item |
| `supplier` | `StringName` | optional, for PO grouping |
| `note` | `String` | optional, e.g. "minimum 3 yd³ delivery" |

### 4.4 Work unit

The eight units a landscape cost book prices in, with the conversion each needs:

```gdscript
const UNITS := {
	&"EACH":  {"name": "each",   "area": false},
	&"SQ_M":  {"name": "m²",     "area": true},
	&"SQ_FT": {"name": "ft²",    "area": true},
	&"LIN_M": {"name": "m",      "linear": true},
	&"LIN_FT": {"name": "ft",    "linear": true},
	&"CU_M":  {"name": "m³",     "volume": true},
	&"CU_YD": {"name": "yd³",    "volume": true},
	&"HOUR":  {"name": "hour",   "time": true},
	&"DAY":   {"name": "day",    "time": true},
	&"LOAD":  {"name": "load",   "count": true},
}
```
REQ-B11 A unit's dimension shall be declared, so a takeoff measured in m² can only price a `SQ_M`
line. Pricing an area at a rate per hour is not a typo a program should accept.

### 4.5 Cost kit

| field | type | meaning |
|---|---|---|
| `id` | `StringName` | `PATIO-GRANITE-COMPACTED` |
| `name` | `String` | "Patio, granite, compacted base" |
| `lines` | `Array[Dictionary]` | `{item_id, quantity_milli, note}` |
| `yield` | `int` | the quantity of *output* one kit makes, in `output_unit` |
| `output_unit` | `StringName` | what the kit is priced per (usually `SQ_M`) |
| `labour_hours` | `int` | optional total for reporting, in thousandths |

A kit is a *recipe*, so it is priced per unit of output: a 45 m² patio is `45 × kit`, and the kit's
own lines scale. Kits may contain kits, which requires cycle detection (§5.3). A line's `item_id` therefore names an **item or another kit**, and which of the two it is is the book's business: a patio kit that needs a compacted-base kit says so, and the expansion resolves it.

### 4.6 Cost book

| field | type | meaning |
|---|---|---|
| `version` | `int` | monotonic; every estimate records the one it priced from |
| `effective_from` | `String` | ISO date this version's prices take effect |
| `currency` | `StringName` | the book's currency |
| `items` | `Dictionary` | id → CostItem |
| `kits` | `Dictionary` | id → CostKit |
| `tax_codes` | `Dictionary` | id → TaxCode |
| `source` | `String` | where it came from (a supplier import, a hand edit, a file) |
| `rejected` | `Array[String]` | entries a load carried but could not use, with the reason - not persisted, and reported by `problems()` |

### 4.7 Lead and its stage events (phase 4)

| field | type | meaning |
|---|---|---|
| `id` | `String` | uuid |
| `name`, `customer`, `address` | `String` | who and where |
| `source` | `StringName` | referral / repeat / web / sign / other |
| `value_estimate` | `Money` | what the office thinks it is worth |
| `stage` | `int` | LEAD / QUALIFIED / VISIT / ESTIMATING / PROPOSED / WON / LOST / WITHDRAWN / DORMANT |
| `opened_at`, `closed_at` | `String` | ISO timestamps |
| `lost_reason` | `StringName` | required when the stage is LOST |
| `events` | `Array[Dictionary]` | `{at, from, to, by, note}` - a transition is an event, never just a field |

A stage is a *field plus a history*, because a funnel is a question about a period: "how many of
March's leads became proposals" cannot be answered by a field that only holds this month's value.

### 4.8 Estimate line

| field | type | meaning |
|---|---|---|
| `id` | `String` | uuid, so a line survives a re-order |
| `cost_item` | `StringName` | where it came from |
| `description` | `String` | as it prints |
| `quantity_milli` | `int` | thousandths of `unit` |
| `unit` | `StringName` | `WorkUnit` |
| `cost_code` | `StringName` | the phase it costs to |
| `unit_cost` | `Money` | **frozen** at the cost book version named below |
| `unit_price` | `Money` | **frozen**; what the customer is charged per unit |
| `waste_ppm` | `int` | applied to the *quantity* of material lines only (§5.1) |
| `tax_code` | `StringName` | per line, so a mixed invoice is one invoice |
| `takeoff` | `Dictionary` | `{entities, measure, value}` or empty - the drawing lineage (§2.4) |
| `book_version` | `int` | the cost book version these prices came from |
| `kind` | `int` | material / labour / equipment / subcontract / fee / other - on the line, because waste applies to material lines only (§5.1) and a book may be edited |

### 4.9 Estimate

| field | type | meaning |
|---|---|---|
| `id` | `String` | uuid |
| `number` | `String` | `EST-2026-0041`, assigned when first sent, never reused |
| `customer` | `Dictionary` | name, address, email, tax status |
| `site` | `Dictionary` | `{latitude, longitude}` - the drawing's own site |
| `lines` | `Array[EstimateLine]` | |
| `overhead_ppm`, `profit_ppm` | `int` | markup applied to direct cost, parts per million |
| `tax_code` default | `StringName` | the usual tax, overridable per line |
| `deposit_ppm` | `int` | deposit requested, parts per million of the total |
| `revision` | `int` | 0 while drafting, then 1, 2, ... |
| `status` | `int` | DRAFT / SENT / WON / LOST / EXPIRED |
| `frozen` | `Dictionary` | empty while draft; `{hash, at, to}` once sent - and then immutable |
| `notes`, `terms` | `String` | |

### 4.10 Job, phase budget, and the cost report shape (phase 5/6)

A job is `{id, estimate_revision, contract_sum, billing_method, phases[], schedule[], crew[], documents[]}`,
where a **phase** is a cost code with a budget taken from the estimate's lines for that code. The
cost report is then one row per phase:

| column | meaning |
|---|---|
| budget | the estimate's price or cost for this code (stated which) |
| committed | open purchase orders and subcontracts for this code |
| actual | receipts + approved timesheets + sub invoices + equipment days |
| variance | budget − actual (and budget − committed − actual, the honest projection) |
| percent complete | by cost incurred, or by milestone - the report says which |

### 4.11 Change order, purchase order, time entry (phase 5/6)

| model | fields that matter |
|---|---|
| ChangeOrder | `job, lines (as an estimate), reason, state (PROPOSED/APPROVED/DECLINED/VOID), approved_by, approved_at, approved_signature (photo path), affects_contract_sum` |
| PurchaseOrder | `job, cost_code, supplier, lines, ordered_milli, received_milli, state (DRAFT/ISSUED/PARTIAL/RECEIVED/CLOSED), expected_at, receipts[]` |
| TimeEntry | `job, cost_code, crew_member, started_at, ended_at, break_minutes, loaded_rate (Money, **recorded**), source (MANUAL/CLOCK/IMPORT), approved_by, note, photo` |

A PO's *received* quantity is what creates actual material cost; an issued-but-unreceived PO is
**committed** only. That distinction is the difference between a job-costing report that is trusted
and one that is quietly wrong for the last two weeks of every job (§8.3).

### 4.12 Billing schedule and invoice (phase 7)

| model | fields that matter |
|---|---|
| Milestone | `name, percent_ppm, fixed_amount (optional), trigger (DATE/PHASE_COMPLETE/APPROVED), due_date, retainage_ppm, state` |
| BillingSchedule | `job, method, milestones[], billed_to_date (Money), retainage_held (Money)` |
| Invoice | `id, number, job, issued_at, due_at, terms_days, lines[], subtotal, tax, retainage, total, payments[], balance, state (DRAFT/ISSUED/PART_PAID/PAID/VOID)` |
| Payment | `invoice, received_at, amount, method, reference` |

### 4.13 The record envelope (phase 10)

Every stored record, whatever its kind, is wrapped:

```json
{"kind": "estimate", "id": "0f3a...", "rev": 7, "updated_at": "2026-10-24T14:11:07Z",
 "updated_by": "evan", "deleted_at": null, "body": { ... }}
```
`rev` is the optimistic-concurrency token (§11.2), `deleted_at` is a tombstone rather than an
absence (so a sync cannot resurrect what someone deleted), and `body` is the model above.

---

## 5. The estimating engine

### 5.1 One line's arithmetic, exactly

```gdscript
## A line's extended price, in minor units.
##
## The order is: waste inflates the *quantity* for material lines, the quantity is multiplied by
## the frozen unit price in exact integers, and the single rounding happens here - half away from
## zero, so a credit reverses the charge it reverses to the cent.
static func extension(line: EstimateLine) -> Money:
	var quantity: int = line.quantity_milli
	if line.is_material():
		quantity = quantity * (1000000 + line.waste_ppm) / 1000000
	return Money.round_div(
		line.unit_price.cents * quantity, 1000, line.unit_price.currency
	)
```
Waste applies to **material quantity only**: labour is not wasted, and a fee is not either. A rate
per m² of finished paving is a *selling* rate, so it already contains the installer's own waste.

### 5.2 The roll-up, and the rule that makes an invoice honest

```
direct_cost      = Σ (quantity_with_waste × unit_cost)     ← each line rounded, then summed
subtotal         = Σ extension(line)                       ← each line rounded, then summed
overhead         = round(subtotal × overhead_ppm / 1000000)
profit           = round((subtotal + overhead) × profit_ppm / 1000000)
price_before_tax = subtotal + overhead + profit
tax              = tax.gross(price_before_tax, code)        ← per code, compounding per §4.2
total            = price_before_tax + tax
deposit          = round(total × deposit_ppm / 1000000)
gross_margin_pct = (price_before_tax − direct_cost) / price_before_tax × 100
```

**Tax is per line, so the markup is apportioned before it is taxed.** §4.8 puts a tax code on every
line and §2.11 says a mixed invoice is one invoice, so the arithmetic above cannot literally be one
`Tax.gross(price_before_tax, code)` when two lines carry two codes. Each line's extension plus its share
of the markup is the base its own code is charged on, lines sharing a code are charged once on their
sum, and with one code throughout that comes out **identical** to the single computation above, to the
cent (asserted for four shipped codes). The markup is apportioned in proportion to what each line is
worth, each share rounded by the module's one rule with the few cents left over handed to the largest
line, so the shares add up to the markup exactly - a markup a cent short is a total that does not foot.
See §15.6.

**The printed lines must foot to the printed subtotal.** So each line is rounded (not carried at
full precision) and the subtotal is the sum of those rounded lines. Computers that carry full
precision and round at the end produce invoices whose columns do not add up, and a customer who
adds up the column is the customer who calls the office. AC-B6 is this, as a test.

### 5.3 Kits expand with cycle detection

`expand(kit_id)` walks a kit's lines, recursing into nested kits, and **refuses** on a cycle with
the chain named (`A → B → A`). Depth is capped as well as cycle-checked, because a generated book
could be deep without being circular. Each expanded line keeps its own cost code and tax code, so
a kit spanning materials and labour still costs to the right phases.

### 5.4 What the engine refuses

The project's habit: refuse and name it. The estimating engine refuses, rather than guessing, on:
an unknown item or kit id; a quantity of zero or less; an invalid (unreadable) money value
anywhere in a line; a takeoff whose dimension does not match the line's unit (§4.4); a line with
no tax code when the customer is not exempt; a kit cycle or an over-deep kit; a discount or markup
outside sane bounds (±500%); and taxable lines on an exempt customer. In every case it names the
line and the reason, and the estimate **will not foot**: a total that silently omits a line is
worse than no total.

### 5.5 Freezing

`Estimate.freeze(sent_to)` computes the revision's content hash over the *priced* content (lines,
markups, tax, deposit - not notes), stores `{hash, at, to}`, and from then on every mutator
refuses. A copy for editing is a **new draft revision**, which is how a business revises a quote
without rewriting what the customer already has.

---

## 6. Takeoff: the drawing, priced (phase 3)

The bridge, and the reason this module exists here.

```
pick entities on a layer  →  measure by kind  →  choose a cost item  →  line with lineage
```

- A **loop** entity measures to `area_m2` (already implemented in `CadSolid`), a **line or polyline**
  to a length, a **circle** to an area or a circumference, a **prop** to a count.
- The measurement carries its own precision: `Units` already decides metric vs imperial, and a
  cost book item priced in `SQ_FT` takes `area_m2 × 10.7639…`* as an exact integer conversion
  (the conversion is a *ratio*, not a rounded constant: §5.1's rounding is the only rounding).
- `PlanStyle`/`LayerSet` already names the layers (`300-NEW-HARD`, `200-PLANTING`, …), so the
  default cost code and a candidate cost item come from the layer the geometry is on. A paving
  loop on `300-NEW-HARD` offers paving items first. The office chooses; the software suggests.
- Re-takeoff is a **diff**: price the plan again, and compare line by line, so a revision to a
  drawing produces "bed grew 4.2 m², +$310" rather than a new estimate to compare by eye.

REQ-B12 A takeoff line shall record the entity ids and the measurement it came from. A quantity
with no lineage is a number somebody typed, and must be marked as such.

---

## 7. Jobs, crews and time

### 7.1 Crew member

| field | type | meaning |
|---|---|---|
| `id` | `StringName` | |
| `name` | `String` | |
| `role` | `StringName` | FOREMAN / LEAD_HAND / LABOURER / SUBCONTRACTOR |
| `rates` | `Array[Dictionary]` | `{from, loaded_rate (Money)}` - **effective dated**, so a raise never reprices a job that is already costed |
| `home_base` | `Vector2` | where the crew starts, for the first drive leg |
| `certifications` | `Array[Dictionary]` | `{name, expires_at}` |
| `availability` | `Array[Dictionary]` | weekly hours, days off, vacation |

A crew member is not a user account. A person can be both, and the two are separate records with
separate purposes (§11.6).

### 7.2 A crew day and its route

| field | type | meaning |
|---|---|---|
| `crew` | `StringName` | |
| `date` | `String` | ISO date |
| `stops` | `Array[Dictionary]` | `{job, window_start, window_end, service_minutes, drive_minutes, sequence}` |
| `start_at`, `end_at` | `String` | the day's bookends, including the drive home |
| `route_note` | `String` | the assumption the route was computed under (§2.8) |

Routing rules, stated so they can be argued with:

1. A **drive-time matrix** is a property of the site list, supplied or approximated at a constant
   speed for straight-line distance. The matrix used is recorded with the route, because a route
   computed on 40 km/h is a different artefact from one computed on a real matrix.
2. The order is **nearest-neighbour from the crew's current position, then 2-opt** while the total
   drive time improves. No randomness, no time limit, no temperature: the same stops produce the
   same order, every time.
3. The result is a **proposal**. The office drags stops and the sequence wins.
4. A stop whose window cannot be met is *reported as late* rather than silently reordered: the
   window belongs to the customer's plumber or the nursery's delivery, not to the optimiser.

### 7.3 Time tracking

Time is entered as a **TimeEntry** (§4.11) and never as a running clock that owns the truth: a
start and an end, or an explicit duration, a job, a cost code, a break, and the loaded rate
**recorded at entry** for the reason a line's price is frozen (§2.2).

- Minutes are stored exactly. Payroll may round to a quarter hour per a company setting; the **job
  cost report uses the exact minutes**, because the labour genuinely took them.
- A field entry is **offline-first**: written locally with its uuid and synced later (§11.5). A
  timesheet shall never require a network connection to be recorded.
- Entries are **approved** by an office user before they become cost. An unapproved entry is shown
  as "pending" and excluded from actual cost, with the pending total visible - so a report never
  reads low without saying why.
- A break longer than the shift, an end before the start, or an entry overlapping another for the
  same crew member is **refused or flagged**, never averaged away.

### 7.4 The schedule board

Crews down the side, days across the top, jobs as blocks. Drag to place, drag to move. Conflicts -
the same crew twice in one window, the same job with two crews, a stop outside a window, a crew
member past their availability - are **reported in a list** and highlighted. Nothing is moved
automatically: a scheduler that rearranges a crew's day without being asked is a scheduler nobody
trusts twice.

---

## 8. Change orders, purchase orders, job costing

### 8.1 The workflow, and who may do each step

| step | office | field | who can undo it |
|---|---|---|---|
| add a time entry or a photo | yes | yes | its author, until approved |
| approve time as cost | yes | no | an office user |
| create a change order (draft) | yes | yes | its author while DRAFT |
| send a change order | yes | no | an office user, while PROPOSED |
| approve a change order (customer) | recorded by office | photo/signature capture | never - it is a contract document |
| issue a purchase order | yes | no | an office user while ISSUED |
| receive against a PO | yes | yes (with photo) | the receiver, until the period is closed |
| issue an invoice | yes | no | never; it is voided and reissued (§9.4) |
| close a job | yes | no | an office user, with a reason |

REQ-B13 Every approval shall record **who, when, and how** (in-app, a signed paper photo, an
e-mail reference), because "the customer agreed" is a claim a business has to be able to support.

### 8.2 Change orders

A change order is a small estimate attached to a job, so it reuses §5's engine, its lines, its tax
handling and its refusals. What it adds:

- `reason` is required, from a short list (customer request / site condition / design change /
  code or permit / error and omission / other) - this is the data that later says whether the
  business is losing money to *unforeseen* conditions or to its own estimating.
- States: PROPOSED → SENT → APPROVED / DECLINED / VOID, with the approval record above.
- **Only APPROVED change orders enter the contract sum.** A pending one is shown separately, and
  the billing screens say so: "contract sum $84,300 (2 change orders pending, $4,150 not yet
  agreed)".
- Billing a pending change order is possible but requires an explicit flag, prints a note on the
  invoice, and appears in the A/R review - because sometimes the work is done and waiting for the
  paperwork is not an option, and the software should allow it *knowingly*.

### 8.3 Purchase orders and receipts: committed versus actual

```
issued   → committed cost (it is owed the moment the truck leaves, not when the invoice arrives)
received → actual cost (a receipt is a quantity received, priced at the PO's line rate)
closed   → neither, once invoiced and reconciled
```
- A PO line has `ordered_milli` and `received_milli`, and receipts are their own records, so a
  partial delivery is normal and visible.
- **Committed** cost is what makes a mid-job cost report honest. Without it, a job looks profitable
  for the three weeks between the mulch arriving and the invoice being entered, and every
  landscape business has been burned by exactly that.
- Receiving more or less than ordered is **not** an error: the receipt says what arrived, the
  variance is reported, and the PO's cost uses receipts.

### 8.4 The job cost report, and the three numbers

Per cost code, always three numbers - **budget, committed, actual** - plus two derived:

| | |
|---|---|
| budget | from the estimate's lines for that code (cost or price, stated) |
| committed | open POs + approved subcontracts |
| actual | receipts + approved time + sub invoices + equipment days |
| variance | budget − actual |
| projection | budget − actual − committed ("what it will cost if nothing else happens") |
| % complete | by cost incurred, or by milestone; the report says which |

Plus the breakdown nobody can avoid agreeing with: **contract sum, billed, cost, gross margin,
uncollected**, each with its basis (§2.9). A job with more committed than budget is flagged at the
moment the PO is issued - not at the WIP review three weeks later - because that is the only
moment the office can still do something about it.

---

## 9. Billing, invoices, and the ledger

### 9.1 Billing methods

| method | what it needs | how an amount due is computed |
|---|---|---|
| FIXED | the contract sum | all of it, on completion (or on a stated trigger) |
| MILESTONE | a schedule of milestones | the milestone's percent or fixed amount, when its trigger fires |
| PERCENTAGE_COMPLETE | a measured percent | `round(contract × pct) − billed_to_date` (§9.3) |
| TIME_AND_MATERIALS | approved time + received materials | `labour (hours × billing rate) + materials × markup`, per period |
| COST_PLUS | actual cost | `actual cost × (1 + fee_ppm)` per period |

A job's method is a property of the *contract* (it is what the customer agreed to), not of the
invoice, so it cannot be changed by billing.

### 9.2 Milestones and retainage

A milestone is `{name, percent_ppm or fixed_amount, trigger, due_date, retainage_ppm, state}`. The
schedule's percents must total 100% (or the missing part is named as *unbilled* - the refusal
again, rather than silently billing 87% of a job and calling it complete). Retainage is withheld
per milestone, accumulates in `retainage_held`, and is released by an explicit act at closeout.
The invoice shows retainage as a deduction with its own line, because a customer's bookkeeper will
look for it.

### 9.3 Percentage completion, and the double-billing guard

```
target_billed = round(contract_sum × percent_ppm / 1000000)
amount_due    = target_billed − billed_to_date          (never negative: a re-bill bills zero)
billed_to_date += amount_due
```
The tracker is the point. Billing 30% then 60% bills 30% twice only in software that computes the
*percentage* as the amount. The tests name this: two billings at 30% and 60% produce equal
invoices, and billing 60% again produces an invoice of zero with a note that says why.

Percentage-complete requires a measured percent. The measurement is entered by the office with a
basis (by cost incurred, by phase completion), and **the basis is stored with the number**, because
"60% complete" from a cost report and from a walk-around are different claims.

### 9.4 Invoices: numbering, states, and the void

- **Numbering** is per fiscal year, gapless among issued invoices, assigned at **issue** rather
  than at draft (`INV-2026-0184`). A draft has no number; deleting a draft leaves no hole.
- **States**: DRAFT → ISSUED → PART_PAID → PAID, plus VOID. A voided invoice **keeps its number**
  and names its replacement; gap-free numbering with a visible void is what an auditor wants, and
  an invoice is never edited after issue - it is voided and reissued.
- **Contents**: customer and site, invoice number and dates, terms, lines (a milestone, or T&M
  detail, or a change order), subtotal, tax by code, retainage, total, payments applied, balance,
  and the job's address in the place the drawing already knows.
- **Payments** are their own records and are applied against a balance, oldest invoice first by
  default and re-appliable; a payment larger than the balance is **refused**, not clamped, and a
  refund is a credit note document rather than a negative payment.
- **Idempotency**: every push to a ledger carries a client-generated key, so a retry after a
  timeout cannot double-post an invoice (§9.6).

### 9.5 The page (PDF) and the document (JSON)

`invoice_sheet.gd` composes the page with `scripts/draft/pdf_writer.gd` - the same writer that
plots sheets, at true paper millimetres, on Letter or A4 - and `Invoice.to_dict()` is the
API-neutral document. PDF is for the customer and the file; JSON is what the adapter posts and what
another system reads. Both come from the same `Invoice`, so they cannot disagree.

An invoice page is a *simpler* page than a landscape plan: header with the company and the
customer, a line grid, a totals block, terms, and a page number. The one thing the writer cannot do
yet is an image XObject, so a **company logo is deferred and named** (§15) rather than faked with
text art.

### 9.6 The ledger adapter

```gdscript
class_name LedgerAdapter
extends RefCounted
## What this module needs from whatever keeps the books.

func capabilities() -> Dictionary:
	# {"invoices": true, "payments": true, "credits": false, "customers": true,
	#  "idempotency": true, "attachments": false}
	pass

## The requests to push a document. Pure: it builds, it does not send.
func build_invoice_push(invoice: Invoice, idempotency_key: String) -> Dictionary:
	# {"method": "POST", "url": "...", "headers": {...}, "body": {...}}
	pass

## Read one of these back into the local record, or report why it cannot be.
func parse_invoice_response(response: Dictionary) -> Dictionary:
	# {"ok": true, "external_id": "INV-184", "number": "INV-2026-0184"} or
	# {"ok": false, "reason": "401 unauthorized: check the API token"}
	pass
```

**Implementations, and why each exists:**

| adapter | auth | why it is here |
|---|---|---|
| `file_ledger.gd` | none | writes JSON plus **CSV and IIF** for whatever the bookkeeper already uses (a great many small businesses run QuickBooks Desktop, and IIF is the only door into it). Always works, needs no service, and is the default. |
| `invoice_ninja.gd` | API token | self-hostable or cloud, source-available (Elastic License 2.0 - source-available, not OSI-open), REST with an OpenAPI spec, invoices/quotes/payments/expenses. The best fit for "open-source QuickBooks alternative". |
| `akaunting.gd` | HTTP Basic | open-source core (paid modules), REST CRUD with ACL permissions; `read-api`/write permissions per user. A heavier, more accounting-shaped system. |

**What is testable without a server**, and therefore what the tests cover: the **request builder**
(method, URL, headers, body) against fixtures, the **response parser** (success, 401, 422
validation, a rate limit), the **capability checks** (a backend that cannot do credits must make the
credit path refuse rather than silently drop), and the **reconciliation loop** (§9.7). A live
server is a deployment, not a unit test; a recorded fixture is the honest half.

REQ-B14 No adapter shall be able to block the workflow: an invoice issues and prints whether or not
a ledger is configured, and the push is a queued, retryable, idempotent action with a visible state
(queued / pushed / failed and why).

### 9.7 Reconciliation

The local store keeps, per pushed document, `{pushed_at, external_id, external_number, last_response}`.
`verify()` re-reads a sample from the backend and reports drift in both directions - issued here but
absent there, or present there but unknown here. A business that cannot answer "does our software
agree with our books" discovers the answer at year end, which is the worst possible time.

---

## 10. Analytics

Every figure below is a **pure function of the event history and the documents**, computable for
any date range (§2.4 in requirements: REQ-B4), and every one names its basis and window. A figure
that cannot be computed from the data present is **refused**, with the missing thing named, rather
than shown as zero.

| figure | definition | basis / window |
|---|---|---|
| funnel by stage | count and value at each stage, and conversion stage→stage | stage events, by period entered |
| win rate | won / (won + lost) | **decision date**, withdrawn excluded and counted separately |
| lost reasons | count and value by reason code | decision date |
| average sale, average cycle | mean contract sum; lead→close and estimate→decision days | won jobs, by close date |
| source performance | win rate and average value by lead source | lead source, decision date |
| pipeline value | open stages, raw and probability-weighted by stage | now |
| slipped | open past its expected close date, with the days late | now |
| job profitability | contract sum, billed, direct cost, gross margin | accrual, per job and per phase |
| cost tracking | budget vs committed vs actual per cost code | per job |
| backlog | approved contract value not yet billed | now |
| WIP | cost incurred against billed to date | per job, per period |
| A/R ageing | unpaid invoices bucketed 0-30/31-60/61-90/90+ | invoice due date |
| crew utilisation | billable hours / available hours | per crew member, by period |

REQ-B15 Analytics shall be recomputable: every figure shall be derivable from stored documents and
events, with no live accumulator anywhere (REQ-B4), so that a report for last March is the same
report next year.

REQ-B16 A figure that cannot be computed shall be reported as unavailable, naming what is missing
(for example: "win rate unavailable: 4 of 11 closed leads have no lost reason").

---

## 11. Collaboration, sync and version control

### 11.1 The store: one record per file, plus a journal

```
user://biz/
  costbook.json                  the catalogue, versioned in-file (not per record: it is a table)
  journals/events-2026-10.jsonl  append-only: who did what, when, to which record
  jobs/<job_id>/job.json
  jobs/<job_id>/estimate/<estimate_id>.json
  jobs/<job_id>/change_order/<id>.json
  jobs/<job_id>/purchase_order/<id>.json
  jobs/<job_id>/time_entry/<id>.json
  jobs/<job_id>/invoice/<id>.json
  leads/<lead_id>.json
  crew/<crew_id>.json
  sync/state.json                the cursor, pending pushes, conflicts
```

One file per record because a job's month of edits then diffs as a handful of small files rather
than a rewritten megabyte, which makes **git a usable version control strategy for the whole
business** (§11.6) and makes a merge conflict something a human can read.

### 11.2 Sync protocol

The service is small and boring on purpose:

| call | purpose |
|---|---|
| `GET /changes?since=<cursor>&limit=n` | the append-only server change log; records changed since the cursor |
| `PUT /records/<kind>/<id>` with `If-Match: <rev>` | push; `200` = accepted at `rev+1`, `409` = someone else changed it |
| `POST /attachments` | photos (receipts, signatures, site photos) - separate from records, because they are large and immutable |
| `GET /health`, `GET /whoami` | deployment checks |

Sync is **pull-then-push**, idempotent, and safe to interrupt: the cursor only advances after the
pull is applied to disk. A device that has been offline for a week pulls the week and pushes its
queue.

### 11.3 Conflicts: three policies by kind, because money is not text

| kind | policy | why |
|---|---|---|
| descriptive text (notes, descriptions, names) | last writer wins, per field | losing a note's wording is not a business event |
| structure (lines added or removed, schedule stops) | **record-level LWW with the loser kept as a conflict copy** | a human must see that two people edited one document |
| **money** (a rate, a quantity, an amount, a tax code, an approval) | **never auto-merged** | a silently merged price is a wrong invoice, and a wrong invoice is a legal problem, not a UI problem |

A money conflict creates a `conflict` record naming both values, both authors and both timestamps,
and the **document refuses to issue** until a human picks. That refusal is the feature.

### 11.4 A sent proposal is immutable; the revision history is the version control

Estimates are append-only by revision (§5.5), which means the *interesting* history - what was
quoted, changed, and agreed - is data, not a git log. Git is for the files; revisions are for the
business.

### 11.5 Offline first, which is not optional

A truck in a driveway has no signal. So: every field action (time entry, photo, CO draft, delivery
receipt) is written locally, carries a uuid generated on the device, and syncs when it can. The
queue is visible ("3 entries waiting to sync"), and a sync failure never blocks the next entry.

### 11.6 Version control strategy, stated plainly

1. **The store is git-able and that is the strategy for history**: the office (or a script) commits
   `user://biz/` daily; a what-if estimate is a branch; a customer dispute is a `git log -p` on one
   file. No bespoke history format is invented for data git already understands.
2. **The service provides concurrency, not history**: it orders writes and arbitrates revisions.
   Its own backup is a second copy of the same files.
3. **Schema versioning** is in the files: `schema_version` per document, and an **upcaster** table
   (`1→2`, `2→3`) applied on load, with the old form still readable. A business's records outlive
   several generations of this software; a document that can only be read by the version that wrote
   it is a data loss with a delay on it.
4. **Accounts and roles** live on the service: OWNER / OFFICE / FIELD / VIEWER, tokens rather than
   passwords on the device, and a role decides which of §8.1's steps are available - the same
   matrix, enforced in one place.

### 11.7 What `MultiplayerSynchronizer` is for here

One node, one purpose: a `presence` node replicated over a live session carrying
`{user, kind, id, field, cursor}` - who has which document open and where they are in it. It makes
two people editing one estimate feel like one room. It is never the source of truth for a record,
never carries money, and losing it costs nothing. [Adopting it needs a relay or peer transport
setup, which is a deployment decision (§15), and it is deliberately not in the built phases.]

---

## 12. UI: the panels, and the rules they obey

The module is a **mode**, like the presentation: entering it takes the whole window, leaving it
returns exactly what was there (the presentation's own contract, REQ-V7.1). A left rail switches
between panels; the work area is one panel at a time.

| panel | what it is | the control that matters |
|---|---|---|
| Pipeline | columns by stage, cards dragging between them; a drop into LOST asks for the reason | the loss reason, which is the whole win/loss report |
| Lead / site visit | a form and a photo strip | source and expected close date |
| Estimate editor | a grid: description, qty, unit, cost, price, margin, cost code, tax | the **money columns**, which are integer-formatted and never a float |
| Takeoff | the plan in a pane, an entity selection, and the resulting line | pick on the drawing, price from the book |
| Cost book | a tree of items and kits, an editor, and an importer (CSV from a supplier) | bulk price update with an effective date and a preview of what it changes |
| Proposal | the sheet preview, revision history, and **Send** | Send freezes a revision (§5.5) |
| Job home | one screen: contract sum, schedule, crew, budget vs actual, billing, documents | the three numbers (§8.4) |
| Schedule | crews down, days across, drag to place | the conflict list |
| Time entry | big targets, a job picker, a cost code, a start/stop; works on a tablet | offline state, shown plainly |
| Change orders | list + editor + approval capture | the approval record |
| Purchase orders | list + editor + receiving with a photo | ordered vs received |
| Billing | method, milestones, percentage complete, and **Issue invoice** | the preview of what will be billed before issuing |
| Invoices | list, filters by state and age, the page, and the ledger push state | void (which keeps the number) |
| Analytics | the funnel drawn by hand, then tables of the figures in §10 | the basis and window, printed under every figure |
| Settings | company, tax codes, terms, numbering, ledger adapter, roles | the adapter's test button |

The rules, carried over from the landscape side of the app because they are right there too:

- **Nothing takes the keyboard unless it is typed into.** Text and number fields take focus; buttons
  and grids do not; Escape leaves a mode and never commits a number. (The HUD's own lesson.)
- **A grid is the one place focus is legitimate**, so the estimate grid is a focusable grid with an
  explicit Escape that discards the cell and a visible cursor - and its arrow-key editing must not
  steal the mode's Escape.
- **Every destructive act names the number it will change** ("Void INV-2026-0184, $4,120.50 to
  A/R?"), because a confirmation that says "are you sure?" trains people to click yes.
- **Money is formatted from integer minor units**, in one function, everywhere (§2.1).
- **A figure shows its basis and its window** (§10), or it does not appear.

---

## 13. Requirements and acceptance criteria

REQ-B5 Money shall be integer minor units with a currency, and no arithmetic on money shall use a
floating-point value. Rounding shall happen once per line, half away from zero.

REQ-B6 An estimate line shall store the unit cost and unit price it was priced with, and the cost
book version they came from. A cost book change shall never alter a stored estimate.

REQ-B7 A cost book shall be a JSON document with a monotonic version and an effective date, and
shall be loadable without Godot.

REQ-B8 A kit shall expand, including nested kits, with cycle detection and a depth cap, and shall
refuse with the chain named.

REQ-B9 A takeoff line shall carry the entity ids and the measurement it came from, and a unit's
dimension shall be checked against the measurement's dimension.

REQ-B10 The sum of the printed line amounts shall equal the printed subtotal, and the printed tax
components shall sum to the printed tax total.

REQ-B17 A job's cost report shall show budget, committed and actual separately, and shall derive
committed from issued-not-received purchase orders.

REQ-B18 Only approved change orders shall enter the contract sum; a pending one shall be shown
separately wherever the contract sum is shown, and billing one shall require an explicit flag that
is printed on the invoice.

REQ-B19 An invoice shall never be edited after issue: it shall be voided and reissued, keeping its
number; numbering shall be gapless within a fiscal year.

REQ-B20 Every figure in the analytics shall name its basis and its window, or be refused with the
missing input named.

REQ-B21 All money arithmetic shall be reversible: for any document, applying its negative shall
return the totals to zero.

REQ-B22 A timesheet shall be storable offline and sync later, and an entry shall never require a
network call to be recorded.

| id | criterion | how |
|---|---|---|
| AC-B1 | Adding cents never loses a cent: 100,000 lines of 1 cent total 100,000 cents. | test |
| AC-B2 | A $250,000.00 amount round-trips exactly, which a float cannot. | test |
| AC-B3 | `Money.parse` on junk yields an invalid amount, which is contagious through a roll-up. | test |
| AC-B4 | Rounding a half-cent credits and charges symmetrically (away from zero, both signs). | test |
| AC-B5 | A compounded tax code reproduces its worked example to the cent. | test |
| AC-B6 | The printed lines foot to the printed subtotal, including with per-line rounding and waste. | test |
| AC-B7 | An estimate priced from cost book v3 still costs the same after the book is updated to v4. | test |
| AC-B8 | A kit cycle is refused, naming the chain. | test |
| AC-B9 | A nested kit expands to the same lines as writing it out. | test |
| AC-B10 | Pricing an area takeoff against a time-unit item is refused. | test |
| AC-B11 | Two billings at 30% and 60% produce equal invoices, and a third at 60% produces zero. | test |
| AC-B12 | The milestone percentages must total 100, or the remainder is named unbilled. | test |
| AC-B13 | A payment larger than the balance is refused, and a void keeps its number. | test |
| AC-B14 | An adapter that reports no credit capability makes the credit path refuse rather than drop. | test |
| AC-B15 | An invoice push built by an adapter is idempotent under retry with the same key. | test |
| AC-B16 | Two money edits conflict into a conflict record, and the document refuses to issue. | test |
| AC-B17 | A funnel figure for a past period is recomputed from events and matches the live value at
that time. | test |
| AC-B18 | An analytic missing its input is reported unavailable, naming the input. | test |
| AC-B19 | The store round-trips a job through files and back, with its revisions and journal. | test |
| AC-B20 | The app boots, draws, presents and plots with `user://biz/` absent. | test |

---

## 14. Phasing

Each phase is a shippable increment with its own tests, ordered so that the arithmetic is proved
before anything depends on it.

| # | phase | contents | state |
|---|---|---|---|
| 0 | **Money, tax, units** | `money.gd`, `tax.gd`, `work_unit.gd`; integer minor units, currencies, rounding, parsing; tax codes with compounding; the unit table with dimensions | **built** - 28 tests |
| 1 | **Cost book** | `cost_item.gd`, `cost_kit.gd`, `cost_book.gd`; items, kits with cycle detection, JSON persistence, versioning, refusals | **built** - 16 tests |
| 2 | **Estimate** | `estimate_line.gd`, `estimate.gd`; lines with frozen prices, waste, roll-up, foots-to-subtotal, freezing and revisions | **built** - 29 tests |
| 3 | **Takeoff** | `takeoff.gd`; entity selection → measurement → line, with lineage and re-takeoff diffs | **built** - 18 tests |
| 4 | **Pipeline** | `lead.gd`, `pipeline.gd`; stages as events, funnel and conversion metrics, the board | specified |
| 5 | **Jobs and crews** | `job.gd`, `crew.gd`, `schedule.gd`, `route.gd`, `time_entry.gd`; scheduling, routing, offline time | specified |
| 6 | **Job costing** | `purchase_order.gd`, `change_order.gd`, `job_cost.gd`; committed vs actual, variance, WIP | specified |
| 7 | **Billing and invoices** | `billing.gd`, `invoice.gd`, `invoice_sheet.gd`; milestones, percentage completion, the page, the JSON | specified |
| 8 | **Ledger adapters** | `ledger/*`; file/CSV/IIF, Invoice Ninja, Akaunting, idempotency, reconciliation | specified |
| 9 | **Analytics** | `analytics.gd`; the figures in §10, each with its basis | specified |
| 10 | **Store and sync** | `store.gd`, `sync.gd`; records, revisions, journal, HTTP, conflicts, presence | specified |
| 11 | **Editor plugin** | `addons/biz_tools/`; the cost book dock, bulk import and price preview | specified |

REQ-B23 A phase shall be shippable on its own, and shall add its tests in the same commit.

REQ-B24 The module shall not regress the landscape suite: every test that passed before a change
shall still pass after it.

---

## 14a. The way in

Phases 0-3 were built, tested and reachable by nothing: four engines with no door. The door is two
files, and neither of them holds any arithmetic.

**`scripts/biz/estimate_desk.gd`** (`EstimateDesk`) is the join. It holds the drawing, the cost book,
the takeoff and the estimate, runs the two hand-offs the engines already define - `Takeoff.of_plan`
and `Takeoff.estimate` - and answers the questions a panel asks in words. Every figure it shows comes
from `Estimate.summary` or a line's own `line_text()`, so the desk and the proposal cannot disagree:
a desk that recomputed a total would be a second place for the rounding rule to live.

It is **not** a fifth engine and it is not a mode. The business specification's §14 describes a
business *mode* with twelve panels; what is built is the four engines that mode would have shown, so
what is built is what the door opens onto. Phases 4-11 remain specified and unbuilt, and the desk
does not pretend otherwise: it prices a drawing and it writes a proposal, and it knows nothing about
leads, jobs, invoices or a ledger.

Three decisions inside it are worth naming:

* **One fault, one sentence.** The takeoff and the estimate both notice the same unpriced line, and
  the takeoff's version is the fuller one ("30 plants have no species recorded, so there is nothing to
  price them with" against "no species recorded has no cost item"). Where the takeoff has already
  explained a line, the estimate's shorter refusal is dropped rather than printed beside it. A panel
  that says the same thing twice reads as two problems.
* **The office's own book wins, and a book that will not load is refused rather than fallen back
  from.** `load_book` looks at the path it was given, then `CostBook.DEFAULT_PATH`, then the starter
  file. A file that is there and will not load is the answer - it is what somebody meant to use - and
  being quietly priced from the starter list instead is the worst kind of quiet wrong.
* **A raise re-prices.** The estimate's tax code is the *default* an estimate hands to each line at
  the moment it is added, so changing it edits nothing that exists; the desk re-runs the takeoff
  instead. That is also why the code is chosen before taking off, and why the window says so.

**`scripts/estimate_window.gd`** (`EstimateWindow`) is the panel: a `Window`, like the plant library
and the ground window, because it has dropdowns and a field to type a customer's name into, and `Root`
is built focus-free so that nothing in this HUD can take the drawing keys.

It is **three tabs** rather than one long column: what the plan measures, what that prices at, and the
price list it was priced from are three tables of different shapes, and stacking them is a window
thirteen hundred pixels tall on a nine hundred pixel screen - whose bottom third could not be read.
The three things true of all of them (take off, check, write) sit above, and the one thing that ends
the job (who it goes to, and sending it) sits below.

Two rules it keeps:

* **A line nothing can price is shown where it would have been.** The refusals are printed in the
  proposal's own list, switched off, so a proposal that is missing a patio looks different from a
  drawing that has no patio.
* **A button that cannot do anything says why.** "Send it" is dead until something is priced and dead
  again once it has gone, and its tooltip says which of the two it is - the rule the plant panel's
  Place button already follows.

Reached from the **Estimate** menu, between Plant and Present, which is hidden when there is no
drawing (a takeoff measures a drawing, so a scene without one has nothing to take off). The menu's own
line is the desk's `describe()`, refreshed from the same snapshot the ticks are: the menu reports, the
window is the work.

REQ-B25 A phase's figures shall be shown by an engine that computed them, and a panel shall not
recompute a figure the engine already owns.

REQ-B26 A line the module can measure and cannot price shall appear in the estimate **as the refusal**,
not omitted, and not priced at zero.

---

## 15. What building it will change

The entries below were found **before** the code that would have depended on them was
written, which is the cheapest place to find them.

**15.1 The single-precision premise was false.** §2.1 originally argued from this build's floats
being 32-bit - a ceiling of 16,777,216 cents, and a large contract unrepresentable. It was a good
argument and it was wrong. A decisive probe (`1e8 + 1.0 == 1e8`, true in float32 and false in
float64) says these floats are 64-bit, and a cents value round-trips through JSON exactly. The
decision to count cents stands, because the four reasons in §2.1 do not depend on the float's
width - but the specification was about to justify a design with a fact about the machine that the
machine itself could refute, and a reader who checked would have been right to distrust the rest of
the document. **A premise about the environment is a claim like any other: it gets measured, and
the measurement goes in the file.**

**15.2 A basis point could not state the tax.** §2.1 said a rate is an integer, and named the
basis point as the unit. Quebec's QST is 9.975% - 997.5 basis points - so the unit could not hold
the rate at all, and the table stored 9975, which is 99.75%. Every estimate to a Quebec customer
would have charged the value of the job again as tax, and the arithmetic would have looked
perfectly reasonable in the file. The test that caught it was written to check a worked example to
the cent, not to check the unit. The lesson is not "use parts per million": it is that **the unit
has to be chosen from the values that actually exist, and the awkward value has to be found before
the table is filled in** - 9.975% was in this specification's own tax list from the first draft.
Rates are parts per million throughout now, and each shipped code is asserted to the cent against
arithmetic done by hand.

**15.3 The compounding flag meant the opposite of how it reads.** The flag was implemented as
"this component becomes part of the base for the components after it", so a code that wanted QST
charged on GST had to mark **GST**. Marking QST - the way the sentence "QST compounds on GST" is
written, and the way a bookkeeper would say it - put both taxes on the price and produced a tax
figure that was plausible and wrong. The test that caught it was written from that sentence rather
than from the implementation, which is the only kind of test that can catch a meaning. The flag now
marks the component that compounds on its predecessors, marking the other one is a test, and the
two spellings are asserted to produce different tax so the meaning cannot drift back.

**15.4 An item's tax code swallowed the estimate's.** `CostItem.tax_code` defaulted to `NONE`, meaning
"this item is zero-rated", and every estimate line copied it - so an estimate whose own code was HST
came out with every line carrying `NONE`, charged nothing, and said so nowhere. A $4,284.00 patio went
out untaxed because the *starter book* had a default rather than an opinion. Empty now means "this item
states no code" and the estimate's own code fills the line in; `NONE` still means a real zero charge,
which is the same distinction the tax table already draws for a customer. A single default in a data
file became a business decision about a jurisdiction, which no data file is entitled to make.

**15.5 The measure is a dimension, not a unit.** §2.4's lineage is `{entities, measure, value}` and
`measure` is *what was measured* - "area", "length", "count". The first implementation checked
`WorkUnit.has(measure)`, which asks whether the measurement is a **unit**, so the check was skipped for
every real lineage and REQ-B9 would have passed its own test while doing nothing: a length drawn on a
paving layer and priced per square metre would have gone onto a proposal. The check is against
`WorkUnit.dimension(unit)`. The test that asserted the refusal carried a real lineage, which is why the
hole was found before a customer found it.

**15.6 Tax per line and one tax on the total are not the same arithmetic.** §5.2 states the roll-up
as a single `Tax.gross(price_before_tax, code)`; §4.8 puts a tax code on every line and §2.11
requires a mixed invoice to be one invoice. Both cannot hold literally, and charging each line's own
extension and then the markup at the default code would reproduce neither (it differs from the stated
formula by a cent whenever the rounding lands differently). The markup is apportioned by largest
remainder and each code charged once on its own base, which is **identical to §5.2 in the ordinary
single-code case** and is asserted so - so the refinement is pinned to the arithmetic the specification
states rather than to a new one.

**15.7 A takeoff key has to name what was measured, not only where.** `TakeoffLine.source` was
`layer:<name>`, and one layer legitimately produces two lines - a paved patio as an **area** and its
edging as a **length**. The second line overwrote the first in the diff's index, so a re-takeoff of an
unchanged plan reported a change in the edging as a change in the paving: a whole line of money
attributed to the wrong phase. The key is `layer:<name>|<measure>` now. **A key that is not unique is a
key that is silently a different feature.**

**15.8 `CostItem.make`'s last parameter was named `code` and was the currency.** The starter book was
generated through it, passed `"HARDSCAPE"` as the cost code, and every item came out *priced in*
HARDSCAPE - refused by `CostBook.problems` as a currency mismatch, which is what caught it. The
parameter is `currency` now, and `cost_code` is deliberately left for the caller: which phase a thing
costs to is a business decision, not a default. The same file has a `cost_code` field twelve lines
above, which is why the name was read the way it was.

**15.9 `Array[StringName].sort()` sorts by pointer, so a sorted list was not sorted.** `item_ids()`
"returned the ids in order" and did nothing of the kind: a StringName orders by its pointer, so a
"choose a cost item" list offered precast slabs above the interlock for no reason a person could see,
and the order could differ between runs. It sorts on the string form now, naturally, so item 2 precedes
item 10. (This project had already recorded the same fact once, when a plant catalogue's ids came back
in pointer order - which is exactly why it was recognised here.)

**15.10 A frozen price has to be a copy.** `Money`'s fields are writable, so a line that stored the cost
item's own `Money` would hold an **alias**: repricing the book would silently move the frozen price on
an estimate that had already been sent, which is the one thing §2.2 exists to prevent. It was found
while writing `EstimateLine.make`, not by a failing test, and `Money.copy()` exists because of it. **A
value type with a mutable field is a reference type wearing a disguise.**

**15.11 The specification's waste arithmetic truncates.** §5.1 writes the waste inflation as an
integer division, which truncates toward zero; the implementation rounds half away from zero, because
that is the one rounding rule this module has and a credit should reverse the quantity its charge
inflated as well as the money. The difference is at most a thousandth of a unit. Recorded because the
snippet in §5.1 is still there, and a reader implementing from it would get a different, and
slightly asymmetric, answer.

**15.12 A cost book had to be shipped for a takeoff to be testable.** `res://data/biz/costbook.json`:
21 items, 3 kits, illustrative prices, and a `source` field that says so in words. The alternative was
tests that build a book inline - which they do, and should - but a takeoff has nothing to measure
*against* without a price list, and a person opening this project should be able to price a drawing on
their first run. It follows the plant module's precedent, and like that list it is a starting point to
be replaced rather than a price list to be trusted.

**15.13 `"1 entities"` was the kind of line that can only survive a log file.** `TakeoffLine.describe()`
built `"%d entities"` for any count, so every single-entity line - which is most of a small plan - read
"1 entities" in the takeoff list. The string had been in the repository since phase 3 and no test
minded, because a test asserts facts and this is prose. The first person to read it was a designer
looking at the new panel. **Text that only ever went to a log file is text nobody has read, and the
first time a panel shows it is the first time it is being written.**

**15.14 A printed line that does not multiply.** `EstimateLine.line_text()` printed the measured
quantity and the extension, and the extension includes waste: the starter book's paving carries 5% for
the cuts, so a line read `95.921 m²  Interlock paving, installed @ $85.00 = $8,560.95`. A reader who
multiplied got $8,153.29 and no way from the page to learn why - the difference was §5.1's waste,
which the line *had* been computing correctly since phase 2 and had never *said*. It now reads
`95.921 m² +5.0% waste  ... = $8,560.95`: the quantity stays the quantity the drawing measured, and
the waste is named rather than folded into it, because a figure that quietly grew between the plan and
the proposal is the thing nobody can check. Found by reading the window's own output against a
calculator rather than by running the tests - which passed, then and now, because the arithmetic was
never wrong.

**15.15 A refusal told twice is a panel that reports two problems.** See §14a: `Takeoff.problems` and
`Estimate`'s refusals both name an unpriced line, in different words. Nothing was wrong with either;
the fault was in the join that printed both. **A join's job includes deciding whose sentence to
keep.**

The visualization specification's equivalent section (§8.8) accumulated ten
corrections, every one of them found by building rather than by reading, and two of them found by
looking at a render. This section is where the same thing happens here: the changes are recorded as
they are found, with the reason, and not written after the fact to look inevitable.

**Named before the fact, and deferred consciously:** a company logo on an invoice (the PDF writer
draws text and vector paths, not images - an image XObject is a real addition); a live routing
service (the heuristic and its stated assumption stand in); a payroll export (payroll is a
different discipline); and the presence synchronizer (§11.7), which needs a transport decision of
its own.
