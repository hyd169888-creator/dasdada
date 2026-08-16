#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; AI 智能打字翻译 - 智能热加载引导器 (Loader)
; 编译为 exe 后，自动优先运行同目录下最新的外部脚本，彻底免去后续重复打包
; ==============================================================================

appTitle := "AI 智能打字翻译"
mainScript := A_ScriptDir . "\Main.ahk"
settingsScript := A_ScriptDir . "\Settings_UI.ahk"

; 优先执行 Main.ahk，若不存在则回退至 Settings_UI.ahk
targetScript := FileExist(mainScript) ? mainScript : (FileExist(settingsScript) ? settingsScript : "")

if (targetScript != "") {
    ; 如果当前是以打包编译后的 .exe 在运行，直接动态调用外部最新脚本
    if (A_IsCompiled) {
        try {
            ; 使用当前 exe 内部自带的 AHK v2 运行时直接解释执行外部最新脚本
            Run('"' . A_ScriptFullPath . '" /script "' . targetScript . '"', A_ScriptDir)
            ExitApp()
        } catch {
            ; 备用方案：尝试直接调用系统关联打开
            try {
                Run('"' . targetScript . '"', A_ScriptDir)
                ExitApp()
            }
        }
    }
}

; 如果处于纯脚本开发模式直接运行 Launcher.ahk，则直接加载主界面
#Include "*i Main.ahk"
#Include "*i Settings_UI.ahk"