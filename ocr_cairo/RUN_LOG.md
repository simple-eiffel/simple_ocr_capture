# ocr_cairo_gui run log (M3 - existing product, new face)

Larry's directive: rebuild the simple_ocr_capture GUI using simple_cairo,
first, "so I can see this in action on an existing project product."

## What is REAL in this window (not mocked)

- OCR_SETTINGS loaded from the same %APPDATA% settings.json the classic
  GUI writes: region, output folder/file, model, endpoint, timeouts, flags
- OCR_PREFLIGHT live on the 500 ms tick: Ollama reachability + model
  presence chips in the toolbar, headline in the status strip
- OCR_HOTKEY - the product's own message-only-window hotkey class,
  registered by THIS process and polled exactly as the classic GUI polls it
- Capture Now / Ctrl+Alt+G runs the real pipeline: spawns the product exe
  in --shot mode (real screen grab of the saved region, real OCR through
  Ollama), stdout streamed into the activity log via SIMPLE_ASYNC_PROCESS
- Open Text File: ShellExecuteW on settings.text_file_path

## Deferred to M4, disabled WITH THEIR REASON shown (self-explaining controls)

- Set Region: the picker is a full-screen Vision2 window (EV_SCREEN capture,
  XOR rubber band)
- Settings editing: 24 text fields + 15 checkboxes await the toolkit's
  input widgets
- Auto-run transport and outlines: EV_POPUP_WINDOW machinery

## Gates (verbatim)

    ec.sh check ocr_cairo_gui -> clean, first try
    ec.sh test  ocr_cairo_gui -> F_code built

## Launch (2026-08-21, verbatim)

    Simple OCR Capture (cairo face) up. Ctrl+Alt+G or the button captures.
    First frame written to ocr_cairo_first_frame.png

First frame committed beside this log. Worker exe resolved to the repo
F_code build; falls back to C:\Program Files when absent.
