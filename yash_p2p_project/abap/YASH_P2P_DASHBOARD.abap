*&======================================================================*
*& Program     : YASH_P2P_DASHBOARD
*& T-Code      : ZP2P_DASH
*& Description : Procure-to-Pay (P2P) Live Dashboard
*&               Displays PO → GR → Invoice status in one ALV Grid
*& Module      : SAP MM — Materials Management
*& Author      : Yash Manufacturing Pvt Ltd
*& Created On  : April 2026
*& Platform    : SAP ECC 6.0 / S/4HANA Compatible
*&
*& HOW TO INSTALL:
*&   1. Open SE38 → Enter "YASH_P2P_DASHBOARD" → Create
*&   2. Type: Executable Program | Status: Test Program
*&   3. Paste this entire file → Save → Activate (Ctrl+F3)
*&   4. Assign T-Code ZP2P_DASH via SE93
*&   5. Create message class YASH_MSG via SE91 (see bottom of file)
*&
*& TABLES USED:
*&   EKKO  — Purchase Order Header
*&   EKPO  — Purchase Order Line Items
*&   EKET  — PO Schedule Lines (delivery dates, GR quantities)
*&   MSEG  — Material Document Segments (Goods Receipt mov. type 101)
*&   RBKP  — Logistics Invoice Document Header (MIRO)
*&   RSEG  — Logistics Invoice Document Line Items (MIRO)
*&======================================================================*

REPORT yash_p2p_dashboard NO STANDARD PAGE HEADING
                           MESSAGE-ID yash_msg.

*----------------------------------------------------------------------*
* TYPE POOLS
*----------------------------------------------------------------------*
TYPE-POOLS: slis.

*----------------------------------------------------------------------*
* CONSTANTS
*----------------------------------------------------------------------*
CONSTANTS:
  gc_po_type   TYPE ekko-bstyp VALUE 'F',   "Standard Purchase Order
  gc_gr_mvt    TYPE mseg-bwart VALUE '101', "Goods Receipt movement
  gc_bukrs_def TYPE ekko-bukrs VALUE 'YM01'."Default Company Code

*----------------------------------------------------------------------*
* CUSTOM TYPE: One row = one PO line with full P2P status
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_p2p,
  ebeln  TYPE ekko-ebeln,    "PO Number
  aedat  TYPE ekko-aedat,    "PO Creation Date
  lifnr  TYPE ekko-lifnr,    "Vendor Number
  bukrs  TYPE ekko-bukrs,    "Company Code
  werks  TYPE ekpo-werks,    "Plant
  matnr  TYPE ekpo-matnr,    "Material Number
  menge  TYPE ekpo-menge,    "PO Quantity (ordered)
  netwr  TYPE ekpo-netwr,    "Net Order Value (INR)
  waers  TYPE ekko-waers,    "Currency
  eindt  TYPE eket-eindt,    "Scheduled Delivery Date
  wemng  TYPE eket-wemng,    "GR Quantity
  belnr  TYPE rbkp-belnr,    "Invoice Document Number
  status TYPE char25,        "P2P Status (derived field)
  icon   TYPE char4,         "Traffic light icon for status
END OF ty_p2p.

*----------------------------------------------------------------------*
* GLOBAL DATA DECLARATIONS
*----------------------------------------------------------------------*
DATA:
  gt_p2p       TYPE TABLE OF ty_p2p,     "Main data table
  gs_p2p       TYPE ty_p2p,              "Work area
  gt_fieldcat  TYPE slis_t_fieldcat_alv, "ALV field catalog
  gs_fieldcat  TYPE slis_fieldcat_alv,   "Field catalog work area
  gs_layout    TYPE slis_layout_alv,     "ALV layout settings
  gt_sort      TYPE slis_t_sortinfo_alv, "ALV sort criteria
  gs_sort      TYPE slis_sortinfo_alv,   "Sort work area
  gs_variant   TYPE disvariant,          "ALV display variant
  gv_repid     TYPE syrepid.             "Program name for callback

*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE text-001.
  SELECT-OPTIONS:
    so_bukrs FOR ekko-bukrs DEFAULT gc_bukrs_def OBLIGATORY,
    so_werks FOR ekpo-werks,
    so_aedat FOR ekko-aedat.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE text-002.
  PARAMETERS:
    p_open  AS CHECKBOX DEFAULT 'X',   "Show Open POs
    p_pgr   AS CHECKBOX DEFAULT 'X',   "Show Partial GR
    p_cgr   AS CHECKBOX DEFAULT 'X',   "Show GR Complete
    p_inv   AS CHECKBOX DEFAULT 'X'.   "Show Invoice Posted
