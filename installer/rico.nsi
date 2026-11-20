; Rico installer (per-user, no admin needed). Build: makensis -DVERSION=x.y.z rico.nsi
Unicode true
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "Sections.nsh"

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!define APP "Rico"
!define SRC "..\build\Rico"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Rico"
!define RUN_KEY "Software\Microsoft\Windows\CurrentVersion\Run"

Name "${APP}"
OutFile "..\build\Rico-Setup-${VERSION}.exe"
InstallDir "$LOCALAPPDATA\Programs\Rico"
InstallDirRegKey HKCU "${UNINST_KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "Rico ${VERSION}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "Rico"
VIAddVersionKey "FileDescription" "Rico desktop assistant installer"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "CompanyName" "Pierre Joshua"
VIAddVersionKey "LegalCopyright" "Pierre Joshua"

!define MUI_ICON "rico.ico"
!define MUI_UNICON "rico.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "welcome.bmp"
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT
!define MUI_HEADERIMAGE_BITMAP "header.bmp"
!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TITLE "Meet Rico"
!define MUI_WELCOMEPAGE_TEXT "Rico is a cheeky little brass bullet who lives on your desktop.$\r$\n$\r$\nHe chats, searches everything with Alt+Space, sets reminders, looks after your PC and keeps himself up to date.$\r$\n$\r$\nNo admin rights needed: he installs just for you."
!insertmacro MUI_PAGE_WELCOME
!define MUI_COMPONENTSPAGE_SMALLDESC
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "Rico is ready"
!define MUI_FINISHPAGE_TEXT "He'll appear at the bottom of your screen. Right-click him for the menu, or press Alt+Space to search."
!define MUI_FINISHPAGE_RUN "$INSTDIR\Rico.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Start Rico now"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function CloseRico
  nsExec::Exec 'taskkill /IM Rico.exe /F'
  nsExec::Exec 'taskkill /IM rico_helper.exe /F'
  nsExec::Exec 'taskkill /IM llama-server.exe /F'
  nsExec::Exec 'taskkill /IM whisper-cli.exe /F'
  Sleep 800
FunctionEnd

Section "Rico (required)" SecMain
  SectionIn RO
  Call CloseRico
  SetOutPath "$INSTDIR"
  File /r "${SRC}\*.*"
  WriteUninstaller "$INSTDIR\Uninstall Rico.exe"
  CreateShortcut "$SMPROGRAMS\Rico.lnk" "$INSTDIR\Rico.exe" "" "$INSTDIR\rico.ico" 0
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "Rico"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "Pierre Joshua"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\rico.ico"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall Rico.exe"'
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall Rico.exe" /S'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" $0
SectionEnd

Section "Desktop shortcut" SecDesk
  CreateShortcut "$DESKTOP\Rico.lnk" "$INSTDIR\Rico.exe" "" "$INSTDIR\rico.ico" 0
SectionEnd

Section "Start Rico with Windows" SecRun
  WriteRegStr HKCU "${RUN_KEY}" "Rico" '"$INSTDIR\Rico.exe"'
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} "Rico himself, his voice and search helpers, and the offline brain runtime."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesk} "Put a Rico shortcut on your desktop."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecRun} "Rico starts automatically when you sign in to Windows."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function .onInit
  ; silent installs are updates: don't change shortcuts or startup choices
  ${If} ${Silent}
    !insertmacro UnselectSection ${SecDesk}
    !insertmacro UnselectSection ${SecRun}
  ${EndIf}
FunctionEnd

Function .onInstSuccess
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/RELAUNCH" $1
  ${IfNot} ${Errors}
    Exec '"$INSTDIR\Rico.exe"'
  ${EndIf}
FunctionEnd

Section "Uninstall"
  nsExec::Exec 'taskkill /IM Rico.exe /F'
  nsExec::Exec 'taskkill /IM rico_helper.exe /F'
  nsExec::Exec 'taskkill /IM llama-server.exe /F'
  Sleep 800
  Delete "$SMPROGRAMS\Rico.lnk"
  Delete "$DESKTOP\Rico.lnk"
  DeleteRegValue HKCU "${RUN_KEY}" "Rico"
  DeleteRegKey HKCU "${UNINST_KEY}"
  RMDir /r "$INSTDIR"
  ${IfNot} ${Silent}
    MessageBox MB_YESNO|MB_ICONQUESTION "Also delete Rico's settings, memory, reminders and offline brain?$\r$\n(Choose No to keep them in case you reinstall.)" IDNO keep
    RMDir /r "$APPDATA\Rico"
    keep:
  ${EndIf}
SectionEnd
