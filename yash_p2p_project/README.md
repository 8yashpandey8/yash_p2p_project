# SAP ABAP — Procure-to-Pay (P2P) Dashboard
### Capstone Project | SAP MM Module | KIIT SAP Centre of Excellence | April 2026

---

## 📋 Project Overview

This project demonstrates a complete **Procure-to-Pay (P2P) cycle** implementation in **SAP MM** for a fictitious company — **Yash Manufacturing Pvt Ltd**, an electronics manufacturer based in Pune, India.

The project includes:
- Full 7-step P2P process documentation with transaction codes
- Two custom ABAP programs with working source code
- SAP organisational structure configuration guide
- Real-life business scenario with accounting entries

---

## 🏭 Company Profile

| Parameter | Details |
|---|---|
| **Company** | Yash Manufacturing Pvt Ltd |
| **Industry** | Electronics — PCBs, Control Panels, Assemblies |
| **Location** | Chakan Industrial Area, Pune 410501, Maharashtra |
| **SAP System** | SAP ECC 6.0 (MM, FI, SD integrated) |
| **Turnover** | ~INR 250 Crores annually |
| **Employees** | 1,200+ |

---

## 📂 Repository Structure

```
yash_p2p_project/
│
├── abap/
│   ├── YASH_P2P_DASHBOARD.abap              ← Main P2P Dashboard (T-Code: ZP2P_DASH)
│   └── ZMM_MATERIAL_INVENTORY_REPORT.abap   ← Inventory Overview (T-Code: ZMM_INV)
│
├── config/
│   └── SAP_CONFIGURATION_GUIDE.txt          ← Full SPRO setup instructions
│
├── docs/
│   └── SAP_P2P_Yash_Final_Report.docx       ← 5-page project report (PDF-ready)
│
├── screenshots/
│   ├── screenshot1_selection.png            ← Selection screen
│   ├── screenshot2_abap_code.png            ← ABAP code in SE38
│   ├── screenshot3_alv_output.png           ← ALV grid output
│   └── screenshot4_p2p_flow.png             ← P2P process flow diagram
│
└── README.md                                ← This file
```

---

## 🔧 ABAP Programs

### Program 1: `YASH_P2P_DASHBOARD`
**T-Code:** `ZP2P_DASH`

Live Procure-to-Pay dashboard that reads data from 6 SAP tables and shows the real-time status of every Purchase Order in the P2P cycle.

**SAP Tables Used:**
| Table | Description |
|---|---|
| EKKO | Purchase Order Header |
| EKPO | Purchase Order Line Items |
| EKET | PO Schedule Lines (Delivery Date, GR Qty) |
| MSEG | Material Document Segments (Goods Receipts) |
| RBKP | Logistics Invoice Document Header |
| RSEG | Logistics Invoice Document Line Items |

**Key Features:**
- Single SQL INNER JOIN + LEFT JOIN across all tables (one DB round-trip)
- Auto-classifies each PO line into 4 status levels:
  - 🔴 `PO Open — GR Pending`
  - 🟡 `Partial GR`
  - 🟢 `GR Complete`
  - 🟢 `Invoice Posted`
- Status filter checkboxes on selection screen
- ALV Grid with zebra rows, sort, filter, Excel export, subtotals
- Traffic light icons per row
- Default sort: PO Date descending

---

### Program 2: `ZMM_MATERIAL_INVENTORY_REPORT`
**T-Code:** `ZMM_INV`

Inventory overview across all plants and storage locations — supports procurement decisions within the P2P cycle.

**SAP Tables Used:**
| Table | Description |
|---|---|
| MARA | General Material Data |
| MAKT | Material Descriptions (language-dependent) |
| MARC | Plant-Level Material Data |
| MARD | Storage Location Stock Data |

**Key Features:**
- OO ALV using modern `CL_SALV_TABLE` class (SAP-recommended)
- Language-safe: MAKT joined with `SY-LANGU` at DB level
- Optional filter for zero-stock materials
- Stock quantity aggregation (subtotals per plant)
- Default sort by Plant → Storage Location

---

## 🚀 How to Install in SAP