SELECTION-SCREEN END OF BLOCK b2.

*----------------------------------------------------------------------*
* INITIALIZATION — Set selection screen texts
*----------------------------------------------------------------------*
INITIALIZATION.
  text-001 = 'Procurement Filters (Company Code Obligatory)'.
  text-002 = 'Status Filter'.

*----------------------------------------------------------------------*
* START OF SELECTION — Main processing chain
*----------------------------------------------------------------------*
START-OF-SELECTION.

  PERFORM fetch_po_data.
  PERFORM fetch_gr_data.
  PERFORM fetch_invoice_data.
  PERFORM apply_status_filter.
  PERFORM build_fieldcatalog.
  PERFORM set_layout_and_sort.
  PERFORM display_alv_report.

*&----------------------------------------------------------------------*
*& FORM: fetch_po_data
*& Reads PO header + items + schedule lines in ONE database call.
*& Uses INNER JOIN (EKKO + EKPO) and LEFT JOIN (EKET) so POs without
*& schedule lines are still included in the output.
*&----------------------------------------------------------------------*
FORM fetch_po_data.

  REFRESH gt_p2p.

  SELECT
       k~ebeln  k~aedat  k~lifnr  k~bukrs  k~waers
       p~werks  p~matnr  p~menge  p~netwr
       e~eindt  e~wemng
    INTO CORRESPONDING FIELDS OF TABLE gt_p2p
    FROM ekko AS k
    INNER JOIN ekpo AS p ON  k~ebeln = p~ebeln
    LEFT  JOIN eket AS e ON  p~ebeln = e~ebeln
                         AND p~ebelp = e~ebelp
   WHERE k~bukrs  IN so_bukrs
     AND p~werks  IN so_werks
     AND k~aedat  IN so_aedat
     AND k~bstyp  =  gc_po_type
     AND p~loekz  =  space          "Exclude deleted PO items
   ORDER BY k~aedat DESCENDING k~ebeln p~matnr.

  IF sy-subrc <> 0 OR gt_p2p IS INITIAL.
    MESSAGE i001 WITH 'No Purchase Order data found for the selected criteria.'.
    LEAVE LIST-PROCESSING.
  ENDIF.

  "-- Derive initial P2P status from GR quantity vs PO quantity
  LOOP AT gt_p2p INTO gs_p2p.
    PERFORM derive_status CHANGING gs_p2p.
    MODIFY gt_p2p FROM gs_p2p.
  ENDLOOP.

ENDFORM.

*&----------------------------------------------------------------------*
*& FORM: derive_status
*& Sets status and traffic-light icon based on quantities.
*& Called after each data enrichment step.
*&----------------------------------------------------------------------*
FORM derive_status CHANGING cs_p2p TYPE ty_p2p.

  IF cs_p2p-belnr IS NOT INITIAL.
    cs_p2p-status = 'Invoice Posted'.
    cs_p2p-icon   = '@08@'.          "Green circle icon

  ELSEIF cs_p2p-wemng >= cs_p2p-menge AND cs_p2p-menge > 0.
    cs_p2p-status = 'GR Complete'.
    cs_p2p-icon   = '@08@'.          "Green circle icon

  ELSEIF cs_p2p-wemng > 0.
    cs_p2p-status = 'Partial GR'.
    cs_p2p-icon   = '@0A@'.          "Yellow circle icon

  ELSE.
    cs_p2p-status = 'PO Open - GR Pending'.
    cs_p2p-icon   = '@0B@'.          "Red circle icon
  ENDIF.

ENDFORM.

