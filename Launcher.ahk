#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; AI 智能打字翻译 - 智能热加载引导器 (Loader)
; ==============================================================================

appTitle := "AI 智能打字翻译"
mainScript := A_ScriptDir . "\Main.ahk"
settingsScript := A_ScriptDir . "\Settings_UI.ahk"

targetScript := FileExist(mainScript) ? mainScript : (FileExist(settingsScript) ? settingsScript : "")

if (targetScript != "") {
    if (A_IsCompiled) {
        try {
            Run('"' . A_ScriptFullPath . '" /script "' . targetScript . '"', A_ScriptDir)
            ExitApp()
        } catch {
            try {
                Run('"' . targetScript . '"', A_ScriptDir)
                ExitApp()
            }
        }
    }
}

; 💡 核心修复：删掉后面多余的 #Include "*i Main.ahk" 等，
; 避免在非编译模式下造成重复包含和类名冲突！