; Set System.AppUserModel.ID on an existing .lnk (NSIS System + propsys).
; Requires !define APP_USER_MODEL_ID before use.
;
; Usage:
;   !insertmacro SetLnkAppUserModelId "$DESKTOP\App.lnk"

!include "LogicLib.nsh"

!macro SetLnkAppUserModelId LINKPATH
  Push `${LINKPATH}`
  Call SetLnkAppUserModelIdFn
!macroend

Function SetLnkAppUserModelIdFn
  Exch $R0
  Push $R1
  Push $R2
  Push $R3
  Push $R4
  Push $R5
  Push $R6

  ; CLSID_ShellLink / IID_IShellLinkW
  System::Call 'ole32::CoCreateInstance(g "{00021401-0000-0000-C000-000000000046}",p0,i1,g "{000214F9-0000-0000-C000-000000000046}",*p.R1)i.R6'
  ${If} $R6 = 0
  ${AndIf} $R1 <> 0
    ; IID_IPersistFile
    System::Call '$R1->0(g "{0000010b-0000-0000-C000-000000000046}",*p.R2)i.R6'
    ${If} $R6 = 0
    ${AndIf} $R2 <> 0
      ; IPersistFile::Load(path, STGM_READWRITE=2)
      System::Call '$R2->5(w R0,i2)i.R6'
      ${If} $R6 = 0
        ; IID_IPropertyStore
        System::Call '$R1->0(g "{886d8eeb-8cf2-4446-8d02-cdba1dbdcf99}",*p.R3)i.R6'
        ${If} $R6 = 0
        ${AndIf} $R3 <> 0
          System::Call '*(g "{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}",i5)p.R4'
          ; PROPVARIANT is 16 bytes; *(i0,i0,p0) is only 12 on 32-bit NSIS.
          System::Alloc 16
          Pop $R5
          System::Call 'propsys::InitPropVariantFromString(w "${APP_USER_MODEL_ID}",p R5)i.R6'
          ${If} $R6 = 0
            ; IPropertyStore::SetValue / Commit
            System::Call '$R3->6(p R4,p R5)i.R6'
            System::Call '$R3->7()i.R6'
            ; IPersistFile::Save(path, TRUE)
            System::Call '$R2->6(w R0,i1)i.R6'
          ${EndIf}
          System::Call 'ole32::PropVariantClear(p R5)'
          System::Free $R5
          System::Free $R4
          System::Call '$R3->2()'
        ${EndIf}
      ${EndIf}
      System::Call '$R2->2()'
    ${EndIf}
    System::Call '$R1->2()'
  ${EndIf}

  Pop $R6
  Pop $R5
  Pop $R4
  Pop $R3
  Pop $R2
  Pop $R1
  Pop $R0
FunctionEnd