*&----------------------------------------------------------------------*
*& FORM: fetch_gr_data
*& Reads Goods Receipt movements (type 101) from MSEG and enriches
*& the main table with actual GR quantities.
*&----------------------------------------------------------------------*
FORM fetch_gr_data.

  DATA:
    lt_mseg TYPE TABLE OF mseg,
    ls_mseg TYPE mseg.

  "-- Collect distinct PO numbers for efficient MSEG read
  DATA lt_ebeln TYPE TABLE OF ekko-ebeln.
  LOOP AT gt_p2p INTO gs_p2p.
    APPEND gs_p2p-ebeln TO lt_ebeln.
  ENDLOOP.
  SORT lt_ebeln.
  DELETE ADJACENT DUPLICATES FROM lt_ebeln.

  IF lt_ebeln IS INITIAL.
    RETURN.
  ENDIF.

  SELECT ebeln ebelp bwart menge werks lgort
    INTO TABLE lt_mseg
    FROM mseg
   FOR ALL ENTRIES IN lt_ebeln
   WHERE ebeln = lt_ebeln-table_line
     AND bwart = gc_gr_mvt.

  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  "-- Update GR quantity in main table
  LOOP AT lt_mseg INTO ls_mseg.
    READ TABLE gt_p2p ASSIGNING FIELD-SYMBOL(<ls_p2p>)
      WITH KEY ebeln = ls_mseg-ebeln.
    IF sy-subrc = 0.
      ADD ls_mseg-menge TO <ls_p2p>-wemng.
      PERFORM derive_status CHANGING <ls_p2p>.
    ENDIF.
  ENDLOOP.

ENDFORM.

*&----------------------------------------------------------------------*
*& FORM: fetch_invoice_data
*& Reads invoice documents (RBKP + RSEG) for matched POs and sets
*& the Invoice Posted status.
*&----------------------------------------------------------------------*
FORM fetch_invoice_data.

  TYPES: BEGIN OF ty_inv,
    belnr TYPE rbkp-belnr,
    gjahr TYPE rbkp-gjahr,
    lifnr TYPE rbkp-lifnr,
    bldat TYPE rbkp-bldat,
    ebeln TYPE rseg-ebeln,
  END OF ty_inv.

  DATA:
    lt_inv TYPE TABLE OF ty_inv,
    ls_inv TYPE ty_inv.

  SELECT k~belnr k~gjahr k~lifnr k~bldat s~ebeln
    INTO TABLE lt_inv
    FROM rbkp AS k
    INNER JOIN rseg AS s ON  k~belnr = s~belnr
                         AND k~gjahr = s~gjahr
   WHERE k~bukrs IN so_bukrs
     AND k~bldat IN so_aedat
     AND k~stblg =  space.          "Exclude reversed invoices

  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  "-- Set invoice number and upgrade status
  LOOP AT lt_inv INTO ls_inv.
    READ TABLE gt_p2p ASSIGNING FIELD-SYMBOL(<ls_p2p>)
      WITH KEY ebeln = ls_inv-ebeln.
    IF sy-subrc = 0 AND <ls_p2p>-belnr IS INITIAL.
      <ls_p2p>-belnr = ls_inv-belnr.
      PERFORM derive_status CHANGING <ls_p2p>.
    ENDIF.
  ENDLOOP.

ENDFORM.

*&----------------------------------------------------------------------*
*& FORM: apply_status_filter
*& Removes rows whose status does not match the checkbox filters.
*&----------------------------------------------------------------------*
FORM apply_status_filter.

  DELETE gt_p2p WHERE ( status = 'PO Open - GR Pending' AND p_open = abap_false )
                   OR ( status = 'Partial GR'            AND p_pgr  = abap_false )
                   OR ( status = 'GR Complete'           AND p_cgr  = abap_false )
                   OR ( status = 'Invoice Posted'        AND p_inv  = abap_false ).

  IF gt_p2p IS INITIAL.
    MESSAGE i001 WITH 'No records match the selected status filters.'.
    LEAVE LIST-PROCESSING.
  ENDIF.

ENDFORM.