### Step 1 — Upload ABAP Programs
```
1. Open SE38
2. Enter program name → F5 (Create)
3. Set: Type = Executable Program, Status = Test Program
4. Copy-paste the .abap file content
5. Save (Ctrl+S) → Activate (Ctrl+F3)
```

### Step 2 — Create Transaction Codes (SE93)
```
ZP2P_DASH → YASH_P2P_DASHBOARD
ZMM_INV   → ZMM_MATERIAL_INVENTORY_REPORT
```

### Step 3 — Create Message Classes (SE91)
```
YASH_MSG: Message 001 (I) = &1 | Message 002 (E) = &1
ZMM_MSG : Message 001 (I) = &1 | Message 002 (E) = &1
```

### Step 4 — Configure SAP Org Structure
```
Refer to: config/SAP_CONFIGURATION_GUIDE.txt
Covers: Company Code YM01, Plant PL01, Storage Locations, Purchasing Org PO01
```

---

## 📊 P2P Process Flow

```
[XK01]          [MM01]          [ME51N]         [ME21N]
Vendor   →   Material   →   Purchase   →   Purchase
Master       Master         Requisition    Order
                                              ↓
[F110]          [MIRO]          [MIGO]
Vendor   ←   Invoice    ←   Goods
Payment      Verification    Receipt
```

### SAP Accounting Entries Generated

| Step | Dr | Cr |
|---|---|---|
| **GR (MIGO)** | Raw Material Inventory 2,30,000 | GR/IR Clearing A/c 2,30,000 |
| **IV (MIRO)** | GR/IR Clearing 2,30,000 + Input GST 41,400 | Vendor Account 2,71,400 |
| **PMT (F110)** | Vendor Account 2,71,400 | Bank Account 2,71,400 |

---

## 🖥️ Screenshots

| Screenshot | Description |
|---|---|
| `screenshot1_selection.png` | Selection screen of ZP2P_DASH |
| `screenshot2_abap_code.png` | ABAP code in SE38 — INNER JOIN logic |
| `screenshot3_alv_output.png` | ALV Grid output with P2P status |
| `screenshot4_p2p_flow.png` | Full P2P flow diagram with T-Codes and FI entries |

---

## ⚙️ Technology Stack

| Component | Details |
|---|---|
| Language | ABAP (Advanced Business Application Programming) |
| IDE | SE38 / ABAP Workbench |
| DB Access | Open SQL — INNER JOIN, LEFT JOIN, FOR ALL ENTRIES |
| ALV (Program 1) | `REUSE_ALV_GRID_DISPLAY` with slis type-pool |
| ALV (Program 2) | `CL_SALV_TABLE` (Object-Oriented ALV) |
| Platform | SAP ECC 6.0 / S/4HANA compatible |
| MM Tables | EKKO, EKPO, EKET, MSEG, RBKP, RSEG, MARA, MAKT, MARC, MARD |

---

## ✨ Unique Technical Highlights

1. **Single JOIN Query** — All 6 tables retrieved in one `SELECT` (no FOR ALL ENTRIES loop, no multiple SELECTs)
2. **Auto Status Classification** — FORM `derive_status` called after each enrichment step (PO → GR → Invoice)
3. **DEFINE Macro Field Catalog** — Compact `add_col` macro for all 14 ALV columns
4. **Language-Safe JOIN** — `MAKT~SPRAS = SY-LANGU` in `ON` clause (DB-level, not ABAP memory)
5. **Dual ALV Approaches** — Program 1 uses legacy slis ALV; Program 2 uses modern OO `CL_SALV_TABLE`

---

## 🔮 Future Scope

- **SAP S/4HANA Migration** — Migrate to S/4HANA for embedded analytics and Fiori mobile approvals
- **SAP Ariba Integration** — Supplier portal for e-invoicing and PO visibility
- **AI Procurement** — Intelligent vendor suggestion and invoice anomaly detection
- **GST e-Invoicing** — IRP integration for auto-IRN generation
- **MM03 Hotspot** — Double-click on Material in ALV → navigate to Material Master

---

## 📄 License

This project is submitted as a capstone project for **KIIT SAP Centre of Excellence**.
For educational use only.

---

**Yash Manufacturing Pvt Ltd | SAP MM Capstone Project | April 2026**
