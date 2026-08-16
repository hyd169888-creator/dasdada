#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent(true)

#Include AI_Translate.ahk
#Include Settings_UI.ahk
#Include Float_Bar.ahk
#Include Updater.ahk

; ==============================================================================
; 全局快捷键注册与动态绑定
; ==============================================================================
RegisterAllHotkeys() {
    static registeredList := []
    
    for hk in registeredList {
        try Hotkey(hk, "Off")
    }
    registeredList := []

    cfg := SettingsUI.LoadConfig()
    hkMap := cfg.Has("hotkeys") ? cfg["hotkeys"] : Map()

    hkShowBar := hkMap.Has("show_bar") ? hkMap["show_bar"] : "!y"
    hkSettings := hkMap.Has("settings") ? hkMap["settings"] : "!s"

    if (hkShowBar != "") {
        try {
            Hotkey(hkShowBar, (*) => FloatBar.Show(), "On")
            registeredList.Push(hkShowBar)
        }
    }

    if (hkSettings != "") {
        try {
            Hotkey(hkSettings, (*) => SettingsUI.Show(), "On")
            registeredList.Push(hkSettings)
        }
    }
}

; 注册设置变更回调
SettingsUI.onHotkeysUpdatedCallback := RegisterAllHotkeys

; 初始化注册全局按键
RegisterAllHotkeys()

; 静默检查更新
AppUpdater.Check(true)

; 启动时直接在前台展示设置中心界面
SettingsUI.Show()