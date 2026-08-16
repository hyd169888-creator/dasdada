#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent(true)

#Include AI_Translate.ahk
#Include Settings_UI.ahk
#Include Float_Bar.ahk
#Include Updater.ahk

; ==============================================================================
; 系统托盘图标与菜单配置
; ==============================================================================
InitTrayMenu() {
    A_IconTip := "AI 智能打字翻译"
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("🖥️ 打开设置中心", (*) => SettingsUI.Show())
    tray.Add("🔄 检查更新", (*) => AppUpdater.Check(false))
    tray.Add()
    tray.Add("❌ 退出程序", (*) => ExitApp())
    tray.Default := "🖥️ 打开设置中心"
}

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

; 1. 初始化托盘与快捷键
InitTrayMenu()
SettingsUI.onHotkeysUpdatedCallback := RegisterAllHotkeys
RegisterAllHotkeys()

; 2. 优先呼出并完整加载主界面
SettingsUI.Show()

; 3. 严格在主程序完全加载并显示后，立即发起更新检查
AppUpdater.StartAutoCheck()