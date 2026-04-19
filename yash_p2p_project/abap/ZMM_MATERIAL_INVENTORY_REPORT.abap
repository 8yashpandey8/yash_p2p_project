*&======================================================================*
*& Program     : ZMM_MATERIAL_INVENTORY_REPORT
*& T-Code      : ZMM_INV
*& Description : Material Inventory Overview — P2P Support Report
*&               Displays unrestricted-use stock across all plants
*&               and storage locations to support procurement decisions.
*& Module      : SAP MM — Materials Management
*& Author      : Yash Manufacturing Pvt Ltd
*& Created On  : April 2026
*& Platform    : SAP ECC 6.0 / S/4HANA Compatible
*&
*& HOW TO INSTALL:
*&   1. Open SE38 → Enter "ZMM_MATERIAL_INVENTORY_REPORT" → Create
*&   2. Type: Executable Program | Status: Test Program
*&   3. Paste this file → Save → Activate (Ctrl+F3)
*&   4. Assign T-Code ZMM_INV via SE93
*&
*& TABLES USED:
*&   MARA  — General Material Data
*&   MAKT  — Material Descriptions (language-dependent)
*&   MARC  — Plant-Level Material Data
*&   MARD  — Storage Location Stock Data
*&======================================================================*

REPORT zmm_material_inventory_report NO STANDARD PAGE HEADING
                                      MESSAGE-ID zmm_msg.

*----------------------------------------------------------------------*
* TYPE: One row = one material at one storage location
*----------------------------------------------------------------------*
TYPES: BEGIN OF ty_inventory,
  matnr  TYPE mara-matnr,    "Material Number
  maktx  TYPE makt-maktx,    "Material Description
  werks  TYPE marc-werks,    "Plant
  lgort  TYPE mard-lgort,    "Storage Location
  labst  TYPE mard-labst,    "Unrestricted-Use Stock Quantity
  meins  TYPE mara-meins,    "Base Unit of Measure
  mtart  TYPE mara-mtart,    "Material Type (ROH, FERT, HALB...)
  matkl  TYPE mara-matkl,    "Material Group
END OF ty_inventory.

*----------------------------------------------------------------------*
* GLOBAL DATA
*----------------------------------------------------------------------*
DATA:
  gt_inventory TYPE TABLE OF ty_inventory,  "Main data table
  go_alv       TYPE REF TO cl_salv_table,   "OO ALV object
  go_columns   TYPE REF TO cl_salv_columns_table,
  go_column    TYPE REF TO cl_salv_column_table,
  go_sorts     TYPE REF TO cl_salv_sorts,
  go_funcs     TYPE REF TO cl_salv_functions_list,
  go_display   TYPE REF TO cl_salv_display_settings,
  go_aggrs     TYPE REF TO cl_salv_aggregations.

*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE text-001.
  SELECT-OPTIONS:
    so_plant FOR marc-werks OBLIGATORY,   "Plant (obligatory)
    so_matnr FOR mara-matnr,              "Material Number (optional)
    so_mtart FOR mara-mtart,              "Material Type (optional)
    so_matkl FOR mara-matkl.              "Material Group (optional)
  PARAMETERS:
    p_zero AS CHECKBOX DEFAULT space.     "Include zero-stock materials
SELECTION-SCREEN END OF BLOCK b1.

INITIALIZATION.
  text-001 = 'Inventory Selection Criteria (Plant Obligatory)'.

*----------------------------------------------------------------------*
* MAIN PROCESSING
*----------------------------------------------------------------------*
START-OF-SELECTION.
  PERFORM fetch_inventory_data.
  PERFORM display_inventory_alv.

*&----------------------------------------------------------------------*
*& FORM: fetch_inventory_data
*& Single INNER JOIN across MARA + MAKT + MARC + MARD.
*& MAKT filtered by SY-LANGU in the ON clause — language filtering
*& at the database level (not in ABAP memory).
*&----------------------------------------------------------------------*
FORM fetch_inventory_data.

  REFRESH gt_inventory.

  IF p_zero = abap_false.
    "-- Fetch only materials with unrestricted stock > 0
    SELECT
         a~matnr  t~maktx  c~werks  d~lgort
         d~labst  a~meins  a~mtart  a~matkl
      INTO CORRESPONDING FIELDS OF TABLE gt_inventory
      FROM mara AS a
      INNER JOIN makt AS t ON  t~matnr = a~matnr
                           AND t~spras = sy-langu
      INNER JOIN marc AS c ON  c~matnr = a~matnr
      INNER JOIN mard AS d ON  d~matnr = a~matnr
                           AND d~werks = c~werks
     WHERE c~werks IN so_plant
       AND a~matnr IN so_matnr
       AND a~mtart IN so_mtart
       AND a~matkl IN so_matkl
       AND d~labst >  0
     ORDER BY c~werks d~lgort a~matnr.
  ELSE.
    "-- Include zero-stock materials as well
    SELECT
         a~matnr  t~maktx  c~werks  d~lgort
         d~labst  a~meins  a~mtart  a~matkl
      INTO CORRESPONDING FIELDS OF TABLE gt_inventory
      FROM mara AS a
      INNER JOIN makt AS t ON  t~matnr = a~matnr
                           AND t~spras = sy-langu
      INNER JOIN marc AS c ON  c~matnr = a~matnr
      INNER JOIN mard AS d ON  d~matnr = a~matnr
                           AND d~werks = c~werks
     WHERE c~werks IN so_plant
       AND a~matnr IN so_matnr
       AND a~mtart IN so_mtart
       AND a~matkl IN so_matkl
     ORDER BY c~werks d~lgort a~matnr.
  ENDIF.

  IF sy-subrc <> 0 OR gt_inventory IS INITIAL.
    MESSAGE i001 WITH 'No inventory data found for the selected plant/material.'.
    LEAVE LIST-PROCESSING.
  ENDIF.

