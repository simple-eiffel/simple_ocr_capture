; ============================================================================
;  Simple OCR Capture - Inno Setup script
;
;  Ships THREE files: the finalized Eiffel binary (statically linked, only
;  Windows system DLLs imported - no VC++ runtime, no libcurl; Ollama is
;  reached over WinHTTP), cairo.dll (the 2D engine behind the new pure-Win32
;  face - no Vision2, no GTK), and winocr_label.ps1 (the page-indicator read
;  via Windows.Media.Ocr, run by the inbox Windows PowerShell 5.1; if the
;  script is missing the app falls back to reading labels with the model).
;
;  The exe is its own OCR worker: the run engine spawns this same binary
;  with --worker, which dispatches past the GUI into the CLI.
;
;  The 9.5 GB OCR model is deliberately NOT bundled. The application checks for
;  it at startup and offers to pull it, which keeps this installer small and
;  lets the model be updated without re-shipping gigabytes.
;
;  Build:  "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" simple_ocr_capture.iss
; ============================================================================

#define AppName        "Simple OCR Capture"
#define AppVersion     "1.10.0"
#define AppPublisher   "Larry Rix"
#define AppExeName     "simple_ocr_capture.exe"
#define SourceExe      "..\EIFGENs\ocr_capture\F_code\simple_ocr_capture.exe"

[Setup]
AppId={{9F2C4A31-7D58-4E60-B1A7-3C6E24D9B085}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=.\output
OutputBaseFilename=SimpleOcrCapture-{#AppVersion}-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}

; Per-user install: no UAC prompt, and the app only ever writes to
; %APPDATA% and the user's chosen output folder.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; The Eiffel binary is 64-bit.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\EIFGENs\ocr_capture\F_code\cairo.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ocr_cairo\winocr_label.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt";   DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\{#AppName}";              Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}";    Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";        Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Captured images and transcripts live in a folder the USER chose. Never
; touch those. Only the app's own settings and log are ours to remove, and
; even those are left in place unless the user asks - see the uninstall
; prompt in [Code].
Type: files; Name: "{userappdata}\simple_ocr_capture\ocr_capture.log"
; The log of the Ollama server this application starts. Ours to remove; the
; Ollama install it belongs to is not touched.
Type: files; Name: "{localappdata}\Ollama\simple_ocr_serve.log"

[Code]

const
  OllamaUrl = 'https://ollama.com/download';

var
  OllamaPage: TOutputMsgWizardPage;
  OllamaMissing: Boolean;

function OllamaInstalled: Boolean;
var
  ResultCode: Integer;
begin
  { Check the usual install locations first, then fall back to asking the
    shell whether 'ollama' resolves on PATH. Ollama's own installer puts it
    under LocalAppData\Programs and adds it to PATH. }
  Result :=
    FileExists(ExpandConstant('{localappdata}\Programs\Ollama\ollama.exe')) or
    FileExists(ExpandConstant('{commonpf}\Ollama\ollama.exe')) or
    FileExists(ExpandConstant('{commonpf32}\Ollama\ollama.exe'));

  if not Result then
    if Exec(ExpandConstant('{cmd}'), '/C where ollama >nul 2>&1', '',
            SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      Result := (ResultCode = 0);
end;

procedure InitializeWizard;
begin
  OllamaMissing := not OllamaInstalled;

  { Informational only. Setup still installs: the user may be about to
    install Ollama, or may be pointing the app at another machine's endpoint. }
  OllamaPage := CreateOutputMsgPage(wpWelcome,
    'Ollama is required',
    'Simple OCR Capture needs Ollama to run the OCR model.',
    'Ollama was not found on this computer.' + #13#10#13#10 +
    'Simple OCR Capture does the screen capture and the text handling, but the' + #13#10 +
    'OCR itself runs on a local model served by Ollama. Without it, captures' + #13#10 +
    'will fail with a "cannot reach endpoint" message.' + #13#10#13#10 +
    'Install Ollama from:' + #13#10 +
    '    ' + OllamaUrl + #13#10#13#10 +
    'You do NOT need to start Ollama yourself. Once it is installed, Simple OCR' + #13#10 +
    'Capture starts the server it needs on its own at launch, watches it while' + #13#10 +
    'you work, and offers to restart it if it ever stops.' + #13#10#13#10 +
    'Setup will continue either way - you can install Ollama afterwards and' + #13#10 +
    'then use "Check Setup / Install Model" inside the application.' + #13#10#13#10 +
    'The OCR model itself (about 9.5 GB) is NOT included in this installer.' + #13#10 +
    'The application will offer to download it the first time you run it.');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  { Only show the Ollama page when it is actually missing. }
  if (OllamaPage <> nil) and (PageID = OllamaPage.ID) then
    Result := not OllamaMissing;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  SettingsDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    SettingsDir := ExpandConstant('{userappdata}\simple_ocr_capture');

    { Only ever delete settings after an EXPLICIT yes from a real dialog.

      UninstallSilent must be checked first. Under /VERYSILENT with
      /SUPPRESSMSGBOXES, MsgBox does not display anything - it returns the
      DEFAULT answer, which for MB_YESNO is IDYES. So a prompt written the
      obvious way silently answers itself and deletes the user's settings
      during any scripted or silent uninstall. That happened here during
      testing and destroyed a real configuration. }
    if DirExists(SettingsDir) and (not UninstallSilent) then
      if MsgBox('Remove your Simple OCR Capture settings as well?' + #13#10#13#10 +
                'This deletes the saved capture region, hotkey and folder choices.' + #13#10 +
                'Your captured images and transcripts are NOT affected.' + #13#10#13#10 +
                'Choose No to keep them for a future reinstall.',
                mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(SettingsDir, True, True, True);
  end;
end;