*&----------------------------------------------------------------------*
*& FORM: build_fieldcatalog
*& Defines ALV column properties using DEFINE macro pattern.
*&----------------------------------------------------------------------*
FORM build_fieldcatalog.

  DATA lv_pos TYPE i VALUE 1.

  DEFINE add_col.
    CLEAR gs_fieldcat.
    gs_fieldcat-col_pos    = lv_pos.
    gs_fieldcat-fieldname  = &1.
    gs_fieldcat-seltext_l  = &2.
    gs_fieldcat-seltext_m  = &3.
    gs_fieldcat-outputlen  = &4.
    gs_fieldcat-just       = &5.
    APPEND gs_fieldcat TO gt_fieldcat.
    lv_pos = lv_pos + 1.
  END-OF-DEFINITION.

  "         Fieldname  Long Text          Medium Text     Width  Just
  add_col 'ICON'    'Status'           'Status'          4     'C'.
  add_col 'EBELN'   'PO Number'        'PO Number'       12    'L'.
  add_col 'AEDAT'   'PO Date'          'PO Date'         10    'C'.
  add_col 'LIFNR'   'Vendor Number'    'Vendor'          10    'L'.
  add_col 'BUKRS'   'Company Code'     'CoCode'           6    'C'.
  add_col 'WERKS'   'Plant'            'Plant'            6    'C'.
  add_col 'MATNR'   'Material Number'  'Material'        18    'L'.
  add_col 'MENGE'   'PO Quantity'      'PO Qty'          12    'R'.
  add_col 'WAERS'   'Currency'         'Curr'             5    'C'.
  add_col 'NETWR'   'Net Value (INR)'  'Net Value'       15    'R'.
  add_col 'EINDT'   'Delivery Date'    'Del. Date'       10    'C'.
  add_col 'WEMNG'   'GR Quantity'      'GR Qty'          12    'R'.
  add_col 'BELNR'   'Invoice Number'   'Invoice No'      10    'L'.
  add_col 'STATUS'  'P2P Status'       'P2P Status'      22    'L'.

  "-- Mark icon column as icon type
  READ TABLE gt_fieldcat ASSIGNING FIELD-SYMBOL(<fc>)
    WITH KEY fieldname = 'ICON'.
  IF sy-subrc = 0.
    <fc>-icon = abap_true.
  ENDIF.

  "-- Mark quantity/value fields as numeric
  LOOP AT gt_fieldcat ASSIGNING <fc>
    WHERE fieldname = 'MENGE' OR fieldname = 'NETWR' OR fieldname = 'WEMNG'.
    <fc>-do_sum = abap_true.
  ENDLOOP.

ENDFORM.

*&----------------------------------------------------------------------*
*& FORM: set_layout_and_sort
*& Configures ALV grid appearance and default sort order.
*&----------------------------------------------------------------------*
FORM set_layout_and_sort.

  "-- Layout
  gs_layout-zebra             = abap_true.  "Alternating row colours
  gs_layout-colwidth_optimize = abap_true.  "Auto column widths
  gs_layout-window_titlebar   = 'Yash Manufacturing — P2P Dashboard (ZP2P_DASH)'.
  gs_layout-edit              = space.
  gs_layout-box_fname         = space.

  "-- Variant for saving user layouts
  gs_variant-report = sy-repid.
  gs_variant-handle = '1'.

  "-- Default sort: PO Date descending, then PO Number
  CLEAR gs_sort.
  gs_sort-spos      = 1.
  gs_sort-fieldname = 'AEDAT'.
  gs_sort-tabname   = 'GT_P2P'.
  gs_sort-down      = abap_true.
  APPEND gs_sort TO gt_sort.

  CLEAR gs_sort.
  gs_sort-spos      = 2.
  gs_sort-fieldname = 'EBELN'.
  gs_sort-tabname   = 'GT_P2P'.
  gs_sort-up        = abap_true.
  APPEND gs_sort TO gt_sort.

ENDFORM.

*&----------------------------------------------------------------------*
*& FORM: display_alv_report
*& Renders the ALV Grid using REUSE_ALV_GRID_DISPLAY.
*& i_save = 'A' allows saving user-specific and global layouts.
*&----------------------------------------------------------------------*
FORM display_alv_report.

  gv_repid = sy-repid.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING
      i_callback_program       = gv_repid
      it_fieldcat              = gt_fieldcat
      is_layout                = gs_layout
      it_sort                  = gt_sort
      is_variant               = gs_variant
      i_save                   = 'A'
      i_default                = 'X'
    TABLES
      t_outtab                 = gt_p2p
    EXCEPTIONS
      program_error            = 1
      OTHERS                   = 2.

  IF sy-subrc <> 0.
    MESSAGE e002 WITH 'ALV Display failed. Check field catalog definition.'.
  ENDIF.

ENDFORM.

*&======================================================================*
*& MESSAGE CLASS SETUP (Create via SE91)
*&
*& Class : YASH_MSG
*& ---------------------------------------------------------------
*& No.  Type  Text
*& 001   I    &1
*& 002   E    &1
*&======================================================================*

*&======================================================================*
*& TRANSACTION CODE (Create via SE93)
*&
*& T-Code : ZP2P_DASH
*& Type   : Transaction with parameters (parameter transaction)
*& Program: YASH_P2P_DASHBOARD
*& Screen : 1000 (standard selection screen)
*&======================================================================*