ENDFORM.

*&----------------------------------------------------------------------*
*& FORM: display_inventory_alv
*& Renders results using modern OO CL_SALV_TABLE class.
*& Enables full toolbar, auto column widths, default sort by Plant+Loc.
*&----------------------------------------------------------------------*
FORM display_inventory_alv.

  "-- Create ALV instance
  TRY.
    cl_salv_table=>factory(
      IMPORTING r_salv_table = go_alv
      CHANGING  t_table      = gt_inventory ).
  CATCH cx_salv_msg INTO DATA(lx_msg).
    MESSAGE lx_msg->get_text( ) TYPE 'E'.
    RETURN.
  ENDTRY.

  "-- Enable full standard toolbar (sort, filter, export, subtotals)
  go_funcs = go_alv->get_functions( ).
  go_funcs->set_all( abap_true ).

  "-- Auto-optimise all column widths
  go_columns = go_alv->get_columns( ).
  go_columns->set_optimize( abap_true ).

  "-- Set descriptive column header texts
  TRY.
    go_column ?= go_columns->get_column( 'MATNR' ).
    go_column->set_long_text(   'Material Number' ).
    go_column->set_medium_text( 'Material' ).

    go_column ?= go_columns->get_column( 'MAKTX' ).
    go_column->set_long_text(   'Material Description' ).
    go_column->set_medium_text( 'Description' ).

    go_column ?= go_columns->get_column( 'WERKS' ).
    go_column->set_long_text(   'Plant' ).
    go_column->set_medium_text( 'Plant' ).

    go_column ?= go_columns->get_column( 'LGORT' ).
    go_column->set_long_text(   'Storage Location' ).
    go_column->set_medium_text( 'Stor.Loc' ).

    go_column ?= go_columns->get_column( 'LABST' ).
    go_column->set_long_text(   'Unrestricted Stock' ).
    go_column->set_medium_text( 'Unr. Stock' ).

    go_column ?= go_columns->get_column( 'MEINS' ).
    go_column->set_long_text(   'Unit of Measure' ).
    go_column->set_medium_text( 'UoM' ).

    go_column ?= go_columns->get_column( 'MTART' ).
    go_column->set_long_text(   'Material Type' ).
    go_column->set_medium_text( 'Mat. Type' ).

    go_column ?= go_columns->get_column( 'MATKL' ).
    go_column->set_long_text(   'Material Group' ).
    go_column->set_medium_text( 'Mat. Group' ).

  CATCH cx_salv_not_found.
    "Non-critical: column headers may not set but ALV still displays
  ENDTRY.

  "-- Enable subtotal aggregation on LABST (stock quantity)
  TRY.
    go_aggrs = go_alv->get_aggregations( ).
    go_aggrs->add_aggregation(
      columnname  = 'LABST'
      aggregation = if_salv_c_aggregation=>total ).
  CATCH cx_salv_data_error cx_salv_not_found cx_salv_existing.
    "Non-critical: aggregation optional
  ENDTRY.

  "-- Default sort: Plant (asc), Storage Location (asc)
  go_sorts = go_alv->get_sorts( ).
  TRY.
    go_sorts->add_sort(
      columnname = 'WERKS'
      sequence   = if_salv_c_sort_sequence=>ascending
      subtotal   = abap_true ).
    go_sorts->add_sort(
      columnname = 'LGORT'
      sequence   = if_salv_c_sort_sequence=>ascending ).
  CATCH cx_salv_data_error cx_salv_existing cx_salv_not_found.
    "Non-critical: sort without subtotals
  ENDTRY.

  "-- Set grid title
  go_display = go_alv->get_display_settings( ).
  go_display->set_list_header(
    'Yash Manufacturing — Material Inventory Overview (ZMM_INV)' ).
  go_display->set_striped_pattern( abap_true ).

  "-- Render the grid
  go_alv->display( ).

ENDFORM.

*&======================================================================*
*& MESSAGE CLASS SETUP (Create via SE91)
*&
*& Class : ZMM_MSG
*& ---------------------------------------------------------------
*& No.  Type  Text
*& 001   I    &1
*& 002   E    &1
*&======================================================================*

*&======================================================================*
*& TRANSACTION CODE (Create via SE93)
*&
*& T-Code : ZMM_INV
*& Type   : Transaction with parameters (parameter transaction)
*& Program: ZMM_MATERIAL_INVENTORY_REPORT
*& Screen : 1000 (standard selection screen)
*&======================================================================*
